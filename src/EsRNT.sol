// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// TODO: EIP-2612
contract EsRNT is ERC20, Ownable {
    using SafeERC20 for IERC20;

    // custom errors
    error InvalidLockIndex();
    error NoLockedTokens();
    error ZeroAddress();

    // events
    event Locked(address indexed user, uint256 amount, uint256 lockTime);
    event Converted(address indexed user, uint256 amount, uint256 receivedAmount);

    // RNT token
    IERC20 public immutable rnt;

    // lock period
    uint256 public immutable lockPeriod;

    // lock info
    struct LockInfo {
        uint256 amount;
        uint256 lockTime;
    }

    // user => locks
    mapping(address => LockInfo[]) public lockInfos;

    constructor(address _rnt, uint256 _lockPeriod) ERC20("esRNT", "esRNT") Ownable(msg.sender) {
        if (_rnt == address(0)) revert ZeroAddress();
        rnt = IERC20(_rnt);
        lockPeriod = _lockPeriod;
    }

    // only staking mining contract can mint esRNT
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        lockInfos[to].push(LockInfo({ amount: amount, lockTime: block.timestamp }));

        emit Locked(to, amount, block.timestamp);
    }

    function convert(uint256 lockIndex) external {
        if (lockIndex >= lockInfos[msg.sender].length) revert InvalidLockIndex();

        LockInfo storage lock = lockInfos[msg.sender][lockIndex];
        if (lock.amount == 0) revert NoLockedTokens();

        uint256 timePassed = block.timestamp - lock.lockTime;
        uint256 totalAmount = lock.amount;
        uint256 unlockedAmount;

        if (timePassed >= lockPeriod) {
            unlockedAmount = totalAmount;
        } else {
            unlockedAmount = (totalAmount * timePassed) / lockPeriod;
        }

        // burn esRNT
        _burn(msg.sender, totalAmount);

        // transfer RNT to user
        rnt.safeTransfer(msg.sender, unlockedAmount);

        // clear lock info
        lock.amount = 0;

        emit Converted(msg.sender, totalAmount, unlockedAmount);
    }

    // view function: get total locked amount
    function getTotalLocked(address user) external view returns (uint256) {
        uint256 total = 0;
        uint256 length = lockInfos[user].length;
        for (uint256 i = 0; i < length;) {
            total += lockInfos[user][i].amount;
            unchecked {
                i++;
            }
        }
        return total;
    }

    // view function: get user lock info
    function getLockInfo(address user) external view returns (LockInfo[] memory) {
        return lockInfos[user];
    }
}
