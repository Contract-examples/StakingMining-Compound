// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@solady/utils/SafeTransferLib.sol";

contract StakingMining is ReentrancyGuard, Ownable, Pausable {
    // custom errors
    error InvalidAmount();
    error InvalidLockIndex();
    error CannotStakeZero();
    error NoLockedTokens();

    // events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event EsRNTConverted(address indexed user, uint256 amount, uint256 receivedAmount);

    // RNT token
    IERC20 public rnt;

    // stake info
    struct StakeInfo {
        uint256 stakedAmount; // staked amount
        uint256 lastRewardTime; // last reward time
    }

    // esRNT lock info
    struct LockInfo {
        uint256 amount; // lock amount
        uint256 lockTime; // lock time
    }

    // user stake info
    mapping(address => StakeInfo) public stakeInfos;
    // user lock info
    mapping(address => LockInfo[]) public lockInfos;

    // lock period
    uint256 public constant LOCK_PERIOD = 30 days;
    // daily reward rate 1RNT = 1esRNT
    uint256 public constant DAILY_REWARD_RATE = 1e18;

    constructor(address _rnt) Ownable(msg.sender) {
        rnt = IERC20(_rnt);
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
        info.stakedAmount += amount;

        emit Staked(msg.sender, amount);
    }

    // unstake RNT
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        StakeInfo storage info = stakeInfos[msg.sender];
        if (amount == 0 || amount > info.stakedAmount) revert InvalidAmount();

        // claim the reward first
        _claimReward();

        // transfer RNT from this contract to user
        SafeTransferLib.safeTransfer(address(rnt), msg.sender, amount);

        // update staked amount
        info.stakedAmount -= amount;

        emit Withdrawn(msg.sender, amount);
    }

    // claim esRNT reward
    function claimReward() external nonReentrant whenNotPaused {
        _claimReward();
    }

    // internal function: calculate and distribute reward
    function _claimReward() internal {
        StakeInfo storage info = stakeInfos[msg.sender];
        if (info.stakedAmount == 0) return;

        uint256 pendingTime = block.timestamp - info.lastRewardTime;
        // avoid duplicate rewards in the same block
        if (pendingTime == 0) return;

        // calculate reward based on staked amount and time
        // daily reward rate = DAILY_REWARD_RATE (1e18 = 100%)
        uint256 reward = (info.stakedAmount * pendingTime * DAILY_REWARD_RATE) / (1 days * 1e18);

        if (reward != 0) {
            lockInfos[msg.sender].push(LockInfo({ amount: reward, lockTime: block.timestamp }));

            info.lastRewardTime = block.timestamp;
            emit RewardClaimed(msg.sender, reward);
        }
    }

    // convert esRNT to RNT
    function convertEsRNTtoRNT(uint256 lockIndex) external nonReentrant whenNotPaused {
        if (lockIndex >= lockInfos[msg.sender].length) revert InvalidLockIndex();

        LockInfo storage lock = lockInfos[msg.sender][lockIndex];
        if (lock.amount == 0) revert NoLockedTokens();

        uint256 timePassed = block.timestamp - lock.lockTime;
        uint256 totalAmount = lock.amount;
        uint256 unlockedAmount;

        if (timePassed >= LOCK_PERIOD) {
            // fully unlocked
            unlockedAmount = totalAmount;
        } else {
            // linear unlock, early conversion will burn the locked part
            unlockedAmount = (totalAmount * timePassed) / LOCK_PERIOD;
        }

        // transfer RNT from this contract to user
        SafeTransferLib.safeTransfer(address(rnt), msg.sender, unlockedAmount);

        // clear the lock record first to prevent reentrancy
        lock.amount = 0;

        emit EsRNTConverted(msg.sender, totalAmount, unlockedAmount);
    }

    // view function: pending reward
    function pendingReward(address user) external view returns (uint256) {
        StakeInfo memory info = stakeInfos[user];
        if (info.stakedAmount == 0) return 0;

        // 1 RNT = 1 esRNT per day
        return info.stakedAmount;
    }

    // view function: total locked esRNT
    function getTotalLockedEsRNT(address user) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < lockInfos[user].length; i++) {
            total += lockInfos[user][i].amount;
        }
        return total;
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
