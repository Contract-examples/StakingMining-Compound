// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Staking Interface
 */
interface IStaking {
    /**
     * @dev stake eth
     */
    function stake() external payable;

    /**
     * @dev withdraw eth
     * @param amount withdraw amount
     */
    function unstake(uint256 amount) external;

    /**
     * @dev claim rnt reward
     */
    function claim() external;

    /**
     * @dev get stake eth amount
     * @param account stake account
     * @return stake eth amount
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev get pending rnt reward
     * @param account stake account
     * @return pending rnt reward
     */
    function earned(address account) external view returns (uint256);
}
