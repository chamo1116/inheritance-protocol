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
}

contract UpdateBeneficiaryTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNft;

    address public _grantor;
    address public _beneficiary1;
    address public _beneficiary2;
    address public _randomUser;

    // Events to test
    event BeneficiaryUpdated(
        address indexed grantor, uint256 assetIndex, address oldBeneficiary, address newBeneficiary
    );

    function setUp() public {
        _grantor = makeAddr("grantor");
        _beneficiary1 = makeAddr("beneficiary1");
        _beneficiary2 = makeAddr("beneficiary2");
        _randomUser = makeAddr("randomUser");

        // Deploy mock contracts
        mockToken = new MockERC20("MockToken", "MTK");
        mockNft = new MockERC721("MockNFT", "MNFT");

        // Deploy factory
        factory = new DigitalWillFactory();

        // Create will for grantor with 30 days heartbeat interval
        vm.prank(_grantor);
        factory.createWill(30 days);
    }

    // Helper function to accept beneficiary
    function _acceptBeneficiary(address beneficiary, address grantor) internal {
        vm.prank(beneficiary);
        factory.acceptBeneficiary(grantor);
    }

    // Basic functionality tests
    function testUpdateBeneficiarySuccessfully() public {
        // Deposit ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);

        // Update beneficiary
        factory.updateBeneficiary(0, _beneficiary2);
        vm.stopPrank();

        // Verify beneficiary was updated
        (,,,, address beneficiary,) = factory.getAsset(_grantor, 0);
        assertEq(beneficiary, _beneficiary2, "Beneficiary should be updated");
    }

    function testUpdateBeneficiaryEmitsEvent() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);

        vm.expectEmit(true, true, true, true);
        emit BeneficiaryUpdated(_grantor, 0, _beneficiary1, _beneficiary2);

        factory.updateBeneficiary(0, _beneficiary2);
        vm.stopPrank();
    }

    function testUpdateBeneficiaryForERC20() public {
        // Mint and deposit ERC20
        mockToken.mint(_grantor, 1000e18);
        vm.startPrank(_grantor);
        mockToken.approve(address(factory), 1000e18);
        factory.depositERC20(address(mockToken), 100e18, _beneficiary1);

        // Update beneficiary
        factory.updateBeneficiary(0, _beneficiary2);
        vm.stopPrank();

        // Verify
        (,,,, address beneficiary,) = factory.getAsset(_grantor, 0);
        assertEq(beneficiary, _beneficiary2, "ERC20 beneficiary should be updated");
    }

    function testUpdateBeneficiaryForERC721() public {
        // Mint and deposit NFT
        uint256 tokenId = mockNft.mint(_grantor);
        vm.startPrank(_grantor);
        mockNft.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNft), tokenId, _beneficiary1);

        // Update beneficiary
        factory.updateBeneficiary(0, _beneficiary2);
        vm.stopPrank();

        // Verify
        (,,,, address beneficiary,) = factory.getAsset(_grantor, 0);
        assertEq(beneficiary, _beneficiary2, "ERC721 beneficiary should be updated");
    }

    // Revert tests
    function testUpdateBeneficiaryRevertsWhenNotGrantor() public {
        vm.prank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);

        vm.prank(_randomUser);
        vm.expectRevert("Will does not exist");
        factory.updateBeneficiary(0, _beneficiary2);
    }

    function testUpdateBeneficiaryRevertsWhenWillNotActive() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);
        vm.stopPrank();

        // Make will claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.prank(_grantor);
        factory.updateState(_grantor);

        vm.prank(_grantor);
        vm.expectRevert("Will must be active");
        factory.updateBeneficiary(0, _beneficiary2);
    }

    function testUpdateBeneficiaryRevertsWhenAssetIndexOutOfBounds() public {
        vm.prank(_grantor);
        vm.expectRevert("Asset index out of bounds");
        factory.updateBeneficiary(0, _beneficiary2);
    }

    function testUpdateBeneficiaryRevertsWhenAssetAlreadyClaimed() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary1, _grantor);

        // Make claimable and claim
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.prank(_grantor);
        factory.updateState(_grantor);
        vm.prank(_beneficiary1);
        factory.claimAsset(_grantor, 0);

        // Try to update after claim - will is COMPLETED now, so should revert with "Will must be active"
        vm.prank(_grantor);
        vm.expectRevert("Will must be active");
        factory.updateBeneficiary(0, _beneficiary2);
    }

    function testUpdateBeneficiaryRevertsWhenSameBeneficiary() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);

        vm.expectRevert("New beneficiary must be different");
        factory.updateBeneficiary(0, _beneficiary1);
        vm.stopPrank();
    }

    function testUpdateBeneficiaryRevertsWithZeroAddress() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);

        vm.expectRevert("Invalid beneficiary address");
        factory.updateBeneficiary(0, address(0));
        vm.stopPrank();
    }

    function testUpdateBeneficiaryRevertsWithUnapprovedContract() public {
        // Create a mock contract beneficiary
        MockERC20 contractBeneficiary = new MockERC20("Contract", "CNT");

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);

        vm.expectRevert("Contract beneficiary not approved. Use approveContractBeneficiary first");
        factory.updateBeneficiary(0, address(contractBeneficiary));
        vm.stopPrank();
    }

    function testUpdateBeneficiaryWithApprovedContract() public {
        // Create and approve a contract beneficiary
        MockERC20 contractBeneficiary = new MockERC20("Contract", "CNT");

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.approveContractBeneficiary(address(contractBeneficiary));
        factory.depositEth{value: 1 ether}(_beneficiary1);

        // Should work with approved contract
        factory.updateBeneficiary(0, address(contractBeneficiary));
        vm.stopPrank();

        (,,,, address beneficiary,) = factory.getAsset(_grantor, 0);
        assertEq(beneficiary, address(contractBeneficiary), "Should update to approved contract");
    }

    // Multiple assets tests
    function testUpdateBeneficiaryWithMultipleAssets() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit multiple assets
        factory.depositEth{value: 1 ether}(_beneficiary1);
        factory.depositEth{value: 2 ether}(_beneficiary1);
        factory.depositEth{value: 3 ether}(_beneficiary1);

        // Update middle asset
        factory.updateBeneficiary(1, _beneficiary2);
        vm.stopPrank();

        // Verify only middle asset was updated
        (,,,, address ben0,) = factory.getAsset(_grantor, 0);
        (,,,, address ben1,) = factory.getAsset(_grantor, 1);
        (,,,, address ben2,) = factory.getAsset(_grantor, 2);

        assertEq(ben0, _beneficiary1, "First asset should remain unchanged");
        assertEq(ben1, _beneficiary2, "Second asset should be updated");
        assertEq(ben2, _beneficiary1, "Third asset should remain unchanged");
    }

    function testUpdateBeneficiaryMultipleTimes() public {
        address beneficiary3 = makeAddr("beneficiary3");

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);

        // First update
        factory.updateBeneficiary(0, _beneficiary2);
        (,,,, address ben1,) = factory.getAsset(_grantor, 0);
        assertEq(ben1, _beneficiary2, "Should update to beneficiary2");

        // Second update
        factory.updateBeneficiary(0, beneficiary3);
        (,,,, address ben2,) = factory.getAsset(_grantor, 0);
        assertEq(ben2, beneficiary3, "Should update to beneficiary3");

        // Third update back to original
        factory.updateBeneficiary(0, _beneficiary1);
        (,,,, address ben3,) = factory.getAsset(_grantor, 0);
        assertEq(ben3, _beneficiary1, "Should update back to beneficiary1");

        vm.stopPrank();
    }

    // Claiming with updated beneficiary
    function testClaimAssetWithUpdatedBeneficiary() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);

        // Update beneficiary
        factory.updateBeneficiary(0, _beneficiary2);
        vm.stopPrank();

        // Beneficiary2 accepts designation (the new beneficiary)
        _acceptBeneficiary(_beneficiary2, _grantor);

        // Make claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.prank(_grantor);
        factory.updateState(_grantor);

        // Beneficiary1 should not be able to claim
        vm.prank(_beneficiary1);
        vm.expectRevert("Not the beneficiary");
        factory.claimAsset(_grantor, 0);

        // Beneficiary2 should be able to claim
        uint256 balanceBefore = _beneficiary2.balance;
        vm.prank(_beneficiary2);
        factory.claimAsset(_grantor, 0);

        assertEq(_beneficiary2.balance, balanceBefore + 1 ether, "Beneficiary2 should receive the asset");
    }

    function testGetBeneficiaryAssetsAfterUpdate() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit assets for beneficiary1
        factory.depositEth{value: 1 ether}(_beneficiary1);
        factory.depositEth{value: 2 ether}(_beneficiary1);
        factory.depositEth{value: 3 ether}(_beneficiary2);

        // Update one asset from beneficiary1 to beneficiary2
        factory.updateBeneficiary(0, _beneficiary2);
        vm.stopPrank();

        // Check assets for each beneficiary
        uint256[] memory ben1Assets = factory.getBeneficiaryAssets(_grantor, _beneficiary1);
        uint256[] memory ben2Assets = factory.getBeneficiaryAssets(_grantor, _beneficiary2);

        assertEq(ben1Assets.length, 1, "Beneficiary1 should have 1 asset");
        assertEq(ben1Assets[0], 1, "Beneficiary1 should have asset index 1");

        assertEq(ben2Assets.length, 2, "Beneficiary2 should have 2 assets");
        assertEq(ben2Assets[0], 0, "Beneficiary2 should have asset index 0");
        assertEq(ben2Assets[1], 2, "Beneficiary2 should have asset index 2");
    }

    // Fuzz tests
    function testFuzzUpdateBeneficiary(uint8 assetCount, uint8 updateIndex) public {
        assetCount = uint8(bound(assetCount, 1, 20));
        updateIndex = uint8(bound(updateIndex, 0, uint256(assetCount) - 1));

        vm.startPrank(_grantor);
        vm.deal(_grantor, 100 ether);

        // Deposit multiple assets
        for (uint8 i = 0; i < assetCount; i++) {
            factory.depositEth{value: 1 ether}(_beneficiary1);
        }

        // Update specific asset
        factory.updateBeneficiary(updateIndex, _beneficiary2);
        vm.stopPrank();

        // Verify the specific asset was updated
        (,,,, address beneficiary,) = factory.getAsset(_grantor, updateIndex);
        assertEq(beneficiary, _beneficiary2, "Specified asset should be updated");

        // Verify other assets remain unchanged
        for (uint8 i = 0; i < assetCount; i++) {
            if (i != updateIndex) {
                (,,,, address ben,) = factory.getAsset(_grantor, i);
                assertEq(ben, _beneficiary1, "Other assets should remain unchanged");
            }
        }
    }

    function testFuzzUpdateBeneficiaryAtVariousTimes(uint256 timeOffset) public {
        timeOffset = bound(timeOffset, 0, 29 days);

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary1);
        vm.stopPrank();

        // Warp to some point during active period
        vm.warp(block.timestamp + timeOffset);

        vm.prank(_grantor);
        factory.updateBeneficiary(0, _beneficiary2);

        (,,,, address beneficiary,) = factory.getAsset(_grantor, 0);
        assertEq(beneficiary, _beneficiary2, "Should update at any time during active period");
    }
}
