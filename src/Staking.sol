// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RNT.sol";
import "./interfaces/IStaking.sol";

contract Staking is IStaking, ReentrancyGuardTransient, Ownable {
    // Custom errors
    error ZeroStake();
    error ZeroWithdraw();
    error InsufficientBalance();
    error ETHTransferFailed();
    error ZeroAddress();

    // events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    RNT public immutable rnt;

    uint256 public totalStaked;
    uint256 public lastUpdateBlock; // last update block
    uint256 public rewardPerTokenStored; // reward per token stored

    mapping(address => uint256) public userStakeAmount; // user stake amount
    mapping(address => uint256) public rewards; // user rewards
    mapping(address => uint256) public userRewardPerTokenPaid; // user reward per token paid

    constructor(address _initialOwner, address _rnt) Ownable(_initialOwner) {
        if (_rnt == address(0)) revert ZeroAddress();
        rnt = RNT(_rnt);
        lastUpdateBlock = block.number;
    }

    // update reward
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateBlock = block.number;

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // calculate reward per token
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (((block.number - lastUpdateBlock) * rnt.REWARD_PER_BLOCK() * 1e18) / totalStaked);
    }

    // stake ETH
    function stake() external payable override nonReentrant updateReward(msg.sender) {
        if (msg.value == 0) revert ZeroStake();

        totalStaked += msg.value;
        userStakeAmount[msg.sender] += msg.value;

        emit Staked(msg.sender, msg.value);
    }

    // withdraw ETH
    function unstake(uint256 amount) external override nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroWithdraw();
        if (userStakeAmount[msg.sender] < amount) revert InsufficientBalance();

        totalStaked -= amount;
        userStakeAmount[msg.sender] -= amount;

        // transfer ETH to user
        (bool success,) = msg.sender.call{ value: amount }("");
        if (!success) revert ETHTransferFailed();

        emit Withdrawn(msg.sender, amount);
    }

    // claim RNT reward
    function claim() external override nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rnt.mint(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // view user stake amount
    function balanceOf(address account) external view override returns (uint256) {
        return userStakeAmount[account];
    }

    // calculate earned reward
    function earned(address account) public view override returns (uint256) {
        return
            (userStakeAmount[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18) + rewards[account];
    }

    receive() external payable { }
}
