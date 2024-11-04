// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@solady/utils/SafeTransferLib.sol";

// no need for EIP-2612
contract EsRNT is ReentrancyGuard, ERC20, Ownable, Initializable {
    // custom errors
    error InvalidToken();
    error InvalidLockIndex();
    error NoLockedTokens();
    error TransferNotAllowed();
    error ApprovalNotAllowed();

    // events
    event Initialized(address stakingToken, uint256 lockPeriod, address owner);
    event Locked(address indexed user, uint256 amount, uint256 lockTime);
    event Converted(address indexed user, uint256 amount, uint256 receivedAmount);

    // RNT token
    IERC20 public stakingToken;

    // lock period
    uint256 public lockPeriod;

    // lock info
    struct LockInfo {
        uint256 amount;
        uint256 lockTime;
    }

    // user => locks
    mapping(address => LockInfo[]) public lockInfos;

    // constructor
    constructor() ERC20("esRNT", "esRNT") Ownable(msg.sender) { }

    // initialize
    function initialize(address _stakingToken, uint256 _lockPeriod, address _stakingMining) external initializer {
        if (_stakingToken == address(0) || _stakingMining == address(0)) revert InvalidToken();

        stakingToken = IERC20(_stakingToken);
        lockPeriod = _lockPeriod;
        _transferOwnership(_stakingMining);
        emit Initialized(_stakingToken, _lockPeriod, _stakingMining);
    }

    // only StakingMining contract can mint esRNT
    // Owner = StakingMining contract
    function mint(address to, uint256 amount) external onlyOwner {
        // mint
        _mint(to, amount);

        // add to lock info
        lockInfos[to].push(LockInfo({ amount: amount, lockTime: block.timestamp }));

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
        SafeTransferLib.safeTransfer(address(stakingToken), msg.sender, unlockedAmount);

        // clear lock info
        lock.amount = 0;

        emit Converted(msg.sender, lockedAmount, unlockedAmount);
    }

    // view function: get total locked amount
    function getTotalLocked(address user) external view returns (uint256) {
        LockInfo[] memory userLocks = lockInfos[user];
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

    // disable transfer
    function transfer(address, uint256) public virtual override returns (bool) {
        revert TransferNotAllowed();
    }

    // disable transferFrom
    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert TransferNotAllowed();
    }

    // disable approve
    function approve(address, uint256) public virtual override returns (bool) {
        revert TransferNotAllowed();
    }
}
