// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./Base.sol";

contract BeneficiaryAcceptanceTest is Base {
    address public grantor;
    address public beneficiary1;
    address public beneficiary2;
    address public nonBeneficiary;

    uint256 constant HEARTBEAT_INTERVAL = 30 days;
    uint256 constant DEPOSIT_AMOUNT = 1 ether;

    event BeneficiaryAccepted(address indexed grantor, address indexed beneficiary);
    event BeneficiaryRejected(address indexed grantor, address indexed beneficiary);

    function setUp() public {
        factory = new DigitalWillFactory();

        // Create users with labels using Base helpers
        grantor = createUser("Grantor");
        beneficiary1 = createUser("Beneficiary1");
        beneficiary2 = createUser("Beneficiary2");
        nonBeneficiary = createUser("NonBeneficiary");

        // Setup: Create will and deposit assets using Base helpers
        fundUser(grantor, 10 ether);
        createWillFor(grantor, HEARTBEAT_INTERVAL);
        depositETH(grantor, DEPOSIT_AMOUNT, beneficiary1);
        depositETH(grantor, DEPOSIT_AMOUNT, beneficiary2);
    }

    // ============ Accept Beneficiary Tests ============

    function test_AcceptBeneficiary_Success() public {
        vm.prank(beneficiary1);
        vm.expectEmit(true, true, false, false);
        emit BeneficiaryAccepted(grantor, beneficiary1);
        factory.acceptBeneficiary(grantor);

        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary1));
    }

    function test_AcceptBeneficiary_MultipleBeneficiaries() public {
        // Beneficiary1 accepts
        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor);

        // Beneficiary2 accepts
        vm.prank(beneficiary2);
        factory.acceptBeneficiary(grantor);

        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary1));
        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary2));
    }

    function test_AcceptBeneficiary_RevertIf_WillDoesNotExist() public {
        address nonExistentGrantor = address(0x999);

        vm.prank(beneficiary1);
        vm.expectRevert("Will does not exist");
        factory.acceptBeneficiary(nonExistentGrantor);
    }

    function test_AcceptBeneficiary_RevertIf_NotDesignatedAsBeneficiary() public {
        vm.prank(nonBeneficiary);
        vm.expectRevert("Not designated as beneficiary");
        factory.acceptBeneficiary(grantor);
    }

    function test_AcceptBeneficiary_RevertIf_AlreadyAccepted() public {
        vm.startPrank(beneficiary1);
        factory.acceptBeneficiary(grantor);

        vm.expectRevert("Already accepted");
        factory.acceptBeneficiary(grantor);
        vm.stopPrank();
    }

    function test_AcceptBeneficiary_AfterBeingReassigned() public {
        // Grantor assigns another asset to beneficiary1
        vm.prank(grantor);
        factory.depositETH{value: DEPOSIT_AMOUNT}(beneficiary1);

        // Beneficiary1 accepts once (covers all assets from this grantor)
        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor);

        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary1));
    }

    // ============ Reject Beneficiary Tests ============

    function test_RejectBeneficiary_Success() public {
        // First accept
        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor);
        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary1));

        // Then reject
        vm.prank(beneficiary1);
        vm.expectEmit(true, true, false, false);
        emit BeneficiaryRejected(grantor, beneficiary1);
        factory.rejectBeneficiary(grantor);

        assertFalse(factory.hasBeneficiaryAccepted(grantor, beneficiary1));
    }

    function test_RejectBeneficiary_WithoutPriorAcceptance() public {
        assertFalse(factory.hasBeneficiaryAccepted(grantor, beneficiary1));

        vm.prank(beneficiary1);
        factory.rejectBeneficiary(grantor);

        assertFalse(factory.hasBeneficiaryAccepted(grantor, beneficiary1));
    }

    function test_RejectBeneficiary_RevertIf_WillDoesNotExist() public {
        address nonExistentGrantor = address(0x999);

        vm.prank(beneficiary1);
        vm.expectRevert("Will does not exist");
        factory.rejectBeneficiary(nonExistentGrantor);
    }

    function test_RejectBeneficiary_RevertIf_NotDesignatedAsBeneficiary() public {
        vm.prank(nonBeneficiary);
        vm.expectRevert("Not designated as beneficiary");
        factory.rejectBeneficiary(grantor);
    }

    function test_RejectBeneficiary_CanReAcceptAfterRejection() public {
        vm.startPrank(beneficiary1);

        // Accept
        factory.acceptBeneficiary(grantor);
        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary1));

        // Reject
        factory.rejectBeneficiary(grantor);
        assertFalse(factory.hasBeneficiaryAccepted(grantor, beneficiary1));

        // Re-accept
        factory.acceptBeneficiary(grantor);
        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary1));

        vm.stopPrank();
    }

    // ============ Claim Asset Integration Tests ============

    function test_ClaimAsset_RequiresAcceptance() public {
        // Fast forward to make will claimable
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(beneficiary1);
        factory.updateState(grantor);

        // Try to claim without accepting - should fail
        vm.prank(beneficiary1);
        vm.expectRevert("Beneficiary must accept designation first");
        factory.claimAsset(grantor, 0);
    }

    function test_ClaimAsset_SuccessAfterAcceptance() public {
        // Beneficiary accepts using helper
        acceptBeneficiary(beneficiary1, grantor);

        // Make will claimable using helper
        makeWillClaimable(grantor, HEARTBEAT_INTERVAL);

        // Now claim should succeed
        uint256 balanceBefore = beneficiary1.balance;

        // Claim using helper
        claimAsset(beneficiary1, grantor, 0);

        uint256 balanceAfter = beneficiary1.balance;
        assertEq(balanceAfter - balanceBefore, DEPOSIT_AMOUNT);
    }

    function test_ClaimAsset_FailsAfterRejection() public {
        // Beneficiary accepts then rejects
        vm.startPrank(beneficiary1);
        factory.acceptBeneficiary(grantor);
        factory.rejectBeneficiary(grantor);
        vm.stopPrank();

        // Fast forward to make will claimable
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(beneficiary1);
        factory.updateState(grantor);

        // Claim should fail
        vm.prank(beneficiary1);
        vm.expectRevert("Beneficiary must accept designation first");
        factory.claimAsset(grantor, 0);
    }

    function test_ClaimAsset_OnlyAcceptedBeneficiaryCanClaim() public {
        // Only beneficiary1 accepts
        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor);

        // Fast forward to make will claimable
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(beneficiary1);
        factory.updateState(grantor);

        // Beneficiary1 can claim
        vm.prank(beneficiary1);
        factory.claimAsset(grantor, 0);

        // Beneficiary2 cannot claim (hasn't accepted)
        vm.prank(beneficiary2);
        vm.expectRevert("Beneficiary must accept designation first");
        factory.claimAsset(grantor, 1);
    }

    // ============ Update Beneficiary Integration Tests ============

    function test_UpdateBeneficiary_NewBeneficiaryNeedsToAccept() public {
        // Beneficiary1 accepts
        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor);

        // Grantor changes beneficiary from beneficiary1 to beneficiary2
        vm.prank(grantor);
        factory.updateBeneficiary(0, beneficiary2);

        // Fast forward to make will claimable
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(beneficiary2);
        factory.updateState(grantor);

        // Beneficiary2 tries to claim without accepting - should fail
        vm.prank(beneficiary2);
        vm.expectRevert("Beneficiary must accept designation first");
        factory.claimAsset(grantor, 0);

        // Beneficiary2 accepts and can now claim
        vm.prank(beneficiary2);
        factory.acceptBeneficiary(grantor);

        vm.prank(beneficiary2);
        factory.claimAsset(grantor, 0);
    }

    function test_UpdateBeneficiary_OldBeneficiaryAcceptanceStillValid() public {
        // Give beneficiary1 another asset (index 2)
        vm.prank(grantor);
        factory.depositETH{value: DEPOSIT_AMOUNT}(beneficiary1);

        // Beneficiary1 accepts
        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor);

        // Grantor changes one asset (index 0) to beneficiary2 but beneficiary1 still has another (index 2)
        vm.prank(grantor);
        factory.updateBeneficiary(0, beneficiary2);

        // Fast forward to make will claimable
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        // Update state (use grantor to avoid issues)
        vm.prank(grantor);
        factory.updateState(grantor);

        // Beneficiary1 can still claim their remaining asset (index 2)
        vm.prank(beneficiary1);
        factory.claimAsset(grantor, 2);
    }

    // ============ Contract Beneficiary Tests ============

    function test_ContractBeneficiary_MustAlsoAccept() public {
        // Create a contract beneficiary using helper
        address contractBeneficiary = createContractBeneficiary();

        // Grantor approves and deposits using helpers
        approveContractBeneficiary(grantor, contractBeneficiary);
        depositETH(grantor, DEPOSIT_AMOUNT, contractBeneficiary);

        // Make will claimable using helper
        makeWillClaimable(grantor, HEARTBEAT_INTERVAL);

        // Contract tries to claim without accepting - should fail
        vm.prank(contractBeneficiary);
        vm.expectRevert("Beneficiary must accept designation first");
        factory.claimAsset(grantor, 2); // Asset index 2 because we already have 2 assets from setUp

        // Contract accepts using helper
        acceptBeneficiary(contractBeneficiary, grantor);

        // Now contract can claim using helper
        claimAsset(contractBeneficiary, grantor, 2);
    }

    // ============ Edge Cases ============

    function test_AcceptBeneficiary_AfterWillBecomesClaimable() public {
        // Fast forward to make will claimable
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(beneficiary1);
        factory.updateState(grantor);

        // Beneficiary can still accept after will becomes claimable
        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor);

        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary1));

        // And can claim
        vm.prank(beneficiary1);
        factory.claimAsset(grantor, 0);
    }

    function test_HasBeneficiaryAccepted_ReturnsFalseByDefault() public view {
        assertFalse(factory.hasBeneficiaryAccepted(grantor, beneficiary1));
        assertFalse(factory.hasBeneficiaryAccepted(grantor, beneficiary2));
    }

    function test_AcceptBeneficiary_ForClaimedAsset_StillWorks() public {
        // Beneficiary1 accepts
        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor);

        // Fast forward and claim
        vm.warp(block.timestamp + HEARTBEAT_INTERVAL + 1);

        vm.prank(beneficiary1);
        factory.updateState(grantor);

        vm.prank(beneficiary1);
        factory.claimAsset(grantor, 0);

        // Beneficiary1 still shows as accepted even after claiming
        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary1));
    }

    function test_AcceptBeneficiary_WithMultipleGrantors() public {
        // Create another grantor with a will
        address grantor2 = address(0x5);
        vm.deal(grantor2, 10 ether);

        vm.startPrank(grantor2);
        factory.createWill(HEARTBEAT_INTERVAL);
        factory.depositETH{value: DEPOSIT_AMOUNT}(beneficiary1);
        vm.stopPrank();

        // Beneficiary accepts from grantor1
        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor);

        // Beneficiary must separately accept from grantor2
        assertFalse(factory.hasBeneficiaryAccepted(grantor2, beneficiary1));

        vm.prank(beneficiary1);
        factory.acceptBeneficiary(grantor2);

        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary1));
        assertTrue(factory.hasBeneficiaryAccepted(grantor2, beneficiary1));
    }
}
