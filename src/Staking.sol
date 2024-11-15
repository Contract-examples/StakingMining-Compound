// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../lib/forge-std/src/console.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./RNT.sol";
import "./interfaces/IStaking.sol";

contract Staking is IStaking, ReentrancyGuard, Ownable {
    // Custom errors
    error ZeroStake();
    error ZeroWithdraw();
    error InsufficientBalance();
    error ETHTransferFailed();
    error ZeroAddress();

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    RNT public immutable rnt;

    uint256 public totalStaked;
    uint256 public lastUpdateBlock;
    uint256 public accRewardPerShare;

    mapping(address => uint256) public userStakeAmount;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public userRewardDebt;

    uint256 private constant PRECISION = 1e24;

    constructor(address _initialOwner, address _rnt) Ownable(_initialOwner) {
        if (_rnt == address(0)) revert ZeroAddress();
        rnt = RNT(_rnt);
        lastUpdateBlock = block.number;
    }

    modifier updateReward() {
        // Final = Principal * (1 + rate)^time
        uint256 blocksSinceLastUpdate = block.number - lastUpdateBlock;
        if (blocksSinceLastUpdate > 0 && totalStaked > 0) {
            uint256 reward = blocksSinceLastUpdate * rnt.REWARD_PER_BLOCK();
            uint256 rewardPerShare = (reward * PRECISION * PRECISION) / (totalStaked * PRECISION);
            accRewardPerShare += rewardPerShare;
        }
        lastUpdateBlock = block.number;

        if (userStakeAmount[msg.sender] > 0) {
            uint256 pending = (userStakeAmount[msg.sender] * accRewardPerShare * PRECISION) / (PRECISION * PRECISION)
                - userRewardDebt[msg.sender];
            if (pending > 0) {
                rewards[msg.sender] += pending;
            }
            userRewardDebt[msg.sender] =
                (userStakeAmount[msg.sender] * accRewardPerShare * PRECISION) / (PRECISION * PRECISION);
        }
        _;
    }

    function stake() external payable override nonReentrant updateReward {
        if (msg.value == 0) revert ZeroStake();

        totalStaked += msg.value;
        userStakeAmount[msg.sender] += msg.value;

        emit Staked(msg.sender, msg.value);
    }

    function unstake(uint256 amount) external override nonReentrant updateReward {
        if (amount == 0) revert ZeroWithdraw();
        if (userStakeAmount[msg.sender] < amount) revert InsufficientBalance();

        totalStaked -= amount;
        userStakeAmount[msg.sender] -= amount;

        (bool success,) = msg.sender.call{ value: amount }("");
        if (!success) revert ETHTransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    function claim() external override nonReentrant updateReward {
        uint256 totalReward = rewards[msg.sender];
        if (totalReward > 0) {
            rewards[msg.sender] = 0;
            rnt.mint(msg.sender, totalReward);
            emit RewardPaid(msg.sender, totalReward);
        }
    }

    function earned(address account) public view override returns (uint256) {
        uint256 currentAccRewardPerShare = accRewardPerShare;

        if (block.number > lastUpdateBlock && totalStaked > 0) {
            uint256 blocksSinceLastUpdate = block.number - lastUpdateBlock;
            uint256 reward = blocksSinceLastUpdate * rnt.REWARD_PER_BLOCK();
            uint256 rewardPerShare = (reward * PRECISION * PRECISION) / (totalStaked * PRECISION);
            currentAccRewardPerShare += rewardPerShare;
        }

        uint256 pending = (userStakeAmount[account] * currentAccRewardPerShare * PRECISION) / (PRECISION * PRECISION)
            - userRewardDebt[account];
        return rewards[account] + pending;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return userStakeAmount[account];
    }

    receive() external payable { }
}
