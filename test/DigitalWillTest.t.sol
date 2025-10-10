// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DigitalWill} from "../src/DigitalWill.sol";

contract DigitalWillTest is Test {
    DigitalWill public digitalWill;

    address public grantor_;
    address public randomUser_;

    // Events to test
    event CheckIn(uint256 timestamp);

    function setUp() public {
        grantor_ = makeAddr("grantor");

        // Deploy contract as grantor
        vm.prank(grantor_);
        digitalWill = new DigitalWill();
    }

    // Deploy contract
    function testDeployContract() public view {
        assertEq(
            digitalWill.grantor(),
            grantor_,
            "Grantor should be set correctly"
        );
        assertEq(
            digitalWill.lastCheckIn(),
            block.timestamp,
            "Last check-in should be set correctly"
        );
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.ACTIVE)
        );
    }

    // Check in

    function testCheckInWithNotGrantor() public {
        vm.prank(randomUser_);
        vm.expectRevert("You are not the grantor");
        digitalWill.checkIn();
    }

    function testCheckInRevertsWhenNotActive() public {
        // Note: This test assumes there will be a way to change the contract state
        // Since the current contract doesn't have methods to change state,
        // we'll need to manually set it using vm.store for testing purposes

        // Arrange - Set contract state to CLAIMABLE (1)
        // The state variable is at slot 2 (grantor=0, lastCheckIn=1, state=2)
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        vm.expectRevert("Contract must be active");
        vm.prank(grantor_);
        digitalWill.checkIn();
    }

    function testCheckInSuccessfully() public {
        uint256 checkInTime = block.timestamp;

        vm.prank(grantor_);
        digitalWill.checkIn();

        assertEq(
            digitalWill.lastCheckIn(),
            checkInTime,
            "lastCheckIn should be updated to current timestamp"
        );
    }

    function testCheckInEmitsEvent() public {
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit CheckIn(expectedTimestamp);

        vm.prank(grantor_);
        digitalWill.checkIn();
    }

    function testCheckInMultipleCheckIns() public {
        // First check-in
        vm.prank(grantor_);
        digitalWill.checkIn();
        uint256 firstCheckIn = digitalWill.lastCheckIn();

        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);

        // Second check-in
        vm.prank(grantor_);
        digitalWill.checkIn();
        uint256 secondCheckIn = digitalWill.lastCheckIn();

        assertGt(
            secondCheckIn,
            firstCheckIn,
            "Second check-in should have later timestamp"
        );
        assertEq(
            secondCheckIn,
            block.timestamp,
            "Second check-in should match current block timestamp"
        );
    }

    // Fuzzing

    // checkIn
    function testFuzzCheckInUpdatesTimestamp(uint256 timeWarp) public {
        // Bound the time warp to reasonable values (0 to 365 days)
        timeWarp = bound(timeWarp, 0, 365 days);

        // Warp to future time
        vm.warp(block.timestamp + timeWarp);

        vm.prank(grantor_);
        digitalWill.checkIn();

        assertEq(
            digitalWill.lastCheckIn(),
            block.timestamp,
            "lastCheckIn should match current timestamp"
        );
    }
}
