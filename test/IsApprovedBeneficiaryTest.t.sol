// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
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

contract IsApprovedBeneficiaryTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;
    MockBeneficiary public mockBeneficiary;

    address public grantor;
    address public grantor2;
    address public eoaBeneficiary;
    address public randomUser;

    function setUp() public {
        grantor = makeAddr("grantor");
        grantor2 = makeAddr("grantor2");
        eoaBeneficiary = makeAddr("eoaBeneficiary");
        randomUser = makeAddr("randomUser");

        // Deploy mock contracts
        mockToken = new MockERC20("MockToken", "MTK");
        mockNFT = new MockERC721("MockNFT", "MNFT");
        mockBeneficiary = new MockBeneficiary();

        // Deploy factory
        factory = new DigitalWillFactory();

        // Create wills for grantors
        vm.prank(grantor);
        factory.createWill(30 days);

        vm.prank(grantor2);
        factory.createWill(30 days);
    }

    // Test that EOA beneficiary is approved by default (if not zero address)
    function testEOABeneficiaryIsApprovedByDefault() public view {
        bool isApproved = factory.isApprovedBeneficiary(grantor, eoaBeneficiary);
        assertTrue(isApproved, "EOA should be approved by default");
    }

    // Test that zero address is not approved
    function testZeroAddressIsNotApproved() public view {
        bool isApproved = factory.isApprovedBeneficiary(grantor, address(0));
        assertFalse(isApproved, "Zero address should not be approved");
    }

    // Test that contract beneficiary is not approved by default
    function testContractBeneficiaryIsNotApprovedByDefault() public view {
        bool isApproved = factory.isApprovedBeneficiary(grantor, address(mockBeneficiary));
        assertFalse(isApproved, "Contract should not be approved by default");
    }

    // Test that contract beneficiary is approved after approval
    function testContractBeneficiaryIsApprovedAfterApproval() public {
        // Initially not approved
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));

        // Approve it
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Now it should be approved
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
    }

    // Test that contract beneficiary is not approved after revocation
    function testContractBeneficiaryIsNotApprovedAfterRevocation() public {
        // Approve first
        vm.startPrank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));

        // Revoke
        factory.revokeContractBeneficiary(address(mockBeneficiary));
        vm.stopPrank();

        // Should not be approved anymore
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
    }

    // Test that different grantors have independent approvals
    function testDifferentGrantorsHaveIndependentApprovals() public {
        // Grantor1 approves the contract
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Check that only grantor1's approval is set
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertFalse(factory.isApprovedBeneficiary(grantor2, address(mockBeneficiary)));

        // Grantor2 approves the same contract
        vm.prank(grantor2);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Both should have independent approvals
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertTrue(factory.isApprovedBeneficiary(grantor2, address(mockBeneficiary)));
    }

    // Test that revoking one grantor's approval doesn't affect another
    function testRevokingOneGrantorDoesNotAffectAnother() public {
        // Both approve
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        vm.prank(grantor2);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Both approved
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertTrue(factory.isApprovedBeneficiary(grantor2, address(mockBeneficiary)));

        // Grantor1 revokes
        vm.prank(grantor);
        factory.revokeContractBeneficiary(address(mockBeneficiary));

        // Grantor1 no longer approved, but grantor2 still is
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertTrue(factory.isApprovedBeneficiary(grantor2, address(mockBeneficiary)));
    }

    // Test with ERC20 token contract as beneficiary
    function testERC20ContractAsBeneficiary() public {
        // Initially not approved
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockToken)));

        // Approve it
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockToken));

        // Now approved
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockToken)));
    }

    // Test with ERC721 token contract as beneficiary
    function testERC721ContractAsBeneficiary() public {
        // Initially not approved
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockNFT)));

        // Approve it
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockNFT));

        // Now approved
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockNFT)));
    }

    // Test with factory contract itself as beneficiary
    function testFactoryContractAsBeneficiary() public {
        // Initially not approved
        assertFalse(factory.isApprovedBeneficiary(grantor, address(factory)));

        // Approve it
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(factory));

        // Now approved
        assertTrue(factory.isApprovedBeneficiary(grantor, address(factory)));
    }

    // Test multiple EOA beneficiaries
    function testMultipleEOABeneficiaries() public {
        address eoa1 = makeAddr("eoa1");
        address eoa2 = makeAddr("eoa2");
        address eoa3 = makeAddr("eoa3");

        // All EOAs should be approved by default
        assertTrue(factory.isApprovedBeneficiary(grantor, eoa1));
        assertTrue(factory.isApprovedBeneficiary(grantor, eoa2));
        assertTrue(factory.isApprovedBeneficiary(grantor, eoa3));
    }

    // Test multiple contract beneficiaries with selective approval
    function testMultipleContractBeneficiariesWithSelectiveApproval() public {
        MockBeneficiary mockBeneficiary2 = new MockBeneficiary();
        MockBeneficiary mockBeneficiary3 = new MockBeneficiary();

        // None approved initially
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary2)));
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary3)));

        // Approve only first and third
        vm.startPrank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));
        factory.approveContractBeneficiary(address(mockBeneficiary3));
        vm.stopPrank();

        // Check selective approval
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary2)));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary3)));
    }

    // Test that approval status can be checked at any time (view function)
    function testIsApprovedBeneficiaryIsViewFunction() public view {
        // Should not modify state, just read
        factory.isApprovedBeneficiary(grantor, eoaBeneficiary);
        factory.isApprovedBeneficiary(grantor, address(mockBeneficiary));
        factory.isApprovedBeneficiary(grantor, address(0));
    }

    // Test checking approval for grantor without will
    function testCheckApprovalForGrantorWithoutWill() public view {
        // Should not revert, just return false for contracts
        bool contractApproved = factory.isApprovedBeneficiary(randomUser, address(mockBeneficiary));
        assertFalse(contractApproved);

        // EOA should still return true if not zero address
        bool eoaApproved = factory.isApprovedBeneficiary(randomUser, eoaBeneficiary);
        assertTrue(eoaApproved);
    }

    // Test EOA addresses of various types
    function testVariousEOAAddresses() public view {
        address addr1 = address(0x1);
        address addr2 = address(0xdEaD);
        address addr3 = address(0x123456789abcdef);

        // All non-zero EOAs should be approved
        assertTrue(factory.isApprovedBeneficiary(grantor, addr1));
        assertTrue(factory.isApprovedBeneficiary(grantor, addr2));
        assertTrue(factory.isApprovedBeneficiary(grantor, addr3));
    }

    // Test that msg.sender doesn't affect isApprovedBeneficiary (it's a pure view)
    function testIsApprovedBeneficiaryIndependentOfCaller() public {
        // Approve from grantor
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Check from different callers - should all see the same result
        vm.prank(grantor);
        bool result1 = factory.isApprovedBeneficiary(grantor, address(mockBeneficiary));

        vm.prank(grantor2);
        bool result2 = factory.isApprovedBeneficiary(grantor, address(mockBeneficiary));

        vm.prank(randomUser);
        bool result3 = factory.isApprovedBeneficiary(grantor, address(mockBeneficiary));

        assertTrue(result1);
        assertTrue(result2);
        assertTrue(result3);
    }

    // Test approval after multiple approve/revoke cycles
    function testApprovalAfterMultipleCycles() public {
        vm.startPrank(grantor);

        for (uint256 i = 0; i < 5; i++) {
            // Approve
            factory.approveContractBeneficiary(address(mockBeneficiary));
            assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));

            // Revoke
            factory.revokeContractBeneficiary(address(mockBeneficiary));
            assertFalse(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        }

        // Final approve
        factory.approveContractBeneficiary(address(mockBeneficiary));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));

        vm.stopPrank();
    }
}
