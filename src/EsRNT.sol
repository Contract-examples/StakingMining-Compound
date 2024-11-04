// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@solady/utils/SafeTransferLib.sol";

// TODO: EIP-2612
contract EsRNT is ReentrancyGuard, ERC20, Ownable {
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

    // only StakingMining contract can mint esRNT
    // Owner = StakingMining contract
    function mint(address to, uint256 amount) external onlyOwner {
        // mint
        _mint(to, amount);

        // we know amount will not overflow totalSupply
        unchecked {
            lockInfos[to].push(LockInfo({ amount: amount, lockTime: block.timestamp }));
        }

        emit Locked(to, amount, block.timestamp);
    }

    // convert esRNT to RNT
    function convert(uint256 lockIndex) external nonReentrant {
        LockInfo[] storage userLocks = lockInfos[msg.sender];
        if (lockIndex >= userLocks.length) revert InvalidLockIndex();

        LockInfo storage lock = userLocks[lockIndex];
        uint256 lockedAmount = lock.amount;
        if (lockedAmount == 0) revert NoLockedTokens();

        uint256 timePassed;
        unchecked {
            // timestamp will not overflow
            timePassed = block.timestamp - lock.lockTime;
        }

        uint256 unlockedAmount;
        // if lock period is passed, unlock all
        if (timePassed >= lockPeriod) {
            unlockedAmount = lockedAmount;
        } else {
            // if lock period is not passed, unlock partially
            unchecked {
                // since timePassed < lockPeriod, it will not overflow
                unlockedAmount = (lockedAmount * timePassed) / lockPeriod;
            }
        }

        // burn esRNT
        _burn(msg.sender, lockedAmount);

        // transfer RNT to user
        SafeTransferLib.safeTransfer(address(rnt), msg.sender, unlockedAmount);

        // clear lock info
        lock.amount = 0;

        emit Converted(msg.sender, lockedAmount, unlockedAmount);
    }

    // view function: get total locked amount
    function getTotalLocked(address user) external view returns (uint256) {
        LockInfo[] storage userLocks = lockInfos[user];
        uint256 total;
        uint256 length = userLocks.length;

        for (uint256 i; i < length;) {
            unchecked {
                total += userLocks[i].amount;
                ++i;
            }
        }
        return total;
    }

    // view function: get user lock info
    function getLockInfo(address user) external view returns (LockInfo[] memory) {
        return lockInfos[user];
    }
}
