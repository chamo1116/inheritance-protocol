// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {DigitalWillFactory} from "../src/DigitalWillFactory.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 contract for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Mock ERC721 contract for testing
contract MockERC721 is ERC721 {
    uint256 private _tokenIdCounter;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to) public returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        _mint(to, tokenId);
        return tokenId;
    }

    function mintWithId(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

// Mock contract to use as beneficiary
contract MockBeneficiary {
    // Simple contract to test contract beneficiary approval
    function doSomething() public pure returns (bool) {
        return true;
    }
}

contract RevokeContractBeneficiaryTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNft;
    MockBeneficiary public mockBeneficiary;

    address public grantor;
    address public eoaBeneficiary;
    address public randomUser;

    // Events to test
    event ContractBeneficiaryRevoked(address indexed grantor, address indexed beneficiary);

    function setUp() public {
        grantor = makeAddr("grantor");
        eoaBeneficiary = makeAddr("eoaBeneficiary");
        randomUser = makeAddr("randomUser");

        // Deploy mock contracts
        mockToken = new MockERC20("MockToken", "MTK");
        mockNft = new MockERC721("MockNFT", "MNFT");
        mockBeneficiary = new MockBeneficiary();

        // Deploy factory
        factory = new DigitalWillFactory();

        // Create will for grantor
        vm.prank(grantor);
        factory.createWill(30 days);
    }

    // Test successful revocation of contract beneficiary
    function testRevokeContractBeneficiary() public {
        // First approve the contract beneficiary
        vm.startPrank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Verify it's approved
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));

        // Revoke the approval
        factory.revokeContractBeneficiary(address(mockBeneficiary));
        vm.stopPrank();

        // Verify it's no longer approved
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
    }

    // Test that revokeContractBeneficiary emits the correct event
    function testRevokeContractBeneficiaryEmitsEvent() public {
        // First approve
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Expect the revoke event
        vm.expectEmit(true, true, true, true);
        emit ContractBeneficiaryRevoked(grantor, address(mockBeneficiary));

        vm.prank(grantor);
        factory.revokeContractBeneficiary(address(mockBeneficiary));
    }

    // Test revoking a beneficiary that was never approved (should not revert)
    function testRevokeNeverApprovedBeneficiary() public {
        // Verify not approved initially
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));

        // Revoke should not revert even if never approved
        vm.prank(grantor);
        factory.revokeContractBeneficiary(address(mockBeneficiary));

        // Still not approved
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
    }

    // Test revoking the same beneficiary multiple times
    function testRevokeContractBeneficiaryMultipleTimes() public {
        // Approve first
        vm.startPrank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Revoke multiple times
        factory.revokeContractBeneficiary(address(mockBeneficiary));
        factory.revokeContractBeneficiary(address(mockBeneficiary));
        factory.revokeContractBeneficiary(address(mockBeneficiary));
        vm.stopPrank();

        // Should still be not approved
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
    }

    // Test that revokeContractBeneficiary reverts when will does not exist
    function testRevokeContractBeneficiaryRevertsWhenWillDoesNotExist() public {
        vm.prank(randomUser);
        vm.expectRevert("Will does not exist");
        factory.revokeContractBeneficiary(address(mockBeneficiary));
    }

    // Test approve, revoke, then approve again cycle
    function testApproveRevokeApproveCycle() public {
        vm.startPrank(grantor);

        // Approve
        factory.approveContractBeneficiary(address(mockBeneficiary));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));

        // Revoke
        factory.revokeContractBeneficiary(address(mockBeneficiary));
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));

        // Approve again
        factory.approveContractBeneficiary(address(mockBeneficiary));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));

        vm.stopPrank();
    }

    // Test that after revocation, deposits to contract beneficiary fail
    function testDepositFailsAfterRevocation() public {
        // Give grantor some ETH
        vm.deal(grantor, 10 ether);

        vm.startPrank(grantor);

        // Approve and deposit successfully
        factory.approveContractBeneficiary(address(mockBeneficiary));
        factory.depositEth{value: 1 ether}(address(mockBeneficiary));

        // Revoke approval
        factory.revokeContractBeneficiary(address(mockBeneficiary));

        // Try to deposit again - should fail
        vm.expectRevert("Contract beneficiary not approved. Use approveContractBeneficiary first");
        factory.depositEth{value: 1 ether}(address(mockBeneficiary));

        vm.stopPrank();
    }

    // Test revoking one of multiple approved beneficiaries
    function testRevokeOneOfMultipleBeneficiaries() public {
        MockBeneficiary mockBeneficiary2 = new MockBeneficiary();
        MockBeneficiary mockBeneficiary3 = new MockBeneficiary();

        vm.startPrank(grantor);

        // Approve multiple
        factory.approveContractBeneficiary(address(mockBeneficiary));
        factory.approveContractBeneficiary(address(mockBeneficiary2));
        factory.approveContractBeneficiary(address(mockBeneficiary3));

        // Verify all approved
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary2)));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary3)));

        // Revoke middle one
        factory.revokeContractBeneficiary(address(mockBeneficiary2));

        // Verify only middle one is revoked
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary2)));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary3)));

        vm.stopPrank();
    }

    // Test that different grantors can revoke independently
    function testDifferentGrantorsCanRevokeIndependently() public {
        address grantor2 = makeAddr("grantor2");

        // Create will for second grantor
        vm.prank(grantor2);
        factory.createWill(30 days);

        // Both grantors approve the same contract
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        vm.prank(grantor2);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Verify both have approval
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertTrue(factory.isApprovedBeneficiary(grantor2, address(mockBeneficiary)));

        // First grantor revokes
        vm.prank(grantor);
        factory.revokeContractBeneficiary(address(mockBeneficiary));

        // Only first grantor's approval should be revoked
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertTrue(factory.isApprovedBeneficiary(grantor2, address(mockBeneficiary)));
    }

    // Test revoking EOA address (should not revert, even though EOAs don't need approval)
    function testRevokeEOABeneficiary() public {
        // Revoking an EOA should not revert (even though it has no effect)
        vm.prank(grantor);
        factory.revokeContractBeneficiary(eoaBeneficiary);

        // EOA should still be considered valid (they don't need approval)
        assertTrue(factory.isApprovedBeneficiary(grantor, eoaBeneficiary));
    }

    // Test revoking zero address (should not revert)
    function testRevokeZeroAddress() public {
        // Should not revert
        vm.prank(grantor);
        factory.revokeContractBeneficiary(address(0));

        // Zero address should still be invalid
        assertFalse(factory.isApprovedBeneficiary(grantor, address(0)));
    }

    // Test that revocation doesn't affect existing deposits
    function testRevocationDoesNotAffectExistingDeposits() public {
        // Give grantor some ETH
        vm.deal(grantor, 10 ether);

        vm.startPrank(grantor);

        // Approve and deposit
        factory.approveContractBeneficiary(address(mockBeneficiary));
        factory.depositEth{value: 1 ether}(address(mockBeneficiary));

        // Verify deposit exists
        uint256 assetCount = factory.getAssetCount(grantor);
        assertEq(assetCount, 1);

        (,,,, address beneficiary,) = factory.getAsset(grantor, 0);
        assertEq(beneficiary, address(mockBeneficiary));

        // Revoke approval
        factory.revokeContractBeneficiary(address(mockBeneficiary));

        // Existing deposit should still be there
        uint256 assetCountAfter = factory.getAssetCount(grantor);
        assertEq(assetCountAfter, 1);

        (,,,, address beneficiaryAfter,) = factory.getAsset(grantor, 0);
        assertEq(beneficiaryAfter, address(mockBeneficiary));

        vm.stopPrank();
    }
}
