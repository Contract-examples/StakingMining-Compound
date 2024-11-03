// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { RNT } from "../src/RNT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract RNTTest is Test {
    RNT public rnt;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.prank(owner);
        rnt = new RNT();
    }

    function test_InitialState() public {
        assertEq(rnt.name(), "RNT");
        assertEq(rnt.symbol(), "RNT");
        assertEq(rnt.decimals(), 18);
        assertEq(rnt.totalSupply(), rnt.INITIAL_SUPPLY());
        assertEq(rnt.balanceOf(owner), rnt.INITIAL_SUPPLY());
        assertEq(rnt.owner(), owner);
    }

    function test_Mint() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        // not owner can't mint
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        rnt.mint(user1, mintAmount);

        // owner can mint
        vm.startPrank(owner);
        rnt.mint(user1, mintAmount);
        assertEq(rnt.balanceOf(user1), mintAmount);
        vm.stopPrank();
    }

    function test_MintExceedsMaxSupply() public {
        uint256 remainingSupply = rnt.remainingMintableSupply();
        uint256 exceedAmount = remainingSupply + 1;

        vm.startPrank(owner);

        vm.expectRevert(
            abi.encodeWithSelector(RNT.ExceedsMaxSupply.selector, rnt.MAX_SUPPLY(), rnt.totalSupply(), exceedAmount)
        );
        rnt.mint(user1, exceedAmount);
        vm.stopPrank();
    }

    function test_RemainingMintableSupply() public {
        uint256 expectedRemaining = rnt.MAX_SUPPLY() - rnt.INITIAL_SUPPLY();
        assertEq(rnt.remainingMintableSupply(), expectedRemaining);

        // mint some tokens and check the remaining mintable supply
        uint256 mintAmount = 1000 * 10 ** 18;
        vm.prank(owner);
        rnt.mint(user1, mintAmount);

        assertEq(rnt.remainingMintableSupply(), expectedRemaining - mintAmount);
    }

    function test_Transfer() public {
        uint256 transferAmount = 1000 * 10 ** 18;

        // give user1 some tokens
        vm.prank(owner);
        rnt.transfer(user1, transferAmount);
        assertEq(rnt.balanceOf(user1), transferAmount);

        // user1 transfer to user2
        vm.prank(user1);
        rnt.transfer(user2, transferAmount);
        assertEq(rnt.balanceOf(user2), transferAmount);
        assertEq(rnt.balanceOf(user1), 0);
    }

    function testFuzz_Mint(uint256 amount) public {
        // ensure the mint amount is in a reasonable range
        uint256 maxMintable = rnt.remainingMintableSupply();
        amount = bound(amount, 1, maxMintable);

        vm.prank(owner);
        rnt.mint(user1, amount);
        assertEq(rnt.balanceOf(user1), amount);
    }

    function testFuzz_Transfer(uint256 amount) public {
        // ensure the transfer amount is in a reasonable range
        amount = bound(amount, 0, rnt.INITIAL_SUPPLY());

        vm.assume(amount <= rnt.balanceOf(owner));

        vm.prank(owner);
        rnt.transfer(user1, amount);
        assertEq(rnt.balanceOf(user1), amount);
        assertEq(rnt.balanceOf(owner), rnt.INITIAL_SUPPLY() - amount);
    }
}
