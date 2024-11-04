// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console2.sol";
import "forge-std/Test.sol";
import "../src/StakingMining.sol";
import "../src/EsRNT.sol";
import "../src/RNT.sol";

contract StakingMiningTest is Test {
    StakingMining public stakingMining;
    RNT public rnt;
    EsRNT public esRnt;

    address public owner;
    address public user1;
    uint256 public user1PrivateKey;
    address public user2;

    uint256 public constant INITIAL_MINT = 10_000 * 1e18;

    function setUp() public {
        owner = makeAddr("owner");

        user1PrivateKey = 0x3389;
        user1 = vm.addr(user1PrivateKey);

        user2 = makeAddr("user2");

        vm.startPrank(owner);

        // deploy contracts
        rnt = new RNT();
        esRnt = new EsRNT();
        stakingMining = new StakingMining(
            address(rnt),
            address(esRnt),
            1e18 // reward rate
        );

        // initialize EsRNT
        esRnt.initialize(address(rnt), 30 days, address(stakingMining));

        // mint RNT
        rnt.mint(address(esRnt), 1_000_000 * 1e18);
        rnt.mint(user1, INITIAL_MINT);
        rnt.mint(user2, INITIAL_MINT);

        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(address(stakingMining.stakingToken()), address(rnt));
        assertEq(stakingMining.owner(), owner);
        assertEq(address(stakingMining.esToken()), address(esRnt));
    }

    function test_Stake() public {
        uint256 stakeAmount = 1000 * 1e18;

        // approve and stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount, 0, 0, bytes32(0), bytes32(0));

        // verify stake status
        (uint256 stakedAmount,) = stakingMining.stakeInfos(user1);
        assertEq(stakedAmount, stakeAmount);
        assertEq(rnt.balanceOf(address(stakingMining)), stakeAmount);
        vm.stopPrank();
    }

    function test_StakePermit() public {
        uint256 stakeAmount = 1000 * 1e18;

        // approve and stake
        vm.startPrank(user1);

        uint256 deadline = block.timestamp + 1 hours;
        console2.log("deadline: %d", deadline);

        // get the nonce (set 0 for testing)
        uint256 nonce = 0;
        console2.log("nonce:", nonce);

        // build the permit data
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                user1,
                address(stakingMining),
                stakeAmount,
                nonce,
                deadline
            )
        );
        console2.log("structHash: %s", Strings.toHexString(uint256(structHash)));

        // build the digest
        bytes32 domainSeparator = rnt.DOMAIN_SEPARATOR();
        console2.log("domainSeparator: %s", Strings.toHexString(uint256(domainSeparator)));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        console2.log("digest: %s", Strings.toHexString(uint256(digest)));

        // sign the digest with user1's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, digest);
        console2.log("v: %s", Strings.toHexString(uint256(v)));
        console2.log("r: %s", Strings.toHexString(uint256(r)));
        console2.log("s: %s", Strings.toHexString(uint256(s)));

        stakingMining.stake(stakeAmount, deadline, v, r, s);

        // verify stake status
        (uint256 stakedAmount,) = stakingMining.stakeInfos(user1);
        assertEq(stakedAmount, stakeAmount);
        assertEq(rnt.balanceOf(address(stakingMining)), stakeAmount);
        vm.stopPrank();
    }

    function test_StakeZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(StakingMining.CannotStakeZero.selector);
        stakingMining.stake(0, 0, 0, bytes32(0), bytes32(0));
    }

    function test_Unstake() public {
        uint256 stakeAmount = 1000 * 1e18;

        // stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount, 0, 0, bytes32(0), bytes32(0));

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
        stakingMining.stake(stakeAmount, 0, 0, bytes32(0), bytes32(0));

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
        stakingMining.stake(stakeAmount, 0, 0, bytes32(0), bytes32(0));

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
        stakingMining.stake(stakeAmount, 0, 0, bytes32(0), bytes32(0));

        // skip 1 day
        skip(1 days);

        // claim reward
        stakingMining.claimReward();

        // verify lock info
        assertEq(stakingMining.esToken().getTotalLocked(user1), stakeAmount);
        vm.stopPrank();
    }

    // alternative way to claim reward
    function test_ClaimReward_Alternative() public {
        uint256 stakeAmount = 1000 * 1e18;

        // stake
        vm.startPrank(user1);
        rnt.approve(address(stakingMining), stakeAmount);
        stakingMining.stake(stakeAmount, 0, 0, bytes32(0), bytes32(0));

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
        stakingMining.stake(stakeAmount, 0, 0, bytes32(0), bytes32(0));
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
        stakingMining.stake(stakeAmount, 0, 0, bytes32(0), bytes32(0));
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
        stakingMining.stake(amount, 0, 0, bytes32(0), bytes32(0));

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
        stakingMining.stake(stakeAmount, 0, 0, bytes32(0), bytes32(0));

        stakingMining.unstake(unstakeAmount);

        (uint256 remainingStaked,) = stakingMining.stakeInfos(user1);
        assertEq(remainingStaked, stakeAmount - unstakeAmount);
        vm.stopPrank();
    }
}
