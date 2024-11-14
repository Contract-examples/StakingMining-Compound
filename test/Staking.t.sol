// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console2.sol";
import "forge-std/Test.sol";
import "../src/Staking.sol";
import "../src/RNT.sol";

contract StakingTest is Test {
    Staking public staking;
    RNT public rnt;

    function setUp() public { }
}
