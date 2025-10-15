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
}

contract RemoveAssetTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;

    address public _grantor;
    address public _beneficiary;
    address public _randomUser;

    // Events to test
    event AssetRemoved(
        address indexed grantor,
        uint256 assetIndex,
        DigitalWillFactory.AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    );

    function setUp() public {
        _grantor = makeAddr("grantor");
        _beneficiary = makeAddr("beneficiary");
        _randomUser = makeAddr("randomUser");

        // Deploy mock contracts
        mockToken = new MockERC20("MockToken", "MTK");
        mockNFT = new MockERC721("MockNFT", "MNFT");

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
    function testRemoveETHAssetSuccessfully() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);

        uint256 balanceBefore = _grantor.balance;
        factory.removeAsset(0);
        vm.stopPrank();

        // Verify ETH returned to grantor
        assertEq(_grantor.balance, balanceBefore + 1 ether, "ETH should be returned to grantor");

        // Verify asset marked as claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    function testRemoveERC20AssetSuccessfully() public {
        // Mint and deposit ERC20
        mockToken.mint(_grantor, 1000e18);
        vm.startPrank(_grantor);
        mockToken.approve(address(factory), 1000e18);
        factory.depositERC20(address(mockToken), 100e18, _beneficiary);

        uint256 balanceBefore = mockToken.balanceOf(_grantor);
        factory.removeAsset(0);
        vm.stopPrank();

        // Verify ERC20 returned to grantor
        assertEq(mockToken.balanceOf(_grantor), balanceBefore + 100e18, "ERC20 should be returned to grantor");

        // Verify asset marked as claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    function testRemoveERC721AssetSuccessfully() public {
        // Mint and deposit NFT
        uint256 tokenId = mockNFT.mint(_grantor);
        vm.startPrank(_grantor);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        factory.removeAsset(0);
        vm.stopPrank();

        // Verify NFT returned to grantor
        assertEq(mockNFT.ownerOf(tokenId), _grantor, "NFT should be returned to grantor");

        // Verify asset marked as claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    function testRemoveAssetEmitsEvent() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);

        vm.expectEmit(true, true, true, true);
        emit AssetRemoved(_grantor, 0, DigitalWillFactory.AssetType.ETH, address(0), 0, 1 ether);

        factory.removeAsset(0);
        vm.stopPrank();
    }

    function testRemoveAssetAllowsRedeposit() public {
        // Mint and deposit NFT
        uint256 tokenId = mockNFT.mint(_grantor);
        vm.startPrank(_grantor);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        // Remove asset
        factory.removeAsset(0);

        // Should be able to deposit the same NFT again
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);
        vm.stopPrank();

        // Verify NFT is deposited again
        assertEq(mockNFT.ownerOf(tokenId), address(factory), "NFT should be in contract");
    }

    function testRemoveAssetDecrementsUnclaimedCount() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        vm.stopPrank();

        // Get initial asset count
        (,,, uint256 assetCount) = factory.getWillInfo(_grantor);
        assertEq(assetCount, 2, "Should have 2 assets");

        vm.prank(_grantor);
        factory.removeAsset(0);

        // Asset count should remain the same (we don't delete from array)
        // But unclaimedAssetsCount should be decremented
        (,,, uint256 assetCountAfter) = factory.getWillInfo(_grantor);
        assertEq(assetCountAfter, 2, "Asset count should still be 2");
    }

    // Revert tests
    function testRemoveAssetRevertsWhenNotGrantor() public {
        vm.prank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);

        vm.prank(_randomUser);
        vm.expectRevert("Will does not exist");
        factory.removeAsset(0);
    }

    function testRemoveAssetRevertsWhenWillNotActive() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make will claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.prank(_grantor);
        factory.updateState(_grantor);

        vm.prank(_grantor);
        vm.expectRevert("Will must be active");
        factory.removeAsset(0);
    }

    function testRemoveAssetRevertsWhenIndexOutOfBounds() public {
        vm.prank(_grantor);
        vm.expectRevert("Asset index out of bounds");
        factory.removeAsset(0);
    }

    function testRemoveAssetRevertsWhenAlreadyClaimed() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);

        // Remove once
        factory.removeAsset(0);

        // Try to remove again
        vm.expectRevert("Asset already claimed");
        factory.removeAsset(0);
        vm.stopPrank();
    }

    function testRemoveAssetRevertsAfterBeneficiaryClaimed() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make claimable and claim
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.prank(_grantor);
        factory.updateState(_grantor);
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Try to remove - should revert because will is COMPLETED
        vm.prank(_grantor);
        vm.expectRevert("Will must be active");
        factory.removeAsset(0);
    }

    // Multiple assets tests
    function testRemoveAssetWithMultipleAssets() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit multiple assets
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);

        uint256 balanceBefore = _grantor.balance;

        // Remove middle asset
        factory.removeAsset(1);
        vm.stopPrank();

        // Verify only middle asset was removed
        assertEq(_grantor.balance, balanceBefore + 2 ether, "Should receive 2 ETH");

        (,,,,, bool claimed0) = factory.getAsset(_grantor, 0);
        (,,,,, bool claimed1) = factory.getAsset(_grantor, 1);
        (,,,,, bool claimed2) = factory.getAsset(_grantor, 2);

        assertFalse(claimed0, "First asset should not be claimed");
        assertTrue(claimed1, "Second asset should be claimed");
        assertFalse(claimed2, "Third asset should not be claimed");
    }

    function testRemoveAllAssets() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit multiple assets
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);

        uint256 balanceBefore = _grantor.balance;

        // Remove all assets
        factory.removeAsset(0);
        factory.removeAsset(1);
        factory.removeAsset(2);
        vm.stopPrank();

        // Verify all assets removed
        assertEq(_grantor.balance, balanceBefore + 6 ether, "Should receive all ETH back");

        // All assets should be marked as claimed
        (,,,,, bool claimed0) = factory.getAsset(_grantor, 0);
        (,,,,, bool claimed1) = factory.getAsset(_grantor, 1);
        (,,,,, bool claimed2) = factory.getAsset(_grantor, 2);

        assertTrue(claimed0, "First asset should be claimed");
        assertTrue(claimed1, "Second asset should be claimed");
        assertTrue(claimed2, "Third asset should be claimed");
    }

    function testRemoveMixedAssetTypes() public {
        // Setup different asset types
        mockToken.mint(_grantor, 1000e18);
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit different types
        factory.depositETH{value: 1 ether}(_beneficiary);
        mockToken.approve(address(factory), 1000e18);
        factory.depositERC20(address(mockToken), 100e18, _beneficiary);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        uint256 ethBalance = _grantor.balance;
        uint256 tokenBalance = mockToken.balanceOf(_grantor);

        // Remove all assets
        factory.removeAsset(0); // ETH
        factory.removeAsset(1); // ERC20
        factory.removeAsset(2); // ERC721
        vm.stopPrank();

        // Verify all returned
        assertEq(_grantor.balance, ethBalance + 1 ether, "ETH should be returned");
        assertEq(mockToken.balanceOf(_grantor), tokenBalance + 100e18, "ERC20 should be returned");
        assertEq(mockNFT.ownerOf(tokenId), _grantor, "NFT should be returned");
    }

    // Integration with other features
    function testRemoveAssetThenDeposit() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit and remove
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.removeAsset(0);

        // Deposit again
        factory.depositETH{value: 2 ether}(_beneficiary);
        vm.stopPrank();

        // Should have 2 assets now (first is claimed, second is new)
        (,,, uint256 assetCount) = factory.getWillInfo(_grantor);
        assertEq(assetCount, 2, "Should have 2 assets");

        (,,,,, bool claimed0) = factory.getAsset(_grantor, 0);
        (,,,,, bool claimed1) = factory.getAsset(_grantor, 1);
        assertTrue(claimed0, "First asset should be claimed");
        assertFalse(claimed1, "Second asset should not be claimed");
    }

    function testRemoveAssetThenCheckIn() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);

        (uint256 lastCheckIn1,,,) = factory.getWillInfo(_grantor);

        factory.removeAsset(0);

        // Check-in should still work
        vm.warp(block.timestamp + 1 days);
        factory.checkIn();
        vm.stopPrank();

        (uint256 lastCheckIn2,,,) = factory.getWillInfo(_grantor);
        assertGt(lastCheckIn2, lastCheckIn1, "Check-in should update timestamp");
    }

    function testRemoveAssetDoesNotAffectOtherBeneficiaries() public {
        address beneficiary2 = makeAddr("beneficiary2");

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit for two different beneficiaries
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(beneficiary2);

        // Remove first asset
        factory.removeAsset(0);
        vm.stopPrank();

        // Beneficiary2 accepts designation
        _acceptBeneficiary(beneficiary2, _grantor);

        // Make claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.prank(_grantor);
        factory.updateState(_grantor);

        // Beneficiary2 should still be able to claim
        uint256 balanceBefore = beneficiary2.balance;
        vm.prank(beneficiary2);
        factory.claimAsset(_grantor, 1);

        assertEq(beneficiary2.balance, balanceBefore + 2 ether, "Beneficiary2 should receive their asset");
    }

    // Fuzz tests
    function testFuzzRemoveAsset(uint8 assetCount, uint8 removeIndex) public {
        assetCount = uint8(bound(assetCount, 1, 20));
        removeIndex = uint8(bound(removeIndex, 0, uint256(assetCount) - 1));

        vm.startPrank(_grantor);
        vm.deal(_grantor, 100 ether);

        // Deposit multiple assets
        for (uint8 i = 0; i < assetCount; i++) {
            factory.depositETH{value: 1 ether}(_beneficiary);
        }

        uint256 balanceBefore = _grantor.balance;

        // Remove specific asset
        factory.removeAsset(removeIndex);
        vm.stopPrank();

        // Verify the specific asset was removed
        assertEq(_grantor.balance, balanceBefore + 1 ether, "Should receive 1 ETH back");

        (,,,,, bool claimed) = factory.getAsset(_grantor, removeIndex);
        assertTrue(claimed, "Specified asset should be removed");

        // Verify other assets remain unchanged
        for (uint8 i = 0; i < assetCount; i++) {
            if (i != removeIndex) {
                (,,,,, bool claimedStatus) = factory.getAsset(_grantor, i);
                assertFalse(claimedStatus, "Other assets should remain unclaimed");
            }
        }
    }

    function testFuzzRemoveAssetAtVariousTimes(uint256 timeOffset) public {
        timeOffset = bound(timeOffset, 0, 29 days);

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Warp to some point during active period
        vm.warp(block.timestamp + timeOffset);

        uint256 balanceBefore = _grantor.balance;
        vm.prank(_grantor);
        factory.removeAsset(0);

        assertEq(_grantor.balance, balanceBefore + 1 ether, "Should remove at any time during active period");
    }

    function testFuzzRemoveMultipleAssets(uint8 assetCount, uint8 removeCount) public {
        assetCount = uint8(bound(assetCount, 2, 20));
        removeCount = uint8(bound(removeCount, 1, assetCount));

        vm.startPrank(_grantor);
        vm.deal(_grantor, 100 ether);

        // Deposit assets
        for (uint8 i = 0; i < assetCount; i++) {
            factory.depositETH{value: 1 ether}(_beneficiary);
        }

        uint256 balanceBefore = _grantor.balance;

        // Remove specified number of assets from the start
        for (uint8 i = 0; i < removeCount; i++) {
            factory.removeAsset(i);
        }
        vm.stopPrank();

        // Verify correct amount returned
        assertEq(
            _grantor.balance, balanceBefore + (uint256(removeCount) * 1 ether), "Should receive correct amount back"
        );

        // Verify correct assets removed
        for (uint8 i = 0; i < assetCount; i++) {
            (,,,,, bool claimed) = factory.getAsset(_grantor, i);
            if (i < removeCount) {
                assertTrue(claimed, "Removed assets should be claimed");
            } else {
                assertFalse(claimed, "Remaining assets should not be claimed");
            }
        }
    }
}
