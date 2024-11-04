// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { StakingMining } from "../src/StakingMining.sol";
import { EsRNT } from "../src/EsRNT.sol";
import { RNT } from "../src/RNT.sol";

contract StakingMiningTest is Test {
    StakingMining public stakingMining;
    RNT public rnt;
    EsRNT public esRnt;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_MINT = 10_000 * 1e18;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // deploy RNT token
        vm.startPrank(owner);
        rnt = new RNT();

        // deploy staking mining contract
        // 30 days lock period
        // 1e18 means (1RNT = 1esRNT)
        stakingMining = new StakingMining(address(rnt), 30 days, 1e18);
        // get esRNT contract address
        esRnt = stakingMining.esRnt();

        // mint enough RNT for esRNT conversion
        rnt.mint(address(esRnt), 1_000_000 * 1e18);
        vm.stopPrank();

        // mint enough RNT for user1 and user2
        vm.startPrank(owner);
        rnt.mint(user1, INITIAL_MINT);
        rnt.mint(user2, INITIAL_MINT);
        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(address(stakingMining.rnt()), address(rnt));
        assertEq(stakingMining.owner(), owner);
        assertEq(address(stakingMining.esRnt()), address(esRnt));
    }

    function test_Stake() public {
        uint256 stakeAmount = 1000 * 1e18;

        // approve and stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);

        // verify stake status
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

        // unstake partial
        uint256 unstakeAmount = 400 * 1e18;
        stakingMining.unstake(unstakeAmount);

        // verify unstake status
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

        // verify pending reward
        uint256 pendingReward = stakingMining.pendingReward(user1);
        assertEq(pendingReward, stakeAmount);
        vm.stopPrank();
    }

    function test_ClaimReward() public {
        uint256 stakeAmount = 1000 * 1e18;

        // stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);

        // skip 1 day
        skip(1 days);

        // claim reward
        stakingMining.claimReward();

        // verify lock info
        assertEq(stakingMining.esRnt().getTotalLocked(user1), stakeAmount);
        vm.stopPrank();
    }

    // alternative way to claim reward
    function test_ClaimReward_Alternative() public {
        uint256 stakeAmount = 1000 * 1e18;

        // stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);

        // skip 1 day
        skip(1 days);

        // claim reward
        stakingMining.claimReward();

        // verify lock info
        (, uint256 totalLocked,) = stakingMining.getUserInfo(user1);
        assertEq(totalLocked, stakeAmount);
        vm.stopPrank();
    }

    function test_ConvertEsRNT() public {
        uint256 stakeAmount = 1000 * 1e18;

        // stake and wait 1 day
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);
        skip(1 days);

        // claim reward
        stakingMining.claimReward();
        uint256 initialBalance = rnt.balanceOf(user1);

        // wait 15 days and convert esRNT
        skip(15 days);
        esRnt.convert(0);

        // verify converted RNT amount (should be about 50%)
        uint256 expectedRNT = (stakeAmount * 15 days) / esRnt.lockPeriod();
        assertApproxEqRel(
            rnt.balanceOf(user1) - initialBalance,
            expectedRNT,
            0.01e18 // allow 1% error
        );
        vm.stopPrank();
    }

    function test_ConvertEsRNTAfterFullPeriod() public {
        uint256 stakeAmount = 1000 * 1e18;

        // stake and wait 1 day
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount);
        skip(1 days);

        // claim reward
        stakingMining.claimReward();
        uint256 initialBalance = rnt.balanceOf(user1);

        // wait full lock period and convert esRNT
        skip(30 days);
        esRnt.convert(0);

        // verify received RNT amount
        assertEq(rnt.balanceOf(user1) - initialBalance, stakeAmount);
        vm.stopPrank();
    }

    function testFuzz_Stake(uint256 amount) public {
        // ensure stake amount is reasonable
        amount = bound(amount, 1e18, INITIAL_MINT);

        vm.startPrank(user1);
        rnt.approve(address(stakingMining), amount);
        stakingMining.stake(amount);

        (uint256 stakedAmount,) = stakingMining.stakeInfos(user1);
        assertEq(stakedAmount, amount);
        vm.stopPrank();
    }

    function testFuzz_UnstakePartial(uint256 stakeAmount, uint256 unstakeAmount) public {
        // ensure stake and unstake amounts are reasonable
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
