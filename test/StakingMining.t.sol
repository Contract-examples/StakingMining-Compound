// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { StakingMining } from "../src/StakingMining.sol";
import { RNT } from "../src/RNT.sol";

contract StakingMiningTest is Test {
    StakingMining public stakingMining;
    RNT public rnt;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_MINT = 10_000 * 1e18;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.startPrank(owner);
        rnt = new RNT();
        stakingMining = new StakingMining(address(rnt));
        vm.stopPrank();

        // mint RNT
        vm.startPrank(owner);
        rnt.mint(user1, INITIAL_MINT);
        rnt.mint(user2, INITIAL_MINT);
        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(address(stakingMining.rnt()), address(rnt));
        assertEq(stakingMining.owner(), owner);
    }

    function test_Stake() public {
        uint256 stakeAmount = 1000 * 1e18;

        // staking
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);

        // stating ok?
        (uint256 stakedAmount,) = stakingMining.stakeInfos(user1);
        assertEq(stakedAmount, stakeAmount);
        assertEq(rnt.balanceOf(address(stakingMining)), stakeAmount);
        vm.stopPrank();
    }

    function test_StakeZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(StakingMining.CannotStakeZero.selector);
        stakingMining.stake(0);
    }

    function test_Unstake() public {
        uint256 stakeAmount = 1000 * 1e18;

        // stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);

        // unstake partial amount
        uint256 unstakeAmount = 400 * 1e18;
        stakingMining.unstake(unstakeAmount);

        // verify unstake state
        (uint256 remainingStaked,) = stakingMining.stakeInfos(user1);
        assertEq(remainingStaked, stakeAmount - unstakeAmount);
        assertEq(rnt.balanceOf(address(stakingMining)), stakeAmount - unstakeAmount);
        vm.stopPrank();
    }

    function test_UnstakeInvalidAmount() public {
        uint256 stakeAmount = 1000 * 1e18;

        // stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);

        // try to unstake more than staked amount
        vm.expectRevert(StakingMining.InvalidAmount.selector);
        stakingMining.unstake(stakeAmount + 1);
        vm.stopPrank();
    }

    function test_RewardCalculation() public {
        uint256 stakeAmount = 1000 * 1e18;

        // stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);

        // skip 1 day
        skip(1 days);

        // verify pending reward - 1 esRNT per staked RNT per day
        uint256 pendingReward = stakingMining.pendingReward(user1);
        assertEq(pendingReward, stakeAmount);
        vm.stopPrank();
    }

    function test_ClaimReward() public {
        uint256 stakeAmount = 1000 * 1e18;

        // mint enough RNT for rewards
        vm.prank(owner);
        rnt.mint(address(stakingMining), 1_000_000 * 1e18);

        // stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);

        // skip 1 day
        skip(1 days);

        // claim reward
        stakingMining.claimReward();

        // verify lock record - 1 esRNT per staked RNT per day
        uint256 expectedReward = stakeAmount * 1; // 1 day's reward
        assertEq(stakingMining.getTotalLockedEsRNT(user1), expectedReward);
        vm.stopPrank();
    }

    function test_ConvertEsRNTtoRNT() public {
        uint256 stakeAmount = 1000 * 1e18;

        // mint enough RNT for rewards
        vm.prank(owner);
        rnt.mint(address(stakingMining), 1_000_000 * 1e18);

        // stake and wait 1 day
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);
        skip(1 days);

        // claim reward
        stakingMining.claimReward();
        uint256 expectedReward = stakeAmount * 1; // 1 day's reward

        // wait 15 days and convert half of esRNT
        skip(15 days);
        uint256 initialBalance = rnt.balanceOf(user1);
        stakingMining.convertEsRNTtoRNT(0);

        // verify the amount of RNT received (should be about 50%)
        uint256 expectedRNT = (expectedReward * 15 days) / stakingMining.LOCK_PERIOD();
        assertApproxEqRel(
            rnt.balanceOf(user1) - initialBalance,
            expectedRNT,
            0.01e18 // allow 1% error
        );
        vm.stopPrank();
    }

    function test_ConvertEsRNTtoRNTAfterFullPeriod() public {
        uint256 stakeAmount = 1000 * 1e18;

        // mint enough RNT for rewards
        vm.prank(owner);
        rnt.mint(address(stakingMining), 1_000_000 * 1e18);

        // stake and wait 1 day
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);
        skip(1 days);

        // claim reward
        stakingMining.claimReward();
        uint256 expectedReward = stakeAmount * 1; // 1 day's reward

        // wait full lock period and convert
        skip(30 days);
        uint256 initialBalance = rnt.balanceOf(user1);
        stakingMining.convertEsRNTtoRNT(0);

        // verify the amount of RNT received
        assertEq(rnt.balanceOf(user1) - initialBalance, expectedReward);
        vm.stopPrank();
    }

    function testFuzz_Stake(uint256 amount) public {
        // ensure the stake amount is within a reasonable range
        amount = bound(amount, 1e18, INITIAL_MINT);

        vm.startPrank(user1);
        rnt.approve(address(stakingMining), amount);
        stakingMining.stake(amount);

        (uint256 stakedAmount,) = stakingMining.stakeInfos(user1);
        assertEq(stakedAmount, amount);
        vm.stopPrank();
    }

    function testFuzz_UnstakePartial(uint256 stakeAmount, uint256 unstakeAmount) public {
        // ensure the stake and unstake amounts are within a reasonable range
        stakeAmount = bound(stakeAmount, 1e18, INITIAL_MINT);
        unstakeAmount = bound(unstakeAmount, 1, stakeAmount);

        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);

        stakingMining.unstake(unstakeAmount);

        (uint256 remainingStaked,) = stakingMining.stakeInfos(user1);
        assertEq(remainingStaked, stakeAmount - unstakeAmount);
        vm.stopPrank();
    }
}
