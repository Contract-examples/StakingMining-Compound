// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console2.sol";
import { Staking } from "../src/Staking.sol";
import { RNT } from "../src/RNT.sol";

contract StakingTest is Test {
    Staking public staking;
    RNT public rnt;

    address public owner;
    address public alice;
    address public bob;

    uint256 public constant INITIAL_ETH = 100 ether;
    uint256 public constant PRECISION = 1e24;

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(owner);
        rnt = new RNT();
        staking = new Staking(owner, address(rnt));
        rnt.setStakingContract(address(staking));
        vm.stopPrank();

        vm.deal(alice, INITIAL_ETH);
        vm.deal(bob, INITIAL_ETH);
    }

    function test_SingleUserStaking() public {
        // set block number
        vm.roll(1);

        // Alice stake 10 ETH
        vm.startPrank(alice);
        staking.stake{ value: 10 ether }();
        vm.stopPrank();

        // advance 50 blocks
        vm.roll(51);

        // calculate expected reward: 50 blocks * 10 RNT/block = 500 RNT
        uint256 expectedReward = 50 * 10 ether;
        uint256 actualReward = staking.earned(alice);

        console.log("Expected reward:", expectedReward);
        console.log("Actual reward:", actualReward);

        assertEq(actualReward, expectedReward, "Incorrect reward calculation");

        // claim reward
        vm.prank(alice);
        staking.claim();
        assertEq(rnt.balanceOf(alice), expectedReward, "Incorrect reward distribution");
    }

    function test_MultipleUsersStaking() public {
        // set block number
        vm.roll(1);

        // Alice stake 10 ETH
        vm.prank(alice);
        staking.stake{ value: 10 ether }();

        // Bob stake 5 ETH
        vm.prank(bob);
        staking.stake{ value: 5 ether }();

        // advance 50 blocks
        vm.roll(51);

        // calculate expected reward:
        // total reward = 50 blocks * 10 RNT/block = 500 RNT
        // Alice ratio = 10/(10+5) = 2/3
        // Bob ratio = 5/(10+5) = 1/3
        uint256 totalReward = 50 * 10 ether;
        // multiply first, then divide to avoid precision loss
        uint256 aliceExpectedReward = (totalReward * 10 * 1e18) / (15 * 1e18); // Alice=2/3
        uint256 bobExpectedReward = (totalReward * 5 * 1e18) / (15 * 1e18); // Bob=1/3

        console.log("Total reward:", totalReward);
        console.log("Alice expected:", aliceExpectedReward);
        console.log("Bob expected:", bobExpectedReward);
        console.log("Alice actual:", staking.earned(alice));
        console.log("Bob actual:", staking.earned(bob));

        assertEq(staking.earned(alice), aliceExpectedReward, "Incorrect Alice reward");
        assertEq(staking.earned(bob), bobExpectedReward, "Incorrect Bob reward");

        // claim reward
        vm.prank(alice);
        staking.claim();
        vm.prank(bob);
        staking.claim();

        assertEq(rnt.balanceOf(alice), aliceExpectedReward, "Incorrect Alice RNT balance");
        assertEq(rnt.balanceOf(bob), bobExpectedReward, "Incorrect Bob RNT balance");
    }

    function test_StakeUnstakeRewards() public {
        // set block number
        vm.roll(1);

        // Alice stake 10 ETH
        vm.prank(alice);
        staking.stake{ value: 10 ether }();

        // advance 25 blocks
        vm.roll(26);

        // calculate first phase expected reward: 25 blocks * 10 RNT/block = 250 RNT
        uint256 firstPhaseExpectedReward = 25 * 10 ether;

        // claim first phase reward
        vm.prank(alice);
        staking.claim();

        // record first phase reward
        uint256 firstPhaseReward = rnt.balanceOf(alice);
        console.log("First phase reward claimed:", firstPhaseReward);

        // Alice withdraw 5 ETH
        vm.prank(alice);
        staking.unstake(5 ether);

        // advance 25 blocks
        vm.roll(51);

        // calculate second phase expected reward: 25 blocks * 10 RNT/block * (5/10) = 125 RNT
        // multiply first, then divide to avoid precision loss
        uint256 secondPhaseExpectedReward = (25 * 10 ether * 5 * 1e18) / (10 * 1e18);
        console.log("Second phase expected reward:", secondPhaseExpectedReward);

        // claim second phase reward
        vm.prank(alice);
        staking.claim();

        // verify total reward
        uint256 totalReward = rnt.balanceOf(alice);
        uint256 totalExpectedReward = firstPhaseExpectedReward + secondPhaseExpectedReward;

        console.log("\n=== Final Results ===");
        console.log("First phase reward:", firstPhaseReward);
        console.log("Second phase reward:", totalReward - firstPhaseReward);
        console.log("Total reward:", totalReward);
        console.log("Expected total reward:", totalExpectedReward);

        assertEq(totalReward, totalExpectedReward, "Incorrect total reward");
    }

    receive() external payable { }
}
