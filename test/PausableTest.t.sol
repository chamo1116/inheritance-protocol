// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DigitalWillFactory} from "../src/DigitalWillFactory.sol";

contract PausableTest is Test {
    DigitalWillFactory public willFactory;

    address public owner;
    address public grantor = address(0x1);
    address public beneficiary = address(0x2);
    address public nonOwner = address(0x3);

    uint256 constant HEARTBEAT_INTERVAL = 30 days;

    function setUp() public {
        owner = address(this);
        willFactory = new DigitalWillFactory();
    }

    /**
     * Test that only owner can pause
     */
    function testOnlyOwnerCanPause() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        willFactory.pause();
    }

    /**
     * Test that only owner can unpause
     */
    function testOnlyOwnerCanUnpause() public {
        willFactory.pause();

        vm.prank(nonOwner);
        vm.expectRevert();
        willFactory.unpause();
    }

    /**
     * Test that owner can pause successfully
     */
    function testOwnerCanPause() public {
        assertFalse(willFactory.paused());

        willFactory.pause();

        assertTrue(willFactory.paused());
    }

    /**
     * Test that owner can unpause successfully
     */
    function testOwnerCanUnpause() public {
        willFactory.pause();
        assertTrue(willFactory.paused());

        willFactory.unpause();

        assertFalse(willFactory.paused());
    }

    /**
     * Test that createWill is blocked when paused
     */
    function testCreateWillRevertsWhenPaused() public {
        willFactory.pause();

        vm.prank(grantor);
        vm.expectRevert();
        willFactory.createWill(HEARTBEAT_INTERVAL);
    }

    /**
     * Test that createWill works after unpause
     */
    function testCreateWillWorksAfterUnpause() public {
        willFactory.pause();
        willFactory.unpause();

        vm.prank(grantor);
        willFactory.createWill(HEARTBEAT_INTERVAL);

        (,, DigitalWillFactory.ContractState state,) = willFactory.getWillInfo(grantor);
        assertEq(uint256(state), uint256(DigitalWillFactory.ContractState.ACTIVE));
    }

    /**
     * Test that checkIn is blocked when paused
     */
    function testCheckInRevertsWhenPaused() public {
        vm.prank(grantor);
        willFactory.createWill(HEARTBEAT_INTERVAL);

        willFactory.pause();

        vm.prank(grantor);
        vm.expectRevert();
        willFactory.checkIn();
    }

    /**
     * Test that depositETH is blocked when paused
     */
    function testDepositETHRevertsWhenPaused() public {
        vm.prank(grantor);
        willFactory.createWill(HEARTBEAT_INTERVAL);

        willFactory.pause();

        vm.deal(grantor, 1 ether);
        vm.prank(grantor);
        vm.expectRevert();
        willFactory.depositETH{value: 1 ether}(beneficiary);
    }

    /**
     * Test that depositETH works after unpause
     */
    function testDepositETHWorksAfterUnpause() public {
        vm.prank(grantor);
        willFactory.createWill(HEARTBEAT_INTERVAL);

        willFactory.pause();
        willFactory.unpause();

        vm.deal(grantor, 1 ether);
        vm.prank(grantor);
        willFactory.depositETH{value: 1 ether}(beneficiary);

        assertEq(willFactory.getAssetCount(grantor), 1);
    }

    /**
     * Test that claimAsset is blocked when paused
     */
    function testClaimAssetRevertsWhenPaused() public {
        // Setup: Create will and deposit ETH
        vm.prank(grantor);
        willFactory.createWill(HEARTBEAT_INTERVAL);

        vm.deal(grantor, 1 ether);
        vm.prank(grantor);
        willFactory.depositETH{value: 1 ether}(beneficiary);

        // Fast forward to make will claimable
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        // Pause contract
        willFactory.pause();

        // Try to claim - should revert
        vm.prank(beneficiary);
        vm.expectRevert();
        willFactory.claimAsset(grantor, 0);
    }

    /**
     * Test that claimAsset works after unpause
     */
    function testClaimAssetWorksAfterUnpause() public {
        // Setup: Create will and deposit ETH
        vm.prank(grantor);
        willFactory.createWill(HEARTBEAT_INTERVAL);

        vm.deal(grantor, 1 ether);
        vm.prank(grantor);
        willFactory.depositETH{value: 1 ether}(beneficiary);

        // Fast forward to make will claimable
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        // Pause and unpause
        willFactory.pause();
        willFactory.unpause();

        // Claim should work
        uint256 beneficiaryBalanceBefore = beneficiary.balance;
        vm.prank(beneficiary);
        willFactory.claimAsset(grantor, 0);

        assertEq(beneficiary.balance - beneficiaryBalanceBefore, 1 ether);
    }

    /**
     * Test that extendHeartbeat is blocked when paused
     */
    function testExtendHeartbeatRevertsWhenPaused() public {
        vm.prank(grantor);
        willFactory.createWill(HEARTBEAT_INTERVAL);

        willFactory.pause();

        vm.prank(grantor);
        vm.expectRevert();
        willFactory.extendHeartbeat(HEARTBEAT_INTERVAL * 2);
    }

    /**
     * Test that view functions still work when paused
     */
    function testViewFunctionsWorkWhenPaused() public {
        vm.prank(grantor);
        willFactory.createWill(HEARTBEAT_INTERVAL);

        vm.deal(grantor, 1 ether);
        vm.prank(grantor);
        willFactory.depositETH{value: 1 ether}(beneficiary);

        willFactory.pause();

        // View functions should still work
        (uint256 lastCheckIn, uint256 interval, DigitalWillFactory.ContractState state, uint256 assetCount) =
            willFactory.getWillInfo(grantor);

        assertGt(lastCheckIn, 0);
        assertEq(interval, HEARTBEAT_INTERVAL);
        assertEq(uint256(state), uint256(DigitalWillFactory.ContractState.ACTIVE));
        assertEq(assetCount, 1);

        assertEq(willFactory.getAssetCount(grantor), 1);
        assertTrue(willFactory.isClaimable(grantor) == false);
    }

    /**
     * Test multiple pause/unpause cycles
     */
    function testMultiplePauseUnpauseCycles() public {
        // First cycle
        assertFalse(willFactory.paused());
        willFactory.pause();
        assertTrue(willFactory.paused());
        willFactory.unpause();
        assertFalse(willFactory.paused());

        // Second cycle
        willFactory.pause();
        assertTrue(willFactory.paused());
        willFactory.unpause();
        assertFalse(willFactory.paused());

        // Third cycle
        willFactory.pause();
        assertTrue(willFactory.paused());
        willFactory.unpause();
        assertFalse(willFactory.paused());
    }

    /**
     * Test that contract can be deployed in unpaused state
     */
    function testContractDeploysInUnpausedState() public {
        DigitalWillFactory newFactory = new DigitalWillFactory();
        assertFalse(newFactory.paused());
    }
}
