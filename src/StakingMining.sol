// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@solady/utils/SafeTransferLib.sol";
import "./interfaces/IEsToken.sol";

contract StakingMining is ReentrancyGuard, Ownable, Pausable {
    // custom errors
    error InvalidAmount();
    error InvalidLockIndex();
    error CannotStakeZero();
    error NoLockedTokens();
    error InvalidRewardRate();
    error InvalidToken();
    error InsufficientAllowance();

    // events
    event StakingInitialized(address indexed stakingToken, address indexed esToken, uint256 rewardRate);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event StakingTokenSet(address indexed stakingToken);
    event EsTokenSet(address indexed esToken);

    // tokens
    IERC20 public stakingToken;
    IERC20Permit public stakingTokenPermit;
    IEsToken public esToken;

    // stake info
    struct StakeInfo {
        uint256 stakedAmount;
        uint256 lastRewardTime;
    }

    // user stake info
    mapping(address => StakeInfo) public stakeInfos;

    // daily reward rate (default=1e18)
    uint256 public rewardRate;

    constructor(address _stakingToken, address _esToken, uint256 _rewardRate) Ownable(msg.sender) {
        if (_stakingToken == address(0) || _esToken == address(0)) revert InvalidToken();
        if (_rewardRate == 0) revert InvalidRewardRate();

        stakingToken = IERC20(_stakingToken);
        if (_isPermitSupported(_stakingToken)) {
            stakingTokenPermit = IERC20Permit(_stakingToken);
        }

        esToken = IEsToken(_esToken);
        rewardRate = _rewardRate;

        emit StakingInitialized(_stakingToken, _esToken, _rewardRate);
    }

    // set new reward rate
    function setRewardRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) revert InvalidRewardRate();

        uint256 oldRate = rewardRate;
        rewardRate = newRate;

        emit RewardRateUpdated(oldRate, newRate);
    }

    // set staking token
    function setStakingToken(address _stakingToken) external onlyOwner {
        if (_stakingToken == address(0)) revert InvalidToken();
        stakingToken = IERC20(_stakingToken);
        emit StakingTokenSet(_stakingToken);
    }

    // set esToken
    function setEsToken(address _esToken) external onlyOwner {
        if (_esToken == address(0)) revert InvalidToken();
        esToken = IEsToken(_esToken);
        emit EsTokenSet(_esToken);
    }

    // stake RNT
    function stake(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        nonReentrant
        whenNotPaused
    {
        if (amount == 0) revert CannotStakeZero();

        StakeInfo storage info = stakeInfos[msg.sender];

        // first stake, we just set the last reward time
        if (info.stakedAmount == 0) {
            info.lastRewardTime = block.timestamp;
        } else {
            // not first stake, claim reward first
            _claimReward();
        }

        // support permit
        if (stakingTokenPermit != IERC20Permit(address(0)) && deadline != 0) {
            stakingTokenPermit.permit(msg.sender, address(this), amount, deadline, v, r, s);
        }

        // transfer from user to this
        SafeTransferLib.safeTransferFrom(address(stakingToken), msg.sender, address(this), amount);

        unchecked {
            info.stakedAmount += amount;
        }

        emit Staked(msg.sender, amount);
    }

    // unstake RNT
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        StakeInfo storage info = stakeInfos[msg.sender];
        if (amount == 0 || amount > info.stakedAmount) revert InvalidAmount();

        // claim reward first
        _claimReward();

        // transfer from this to user
        SafeTransferLib.safeTransfer(address(stakingToken), msg.sender, amount);

        unchecked {
            info.stakedAmount -= amount;
        }

        emit Unstaked(msg.sender, amount);
    }

    // claim esRNT reward
    function claimReward() external nonReentrant whenNotPaused {
        _claimReward();
    }

    // emergency withdraw (when paused)
    function emergencyWithdraw() external nonReentrant whenPaused {
        StakeInfo storage info = stakeInfos[msg.sender];
        uint256 amount = info.stakedAmount;
        if (amount == 0) revert InvalidAmount();

        // transfer staking token to user
        uint256 amountBefore = stakingToken.balanceOf(msg.sender);
        SafeTransferLib.safeTransfer(address(stakingToken), msg.sender, amount);
        uint256 amountAfter = stakingToken.balanceOf(msg.sender);
        if (amountAfter - amountBefore != amount) revert InvalidAmount();

        info.stakedAmount = 0;
        info.lastRewardTime = 0;

        emit EmergencyWithdrawn(msg.sender, amount);
    }

    // internal function: calculate and distribute reward
    function _claimReward() internal {
        StakeInfo storage info = stakeInfos[msg.sender];
        if (info.stakedAmount == 0) return;

        uint256 currentTime = block.timestamp;
        uint256 pendingTime;
        unchecked {
            pendingTime = currentTime - info.lastRewardTime;
        }
        if (pendingTime == 0) return;

        unchecked {
            uint256 reward = info.stakedAmount * rewardRate / 1e18;
            reward = reward * pendingTime / 1 days;
            if (reward != 0) {
                esToken.mint(msg.sender, reward);
                info.lastRewardTime = currentTime;
                emit RewardClaimed(msg.sender, reward);
            }
        }
    }

    // this is a helper function to check if the recipient is a contract
    function _isContract(address account) internal view returns (bool) {
        // if the code size is greater than 0, then the account is a contract
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    // check if the token supports permit
    function _isPermitSupported(address _token) internal view returns (bool) {
        if (!_isContract(_token)) {
            return false;
        }
        try IERC20Permit(_token).DOMAIN_SEPARATOR() returns (bytes32) {
            return true;
        } catch {
            return false;
        }
    }

    // view function: pending reward
    function pendingReward(address user) external view returns (uint256) {
        StakeInfo memory info = stakeInfos[user];
        return info.stakedAmount == 0 ? 0 : info.stakedAmount;
    }

    // view function: get user info
    function getUserInfo(address user)
        external
        view
        returns (StakeInfo memory stakeInfo, uint256 totalLocked, IEsToken.LockInfo[] memory lockInfo)
    {
        return (stakeInfos[user], esToken.getTotalLocked(user), esToken.getLockInfo(user));
    }

    // pause
    function pause() external onlyOwner {
        _pause();
    }

    // unpause
    function unpause() external onlyOwner {
        _unpause();
    }
}
