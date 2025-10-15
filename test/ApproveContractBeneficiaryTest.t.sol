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

contract ApproveContractBeneficiaryTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNft;
    MockBeneficiary public mockBeneficiary;

    address public grantor;
    address public eoaBeneficiary;
    address public randomUser;

    // Events to test
    event ContractBeneficiaryApproved(address indexed grantor, address indexed beneficiary);

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

    // Test successful approval of contract beneficiary
    function testApproveContractBeneficiary() public {
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Verify the contract is now approved
        bool isApproved = factory.isApprovedBeneficiary(grantor, address(mockBeneficiary));
        assertTrue(isApproved, "Contract beneficiary should be approved");
    }

    // Test that approveContractBeneficiary emits the correct event
    function testApproveContractBeneficiaryEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ContractBeneficiaryApproved(grantor, address(mockBeneficiary));

        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));
    }

    // Test approving multiple contract beneficiaries
    function testApproveMultipleContractBeneficiaries() public {
        MockBeneficiary mockBeneficiary2 = new MockBeneficiary();
        MockBeneficiary mockBeneficiary3 = new MockBeneficiary();

        vm.startPrank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));
        factory.approveContractBeneficiary(address(mockBeneficiary2));
        factory.approveContractBeneficiary(address(mockBeneficiary3));
        vm.stopPrank();

        // Verify all contracts are approved
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary2)));
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary3)));
    }

    // Test approving the same contract beneficiary twice (should not revert)
    function testApproveContractBeneficiaryTwice() public {
        vm.startPrank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));
        factory.approveContractBeneficiary(address(mockBeneficiary));
        vm.stopPrank();

        // Should still be approved
        bool isApproved = factory.isApprovedBeneficiary(grantor, address(mockBeneficiary));
        assertTrue(isApproved, "Contract beneficiary should still be approved");
    }

    // Test that EOA token contract can be approved as beneficiary (using ERC20 as example)
    function testApproveTokenContractAsBeneficiary() public {
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockToken));

        bool isApproved = factory.isApprovedBeneficiary(grantor, address(mockToken));
        assertTrue(isApproved, "Token contract should be approved as beneficiary");
    }

    // Test that NFT contract can be approved as beneficiary
    function testApproveNFTContractAsBeneficiary() public {
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockNft));

        bool isApproved = factory.isApprovedBeneficiary(grantor, address(mockNft));
        assertTrue(isApproved, "NFT contract should be approved as beneficiary");
    }

    // Test that approveContractBeneficiary reverts when will does not exist
    function testApproveContractBeneficiaryRevertsWhenWillDoesNotExist() public {
        vm.prank(randomUser);
        vm.expectRevert("Will does not exist");
        factory.approveContractBeneficiary(address(mockBeneficiary));
    }

    // Test that approveContractBeneficiary reverts when address is zero
    function testApproveContractBeneficiaryRevertsWhenAddressIsZero() public {
        vm.prank(grantor);
        vm.expectRevert("Invalid beneficiary address");
        factory.approveContractBeneficiary(address(0));
    }

    // Test that approveContractBeneficiary reverts when address is not a contract (EOA)
    function testApproveContractBeneficiaryRevertsWhenAddressIsNotContract() public {
        vm.prank(grantor);
        vm.expectRevert("Address is not a contract");
        factory.approveContractBeneficiary(eoaBeneficiary);
    }

    // Test that after approval, assets can be deposited to contract beneficiary
    function testDepositAfterApproval() public {
        // Give grantor some ETH
        vm.deal(grantor, 10 ether);

        vm.startPrank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Deposit ETH to approved contract beneficiary
        factory.depositEth{value: 1 ether}(address(mockBeneficiary));
        vm.stopPrank();

        // Verify the asset was deposited
        uint256 assetCount = factory.getAssetCount(grantor);
        assertEq(assetCount, 1, "Asset should be deposited");

        // Verify the asset details
        (DigitalWillFactory.AssetType assetType,,, uint256 amount, address beneficiary, bool claimed) =
            factory.getAsset(grantor, 0);

        assertEq(uint256(assetType), uint256(DigitalWillFactory.AssetType.ETH));
        assertEq(beneficiary, address(mockBeneficiary));
        assertEq(amount, 1 ether);
        assertFalse(claimed);
    }

    // Test that deposit reverts without prior approval
    function testDepositRevertsWithoutApproval() public {
        // Give grantor some ETH
        vm.deal(grantor, 10 ether);

        vm.prank(grantor);
        vm.expectRevert("Contract beneficiary not approved. Use approveContractBeneficiary first");
        factory.depositEth{value: 1 ether}(address(mockBeneficiary));
    }

    // Test that different grantors can approve the same contract independently
    function testDifferentGrantorsCanApproveIndependently() public {
        address grantor2 = makeAddr("grantor2");

        // Create will for second grantor
        vm.prank(grantor2);
        factory.createWill(30 days);

        // First grantor approves
        vm.prank(grantor);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Verify only first grantor has approval
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertFalse(factory.isApprovedBeneficiary(grantor2, address(mockBeneficiary)));

        // Second grantor approves
        vm.prank(grantor2);
        factory.approveContractBeneficiary(address(mockBeneficiary));

        // Now both should have approval
        assertTrue(factory.isApprovedBeneficiary(grantor, address(mockBeneficiary)));
        assertTrue(factory.isApprovedBeneficiary(grantor2, address(mockBeneficiary)));
    }
}
