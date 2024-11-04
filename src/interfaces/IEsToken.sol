// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IEsToken {
    struct LockInfo {
        uint256 amount;
        uint256 lockTime;
    }

    function mint(address to, uint256 amount) external;
    function convert(uint256 lockIndex) external;
    function getTotalLocked(address user) external view returns (uint256);
    function getLockInfo(address user) external view returns (LockInfo[] memory);
}
