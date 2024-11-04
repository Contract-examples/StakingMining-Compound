// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@solady/utils/SafeTransferLib.sol";
import "./EsRNT.sol";

contract StakingMining is ReentrancyGuard, Ownable, Pausable {
    // custom errors
    error InvalidAmount();
    error InvalidLockIndex();
    error CannotStakeZero();
    error NoLockedTokens();
    error InvalidRewardRate();

    // events
    event EsRNTCreated(address indexed esRnt);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    // RNT token
    IERC20 public immutable rnt;
    EsRNT public immutable esRnt;

    // stake info
    struct StakeInfo {
        uint256 stakedAmount; // staked amount
        uint256 lastRewardTime; // last reward time
    }

    // user stake info
    mapping(address => StakeInfo) public stakeInfos;

    // daily reward rate 1RNT = 1esRNT (default=1e18)
    uint256 public rewardRate;

    constructor(address _rnt, uint256 _lockPeriod, uint256 _rewardRate) Ownable(msg.sender) {
        if (_rewardRate == 0) revert InvalidRewardRate();

        rnt = IERC20(_rnt);
        esRnt = new EsRNT(_rnt, _lockPeriod);
        rewardRate = _rewardRate;

        emit EsRNTCreated(address(esRnt));
    }

    // set new reward rate
    function setRewardRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) revert InvalidRewardRate();

        uint256 oldRate = rewardRate;
        rewardRate = newRate;

        emit RewardRateUpdated(oldRate, newRate);
    }

    // stake RNT
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert CannotStakeZero();

        StakeInfo storage info = stakeInfos[msg.sender];

        // if it's the first stake, initialize the last reward time
        if (info.stakedAmount == 0) {
            info.lastRewardTime = block.timestamp;
        } else {
            // if it's not the first stake, claim the previous reward first
            _claimReward();
        }

        // transfer RNT from user to this contract (need approve first)
        SafeTransferLib.safeTransferFrom(address(rnt), msg.sender, address(this), amount);

        // update staked amount
        unchecked {
            info.stakedAmount += amount;
        }

        emit Staked(msg.sender, amount);
    }

    // unstake RNT
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        StakeInfo storage info = stakeInfos[msg.sender];
        if (amount == 0 || amount > info.stakedAmount) revert InvalidAmount();

        // claim the reward finally
        _claimReward();

        // transfer RNT from this contract to user
        SafeTransferLib.safeTransfer(address(rnt), msg.sender, amount);

        // update staked amount
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

        // transfer RNT from this contract to user
        uint256 amountBefore = rnt.balanceOf(msg.sender);
        SafeTransferLib.safeTransfer(address(rnt), msg.sender, amount);
        uint256 amountAfter = rnt.balanceOf(msg.sender);
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
        // avoid duplicate rewards in the same block
        if (pendingTime == 0) return;

        // calculate reward based on staked amount and time
        // daily reward rate = rewardRate (1e18 = 100%)
        unchecked {
            uint256 reward = info.stakedAmount * rewardRate / 1e18;
            reward = reward * pendingTime / 1 days;
            if (reward != 0) {
                // mint esRNT to user
                esRnt.mint(msg.sender, reward);
                info.lastRewardTime = currentTime;
                emit RewardClaimed(msg.sender, reward);
            }
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
        returns (StakeInfo memory stakeInfo, uint256 totalLocked, EsRNT.LockInfo[] memory lockInfo)
    {
        return (stakeInfos[user], esRnt.getTotalLocked(user), esRnt.getLockInfo(user));
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
