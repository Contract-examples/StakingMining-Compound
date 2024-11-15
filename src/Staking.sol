// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../lib/forge-std/src/console.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./RNT.sol";
import "./interfaces/IStaking.sol";

contract Staking is IStaking, ReentrancyGuardTransient, Ownable {
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
        // update global reward
        uint256 blocksSinceLastUpdate = block.number - lastUpdateBlock;
        if (blocksSinceLastUpdate > 0 && totalStaked > 0) {
            uint256 reward = blocksSinceLastUpdate * rnt.REWARD_PER_BLOCK();
            accRewardPerShare += (reward * PRECISION) / totalStaked;
        }
        lastUpdateBlock = block.number;

        // update user reward
        if (userStakeAmount[msg.sender] > 0) {
            uint256 pending = (userStakeAmount[msg.sender] * accRewardPerShare) / PRECISION - userRewardDebt[msg.sender];
            if (pending > 0) {
                rewards[msg.sender] += pending;
            }
            // update user reward debt
            userRewardDebt[msg.sender] = (userStakeAmount[msg.sender] * accRewardPerShare) / PRECISION;
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

        // update stake amount
        totalStaked -= amount;
        userStakeAmount[msg.sender] -= amount;

        // transfer ETH
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

        // calculate new reward
        if (block.number > lastUpdateBlock && totalStaked > 0) {
            uint256 blocksSinceLastUpdate = block.number - lastUpdateBlock;
            uint256 reward = blocksSinceLastUpdate * rnt.REWARD_PER_BLOCK();
            currentAccRewardPerShare += (reward * PRECISION) / totalStaked;
        }

        // calculate pending reward
        uint256 pending = (userStakeAmount[account] * currentAccRewardPerShare) / PRECISION - userRewardDebt[account];
        return rewards[account] + pending;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return userStakeAmount[account];
    }

    receive() external payable { }
}
