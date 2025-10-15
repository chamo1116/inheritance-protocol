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

contract ClaimAssetTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNft;

    address public _grantor;
    address public _randomUser;
    address public _beneficiary;

    // Events to test
    event AssetClaimed(
        address indexed grantor,
        address indexed beneficiary,
        uint256 assetIndex,
        DigitalWillFactory.AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    );

    event WillCompleted(address indexed grantor);

    function setUp() public {
        _grantor = makeAddr("grantor");
        _beneficiary = makeAddr("beneficiary");
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

    // Helper function to setup claimable state
    function _setupClaimableState() internal {
        // Warp time to make contract claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
    }

    // Helper function to accept beneficiary
    function _acceptBeneficiary(address beneficiary, address grantor) internal {
        vm.prank(beneficiary);
        factory.acceptBeneficiary(grantor);
    }

    // claimAsset tests
    function testClaimSpecificAssetRevertsWhenNotClaimable() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Try to claim before heartbeat expires
        vm.prank(_beneficiary);
        vm.expectRevert("Will not yet claimable");
        factory.claimAsset(_grantor, 0);
    }

    function testClaimSpecificAssetRevertsWhenNotBeneficiary() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Try to claim with wrong beneficiary
        vm.prank(_randomUser);
        vm.expectRevert("Not the beneficiary");
        factory.claimAsset(_grantor, 0);
    }

    function testClaimSpecificAssetRevertsWhenAlreadyClaimed() public {
        // Setup: Deposit two ETH assets so contract doesn't complete after first claim
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Claim the first asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Try to claim the same asset again
        vm.prank(_beneficiary);
        vm.expectRevert("Asset already claimed");
        factory.claimAsset(_grantor, 0);
    }

    function testClaimSpecificAssetRevertsWithInvalidIndex() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Try to claim non-existent asset
        vm.prank(_beneficiary);
        vm.expectRevert();
        factory.claimAsset(_grantor, 999);
    }

    function testClaimSpecificAssetRevertsWhenContractCompleted() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        // Claim the asset (this completes the contract)
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify contract is completed
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState), uint256(DigitalWillFactory.ContractState.COMPLETED), "Contract should be completed"
        );

        // Try to claim again after completion
        vm.prank(_beneficiary);
        vm.expectRevert("Will already completed");
        factory.claimAsset(_grantor, 0);
    }

    function testClaimSpecificAssetETHSuccessfully() public {
        uint256 depositAmount = 5 ether;

        // Setup: Deposit ETH
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: depositAmount}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        // Record initial balances
        uint256 beneficiaryBalanceBefore = _beneficiary.balance;
        uint256 contractBalanceBefore = address(factory).balance;

        // Claim the asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify balances updated
        assertEq(_beneficiary.balance, beneficiaryBalanceBefore + depositAmount, "Beneficiary should receive ETH");
        assertEq(address(factory).balance, contractBalanceBefore - depositAmount, "Contract balance should decrease");

        // Verify asset marked as claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    function testClaimSpecificAssetERC20Successfully() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // Setup: Deposit ERC20
        mockToken.mint(_grantor, depositAmount);
        vm.startPrank(_grantor);
        mockToken.approve(address(factory), depositAmount);
        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        // Record initial balances
        uint256 beneficiaryBalanceBefore = mockToken.balanceOf(_beneficiary);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(factory));

        // Claim the asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify balances updated
        assertEq(
            mockToken.balanceOf(_beneficiary),
            beneficiaryBalanceBefore + depositAmount,
            "Beneficiary should receive tokens"
        );
        assertEq(
            mockToken.balanceOf(address(factory)),
            contractBalanceBefore - depositAmount,
            "Contract balance should decrease"
        );

        // Verify asset marked as claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    function testClaimSpecificAssetERC721Successfully() public {
        // Setup: Deposit ERC721
        uint256 tokenId = mockNft.mint(_grantor);
        vm.startPrank(_grantor);
        mockNft.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNft), tokenId, _beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        // Claim the asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify NFT transferred
        assertEq(mockNft.ownerOf(tokenId), _beneficiary, "Beneficiary should own the NFT");

        // Verify asset marked as claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    function testClaimSpecificAssetEmitsEvent() public {
        uint256 depositAmount = 2 ether;

        // Setup: Deposit ETH
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: depositAmount}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit AssetClaimed(_grantor, _beneficiary, 0, DigitalWillFactory.AssetType.ETH, address(0), 0, depositAmount);

        // Claim the asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);
    }

    function testClaimSpecificAssetCompletesContractSingleAsset() public {
        // Setup: Deposit one ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        // Verify state is CLAIMABLE before claim
        vm.prank(_grantor);
        factory.updateState(_grantor);
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.CLAIMABLE), "State should be CLAIMABLE");

        // Expect WillCompleted event
        vm.expectEmit(true, false, false, false);
        emit WillCompleted(_grantor);

        // Claim the asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify state changed to COMPLETED
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.COMPLETED), "State should be COMPLETED");
    }

    function testClaimSpecificAssetCompletesContractMultipleAssets() public {
        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositEth{value: 1 ether}(_beneficiary);

        mockToken.mint(_grantor, 1000 * 10 ** 18);
        mockToken.approve(address(factory), 1000 * 10 ** 18);
        factory.depositERC20(address(mockToken), 1000 * 10 ** 18, _beneficiary);

        uint256 tokenId = mockNft.mint(_grantor);
        mockNft.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNft), tokenId, _beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        vm.startPrank(_beneficiary);

        // Claim first two assets - should not complete
        factory.claimAsset(_grantor, 0);
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.CLAIMABLE),
            "State should still be CLAIMABLE after first claim"
        );

        factory.claimAsset(_grantor, 1);
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.CLAIMABLE),
            "State should still be CLAIMABLE after second claim"
        );

        // Claim last asset - should complete
        factory.claimAsset(_grantor, 2);
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.COMPLETED),
            "State should be COMPLETED after all claims"
        );

        vm.stopPrank();
    }

    function testClaimSpecificAssetMultipleBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        // Setup: Deposit assets for different beneficiaries
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositEth{value: 1 ether}(beneficiary1);
        factory.depositEth{value: 2 ether}(beneficiary2);
        factory.depositEth{value: 3 ether}(beneficiary3);
        vm.stopPrank();

        // Beneficiaries accept designation
        _acceptBeneficiary(beneficiary1, _grantor);
        _acceptBeneficiary(beneficiary2, _grantor);
        _acceptBeneficiary(beneficiary3, _grantor);

        // Make contract claimable
        _setupClaimableState();

        // Each beneficiary claims their asset
        vm.prank(beneficiary1);
        factory.claimAsset(_grantor, 0);
        assertEq(beneficiary1.balance, 1 ether, "Beneficiary1 should receive 1 ETH");

        vm.prank(beneficiary2);
        factory.claimAsset(_grantor, 1);
        assertEq(beneficiary2.balance, 2 ether, "Beneficiary2 should receive 2 ETH");

        vm.prank(beneficiary3);
        factory.claimAsset(_grantor, 2);
        assertEq(beneficiary3.balance, 3 ether, "Beneficiary3 should receive 3 ETH");

        // Verify contract completed
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState), uint256(DigitalWillFactory.ContractState.COMPLETED), "Contract should be completed"
        );
    }

    function testClaimSpecificAssetCannotClaimOtherBeneficiaryAsset() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");

        // Setup: Deposit assets for different beneficiaries
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(beneficiary1);
        factory.depositEth{value: 2 ether}(beneficiary2);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Beneficiary1 tries to claim beneficiary2's asset
        vm.prank(beneficiary1);
        vm.expectRevert("Not the beneficiary");
        factory.claimAsset(_grantor, 1);

        // Beneficiary2 tries to claim beneficiary1's asset
        vm.prank(beneficiary2);
        vm.expectRevert("Not the beneficiary");
        factory.claimAsset(_grantor, 0);
    }

    function testClaimSpecificAssetOutOfOrder() public {
        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        factory.depositEth{value: 2 ether}(_beneficiary);
        factory.depositEth{value: 3 ether}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        uint256 balanceBefore = _beneficiary.balance;

        vm.startPrank(_beneficiary);

        // Claim in reverse order
        factory.claimAsset(_grantor, 2);
        assertEq(_beneficiary.balance, balanceBefore + 3 ether, "Should receive 3 ETH");

        factory.claimAsset(_grantor, 0);
        assertEq(_beneficiary.balance, balanceBefore + 4 ether, "Should receive additional 1 ETH");

        factory.claimAsset(_grantor, 1);
        assertEq(_beneficiary.balance, balanceBefore + 6 ether, "Should receive additional 2 ETH");

        vm.stopPrank();

        // Verify all claimed
        (,,,,, bool claimed0) = factory.getAsset(_grantor, 0);
        (,,,,, bool claimed1) = factory.getAsset(_grantor, 1);
        (,,,,, bool claimed2) = factory.getAsset(_grantor, 2);
        assertTrue(claimed0 && claimed1 && claimed2, "All assets should be claimed");
    }

    function testClaimSpecificAssetPartialClaims() public {
        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        factory.depositEth{value: 2 ether}(_beneficiary);
        factory.depositEth{value: 3 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Claim only first asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify first asset claimed, others not
        (,,,,, bool claimed0) = factory.getAsset(_grantor, 0);
        (,,,,, bool claimed1) = factory.getAsset(_grantor, 1);
        (,,,,, bool claimed2) = factory.getAsset(_grantor, 2);

        assertTrue(claimed0, "Asset 0 should be claimed");
        assertFalse(claimed1, "Asset 1 should not be claimed");
        assertFalse(claimed2, "Asset 2 should not be claimed");

        // Contract should still be CLAIMABLE
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.CLAIMABLE),
            "Contract should still be CLAIMABLE"
        );
    }

    function testClaimSpecificAssetAutomaticallyUpdatesState() public {
        // Setup: Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Warp time but don't manually update state
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Verify state is still ACTIVE (not yet updated)
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.ACTIVE),
            "State should still be ACTIVE before claim"
        );

        // Claim should automatically update state to CLAIMABLE then claim
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Asset should be successfully claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be claimed");
    }

    function testClaimSpecificAssetMixedAssetTypes() public {
        uint256 ethAmount = 2 ether;
        uint256 tokenAmount = 500 * 10 ** 18;
        uint256 nftTokenId;

        // Setup: Deposit mixed assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositEth{value: ethAmount}(_beneficiary);

        mockToken.mint(_grantor, tokenAmount);
        mockToken.approve(address(factory), tokenAmount);
        factory.depositERC20(address(mockToken), tokenAmount, _beneficiary);

        nftTokenId = mockNft.mint(_grantor);
        mockNft.approve(address(factory), nftTokenId);
        factory.depositERC721(address(mockNft), nftTokenId, _beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        // Claim all assets
        vm.startPrank(_beneficiary);

        factory.claimAsset(_grantor, 0); // ETH
        factory.claimAsset(_grantor, 1); // ERC20
        factory.claimAsset(_grantor, 2); // ERC721

        vm.stopPrank();

        // Verify all assets transferred correctly
        assertEq(_beneficiary.balance, ethAmount, "Should receive ETH");
        assertEq(mockToken.balanceOf(_beneficiary), tokenAmount, "Should receive tokens");
        assertEq(mockNft.ownerOf(nftTokenId), _beneficiary, "Should own NFT");

        // Verify contract completed
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState), uint256(DigitalWillFactory.ContractState.COMPLETED), "Contract should be completed"
        );
    }

    function testClaimSpecificAssetBeneficiaryWithMultipleAssetsOfSameType() public {
        // Setup: Deposit multiple ETH assets to same beneficiary
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        factory.depositEth{value: 2 ether}(_beneficiary);
        factory.depositEth{value: 3 ether}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        uint256 balanceBefore = _beneficiary.balance;

        // Claim each asset individually
        vm.startPrank(_beneficiary);
        factory.claimAsset(_grantor, 0);
        factory.claimAsset(_grantor, 1);
        factory.claimAsset(_grantor, 2);
        vm.stopPrank();

        // Verify total received
        assertEq(_beneficiary.balance, balanceBefore + 6 ether, "Should receive total of 6 ETH");
    }

    function testClaimSpecificAssetAtExactHeartbeatBoundary() public {
        // Setup: Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Warp to exact boundary
        vm.warp(block.timestamp + 30 days);

        // Should be able to claim
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be claimed at exact boundary");
    }

    // Fuzz tests
    function testFuzzClaimSpecificAssetWithVariousIndices(uint256 numAssets) public {
        // Bound to reasonable number (1-20)
        numAssets = bound(numAssets, 1, 20);

        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, numAssets * 1 ether);

        for (uint256 i = 0; i < numAssets; i++) {
            factory.depositEth{value: 1 ether}(_beneficiary);
        }
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Make contract claimable
        _setupClaimableState();

        // Claim all assets
        vm.startPrank(_beneficiary);
        for (uint256 i = 0; i < numAssets; i++) {
            factory.claimAsset(_grantor, i);
        }
        vm.stopPrank();

        // Verify all assets claimed
        for (uint256 i = 0; i < numAssets; i++) {
            (,,,,, bool claimed) = factory.getAsset(_grantor, i);
            assertTrue(claimed, "Each asset should be claimed");
        }
    }

    function testFuzzClaimSpecificAssetWithVariousTimeOffsets(uint256 timeOffset) public {
        // Bound to reasonable range (30 days to 365 days)
        timeOffset = bound(timeOffset, 30 days, 365 days);

        // Setup: Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Warp time
        vm.warp(block.timestamp + timeOffset);

        // Should be able to claim
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be claimable after time offset");
    }

    function testFuzzClaimSpecificAssetERC20WithVariousAmounts(uint256 amount) public {
        // Bound to reasonable range
        amount = bound(amount, 1, 1_000_000_000 * 10 ** 18);

        // Setup: Deposit ERC20
        mockToken.mint(_grantor, amount);
        vm.startPrank(_grantor);
        mockToken.approve(address(factory), amount);
        factory.depositERC20(address(mockToken), amount, _beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Beneficiary accepts designation
        _acceptBeneficiary(_beneficiary, _grantor);

        // Claim
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify
        assertEq(mockToken.balanceOf(_beneficiary), amount, "Beneficiary should receive correct amount");
    }
}
