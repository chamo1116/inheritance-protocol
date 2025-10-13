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

contract DepositERC721Test is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;

    address public _grantor;
    address public _randomUser;
    address public _beneficiary;

    // Events to test
    event AssetDeposited(
        address indexed grantor,
        DigitalWillFactory.AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        address indexed beneficiary
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

    // depositERC721 tests
    function testDepositERC721RevertsWhenNotGrantor() public {
        // Mint NFT to random user
        uint256 tokenId = mockNFT.mint(_randomUser);

        vm.startPrank(_randomUser);
        mockNFT.approve(address(factory), tokenId);

        vm.expectRevert("Will does not exist");
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC721RevertsWithInvalidTokenAddress() public {
        vm.startPrank(_grantor);

        vm.expectRevert("Invalid token address");
        factory.depositERC721(address(0), 1, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721RevertsWithInvalidBeneficiaryAddress() public {
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        mockNFT.approve(address(factory), tokenId);

        vm.expectRevert("Invalid beneficiary address");
        factory.depositERC721(address(mockNFT), tokenId, address(0));

        vm.stopPrank();
    }

    function testDepositERC721RevertsWhenOwnerIsNotGrantor() public {
        uint256 tokenId = mockNFT.mint(_randomUser);

        vm.startPrank(_grantor);

        vm.expectRevert("Not the owner of NFT");
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721RevertsWhenNotActive() public {
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        mockNFT.approve(address(factory), tokenId);
        vm.stopPrank();

        // Make the will claimable by warping time
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);

        vm.startPrank(_grantor);
        vm.expectRevert("Will must be active");
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721Successfully() public {
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        mockNFT.approve(address(factory), tokenId);

        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        // Check NFT ownership transferred
        assertEq(mockNFT.ownerOf(tokenId), address(factory), "NFT should be owned by contract");

        // Check asset stored correctly
        (
            DigitalWillFactory.AssetType assetType,
            address tokenAddress,
            uint256 storedTokenId,
            uint256 amount,
            address storedBeneficiary,
            bool claimed
        ) = factory.getAsset(_grantor, 0);

        assertEq(uint256(assetType), uint256(DigitalWillFactory.AssetType.ERC721), "Asset type should be ERC721");
        assertEq(tokenAddress, address(mockNFT), "Token address should match");
        assertEq(storedTokenId, tokenId, "Token ID should match");
        assertEq(amount, 1, "Amount should be 1");
        assertEq(storedBeneficiary, _beneficiary, "Beneficiary should match");
        assertFalse(claimed, "Should not be claimed");

        // Check beneficiaryAssets mapping
        uint256[] memory assetIndices = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        uint256 assetIndex = assetIndices[0];
        assertEq(assetIndex, 0, "Asset index should be 0");

        vm.stopPrank();
    }

    function testDepositERC721EmitsEvent() public {
        // Mint NFT to grantor
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        mockNFT.approve(address(factory), tokenId);

        vm.expectEmit(true, true, true, true);
        emit AssetDeposited(_grantor, DigitalWillFactory.AssetType.ERC721, address(mockNFT), tokenId, 1, _beneficiary);

        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721MultipleNFTsToSameBeneficiary() public {
        vm.startPrank(_grantor);

        // Mint and deposit multiple NFTs
        uint256 tokenId1 = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId1);
        factory.depositERC721(address(mockNFT), tokenId1, _beneficiary);

        uint256 tokenId2 = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId2);
        factory.depositERC721(address(mockNFT), tokenId2, _beneficiary);

        uint256 tokenId3 = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId3);
        factory.depositERC721(address(mockNFT), tokenId3, _beneficiary);

        // Check all NFTs are owned by contract
        assertEq(mockNFT.ownerOf(tokenId1), address(factory), "NFT 1 should be owned by contract");
        assertEq(mockNFT.ownerOf(tokenId2), address(factory), "NFT 2 should be owned by contract");
        assertEq(mockNFT.ownerOf(tokenId3), address(factory), "NFT 3 should be owned by contract");

        // Check all assets stored
        (,, uint256 storedId1,,,) = factory.getAsset(_grantor, 0);
        (,, uint256 storedId2,,,) = factory.getAsset(_grantor, 1);
        (,, uint256 storedId3,,,) = factory.getAsset(_grantor, 2);

        assertEq(storedId1, tokenId1, "Token ID 1 should match");
        assertEq(storedId2, tokenId2, "Token ID 2 should match");
        assertEq(storedId3, tokenId3, "Token ID 3 should match");

        // Check beneficiaryAssets mapping has all three
        uint256[] memory nft3AssetIndices = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(nft3AssetIndices[0], 0, "First asset index");
        assertEq(nft3AssetIndices[1], 1, "Second asset index");
        assertEq(nft3AssetIndices[2], 2, "Third asset index");

        vm.stopPrank();
    }

    function testDepositERC721MultipleBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.startPrank(_grantor);

        // Mint and deposit NFTs to different beneficiaries
        uint256 tokenId1 = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId1);
        factory.depositERC721(address(mockNFT), tokenId1, beneficiary1);

        uint256 tokenId2 = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId2);
        factory.depositERC721(address(mockNFT), tokenId2, beneficiary2);

        uint256 tokenId3 = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId3);
        factory.depositERC721(address(mockNFT), tokenId3, beneficiary3);

        // Check each beneficiary has correct asset
        (,,,, address stored1,) = factory.getAsset(_grantor, 0);
        (,,,, address stored2,) = factory.getAsset(_grantor, 1);
        (,,,, address stored3,) = factory.getAsset(_grantor, 2);

        assertEq(stored1, beneficiary1, "Beneficiary 1 should match");
        assertEq(stored2, beneficiary2, "Beneficiary 2 should match");
        assertEq(stored3, beneficiary3, "Beneficiary 3 should match");

        // Check each beneficiary's asset mapping
        uint256[] memory indices1 = factory.getBeneficiaryAssets(_grantor, beneficiary1);
        uint256[] memory indices2 = factory.getBeneficiaryAssets(_grantor, beneficiary2);
        uint256[] memory indices3 = factory.getBeneficiaryAssets(_grantor, beneficiary3);

        assertEq(indices1[0], 0, "Beneficiary1 asset index");
        assertEq(indices2[0], 1, "Beneficiary2 asset index");
        assertEq(indices3[0], 2, "Beneficiary3 asset index");

        vm.stopPrank();
    }

    function testDepositERC721WithDifferentNFTCollections() public {
        // Create another NFT collection
        MockERC721 mockNFT2 = new MockERC721("MockNFT2", "MNFT2");

        vm.startPrank(_grantor);

        // Mint and deposit from first collection
        uint256 tokenId1 = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId1);
        factory.depositERC721(address(mockNFT), tokenId1, _beneficiary);

        // Mint and deposit from second collection
        uint256 tokenId2 = mockNFT2.mint(_grantor);
        mockNFT2.approve(address(factory), tokenId2);
        factory.depositERC721(address(mockNFT2), tokenId2, _beneficiary);

        // Check both NFTs stored with correct addresses
        (, address token1,,,,) = factory.getAsset(_grantor, 0);
        (, address token2,,,,) = factory.getAsset(_grantor, 1);

        assertEq(token1, address(mockNFT), "First token address should match");
        assertEq(token2, address(mockNFT2), "Second token address should match");

        // Check ownership
        assertEq(mockNFT.ownerOf(tokenId1), address(factory), "NFT 1 should be owned by contract");
        assertEq(mockNFT2.ownerOf(tokenId2), address(factory), "NFT 2 should be owned by contract");

        vm.stopPrank();
    }

    function testDepositERC721WithoutApprovalReverts() public {
        // Mint NFT to grantor
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        // Don't approve the transfer

        vm.expectRevert();
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721NonExistentTokenReverts() public {
        uint256 nonExistentTokenId = 999;

        vm.startPrank(_grantor);

        vm.expectRevert();
        factory.depositERC721(address(mockNFT), nonExistentTokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721MixedWithETHDeposits() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit ETH
        factory.depositETH{value: 1 ether}(_beneficiary);

        // Deposit NFT
        uint256 tokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        // Deposit more ETH
        factory.depositETH{value: 2 ether}(_beneficiary);

        // Check all assets stored correctly
        (DigitalWillFactory.AssetType type0,,,,,) = factory.getAsset(_grantor, 0);
        (DigitalWillFactory.AssetType type1,,,,,) = factory.getAsset(_grantor, 1);
        (DigitalWillFactory.AssetType type2,,,,,) = factory.getAsset(_grantor, 2);

        assertEq(uint256(type0), uint256(DigitalWillFactory.AssetType.ETH), "Asset 0 should be ETH");
        assertEq(uint256(type1), uint256(DigitalWillFactory.AssetType.ERC721), "Asset 1 should be ERC721");
        assertEq(uint256(type2), uint256(DigitalWillFactory.AssetType.ETH), "Asset 2 should be ETH");

        // Check beneficiaryAssets has all three
        uint256[] memory assetIndices1140 = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices1140[0], 0, "First asset index");
        uint256[] memory assetIndices1145 = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices1145[1], 1, "Second asset index");
        uint256[] memory assetIndices1150 = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices1150[2], 2, "Third asset index");

        vm.stopPrank();
    }

    // Fuzz tests
    function testFuzzDepositERC721TokenId(uint256 tokenId) public {
        // Bound token ID to reasonable range
        tokenId = bound(tokenId, 0, type(uint128).max);

        vm.startPrank(_grantor);

        // Mint with specific token ID
        mockNFT.mintWithId(_grantor, tokenId);
        mockNFT.approve(address(factory), tokenId);

        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        // Verify storage
        (,, uint256 storedTokenId,,,) = factory.getAsset(_grantor, 0);
        assertEq(storedTokenId, tokenId, "Token ID should match");
        assertEq(mockNFT.ownerOf(tokenId), address(factory), "Contract should own NFT");

        vm.stopPrank();
    }

    function testFuzzDepositERC721MultipleBeneficiaries(address beneficiary1, address beneficiary2) public {
        // Ensure addresses are valid and different
        vm.assume(beneficiary1 != address(0));
        vm.assume(beneficiary2 != address(0));
        vm.assume(beneficiary1 != beneficiary2);

        vm.startPrank(_grantor);

        // Mint and deposit to first beneficiary
        uint256 tokenId1 = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId1);
        factory.depositERC721(address(mockNFT), tokenId1, beneficiary1);

        // Mint and deposit to second beneficiary
        uint256 tokenId2 = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId2);
        factory.depositERC721(address(mockNFT), tokenId2, beneficiary2);

        // Verify storage
        (,,,, address stored1,) = factory.getAsset(_grantor, 0);
        (,,,, address stored2,) = factory.getAsset(_grantor, 1);

        assertEq(stored1, beneficiary1, "First beneficiary should match");
        assertEq(stored2, beneficiary2, "Second beneficiary should match");

        vm.stopPrank();
    }

    function testFuzzDepositERC721MultipleTokens(uint8 numTokens) public {
        // Bound to reasonable number of tokens (1-20)
        numTokens = uint8(bound(numTokens, 1, 20));

        vm.startPrank(_grantor);

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = mockNFT.mint(_grantor);
            mockNFT.approve(address(factory), tokenId);
            factory.depositERC721(address(mockNFT), tokenId, _beneficiary);
        }

        // Verify all tokens deposited
        uint256[] memory nftAssetIndices = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        for (uint256 i = 0; i < numTokens; i++) {
            assertEq(mockNFT.ownerOf(i), address(factory), "Contract should own all NFTs");
            assertEq(nftAssetIndices[i], i, "Asset indices should match");
        }

        vm.stopPrank();
    }
}
