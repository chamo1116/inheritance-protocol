// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DigitalWill} from "../src/DigitalWill.sol";

contract DigitalWillTest is Test {
    DigitalWill public digitalWill;

    address public grantor_;
    address public randomUser_;
    address public beneficiary_;

    // Events to test
    event CheckIn(uint256 timestamp);
    event AssetDeposited(
        address indexed grantor,
        DigitalWill.AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        address beneficiary
    );

    function setUp() public {
        grantor_ = makeAddr("grantor");
        beneficiary_ = makeAddr("beneficiary");
        // Deploy contract as grantor
        vm.prank(grantor_);
        digitalWill = new DigitalWill();
    }

    // Deploy contract
    function testDeployContract() public view {
        assertEq(digitalWill.grantor(), grantor_, "Grantor should be set correctly");
        assertEq(digitalWill.lastCheckIn(), block.timestamp, "Last check-in should be set correctly");
        assertEq(uint256(digitalWill.state()), uint256(DigitalWill.ContractState.ACTIVE));
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

        assertEq(digitalWill.lastCheckIn(), checkInTime, "lastCheckIn should be updated to current timestamp");
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

        assertGt(secondCheckIn, firstCheckIn, "Second check-in should have later timestamp");
        assertEq(secondCheckIn, block.timestamp, "Second check-in should match current block timestamp");
    }

    // Deposit ETH
    function testDepositETHRevertsWhenNotGrantor() public {
        vm.startPrank(randomUser_);
        vm.deal(randomUser_, 10 ether);
        vm.expectRevert("You are not the grantor");
        digitalWill.depositETH{value: 1 ether}(beneficiary_);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroValue() public {
        vm.startPrank(grantor_);
        vm.expectRevert("Must send ETH");
        digitalWill.depositETH{value: 0}(beneficiary_);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroAddressInBeneficiary() public {
        vm.startPrank(grantor_);
        vm.deal(grantor_, 10 ether);
        vm.expectRevert("Invalid beneficiary address");

        digitalWill.depositETH{value: 1 ether}(address(0));
        vm.stopPrank();
    }

    function testDepositETHRevertsWhenNotActive() public {
        vm.startPrank(grantor_);
        vm.deal(grantor_, 10 ether);
        // Set contract state to CLAIMABLE (1)
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        vm.expectRevert("Contract must be active");
        digitalWill.depositETH{value: 1 ether}(beneficiary_);
        vm.stopPrank();
    }

    function testDepositETHSuccessfully() public {
        vm.startPrank(grantor_);
        vm.deal(grantor_, 10 ether);
        uint256 depositAmount = 5 ether;

        uint256 initialBalance = address(digitalWill).balance;

        digitalWill.depositETH{value: depositAmount}(beneficiary_);

        // Check contract balance updated
        assertEq(
            address(digitalWill).balance,
            initialBalance + depositAmount,
            "Contract balance should increase by deposit amount"
        );
        // Check beneficiaryAssets mapping updated
        uint256 assetIndex = digitalWill.beneficiaryAssets(beneficiary_, 0);
        assertEq(assetIndex, 0, "Asset index should be 0 for first asset");
        vm.stopPrank();
    }

    function testDepositETHMultipleDeposits() public {
        vm.startPrank(grantor_);

        vm.deal(grantor_, 10 ether);

        // First deposit
        digitalWill.depositETH{value: 1 ether}(beneficiary_);

        // Second deposit
        digitalWill.depositETH{value: 2 ether}(beneficiary_);

        // Third deposit
        digitalWill.depositETH{value: 3 ether}(beneficiary_);

        // Check contract balance
        assertEq(address(digitalWill).balance, 6 ether, "Contract should have 6 ETH total");

        // Check all three assets stored
        (,,, uint256 amount1,,) = digitalWill.assets(0);
        (,,, uint256 amount2,,) = digitalWill.assets(1);
        (,,, uint256 amount3,,) = digitalWill.assets(2);

        assertEq(amount1, 1 ether, "First asset amount should be 1 ETH");
        assertEq(amount2, 2 ether, "Second asset amount should be 2 ETH");
        assertEq(amount3, 3 ether, "Third asset amount should be 3 ETH");

        // Check beneficiaryAssets has all three indices
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 2), 2, "Third asset index");
        vm.stopPrank();
    }

    function testDepositETHMultipleBeneficiaries() public {
        vm.startPrank(grantor_);
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.deal(grantor_, 10 ether);

        // Deposit to different beneficiaries

        digitalWill.depositETH{value: 1 ether}(beneficiary1);

        digitalWill.depositETH{value: 2 ether}(beneficiary2);

        digitalWill.depositETH{value: 3 ether}(beneficiary3);

        // Check contract balance
        assertEq(address(digitalWill).balance, 6 ether, "Contract should have 6 ETH total");

        // Check each beneficiary has correct asset
        (,,,, address stored1,) = digitalWill.assets(0);
        (,,,, address stored2,) = digitalWill.assets(1);
        (,,,, address stored3,) = digitalWill.assets(2);

        assertEq(stored1, beneficiary1, "First beneficiary should match");
        assertEq(stored2, beneficiary2, "Second beneficiary should match");
        assertEq(stored3, beneficiary3, "Third beneficiary should match");

        // Check each beneficiary's asset mapping
        assertEq(digitalWill.beneficiaryAssets(beneficiary1, 0), 0, "Beneficiary1 asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary2, 0), 1, "Beneficiary2 asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary3, 0), 2, "Beneficiary3 asset index");
        vm.stopPrank();
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

        assertEq(digitalWill.lastCheckIn(), block.timestamp, "lastCheckIn should match current timestamp");
    }
}
