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

contract GetBeneficiaryAssetsTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;

    address public _grantor;
    address public _randomUser;
    address public _beneficiary;

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

    // Helper function to setup claimable state
    function _setupClaimableState() internal {
        // Warp time to make contract claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
    }

    // getBeneficiaryAssets tests
    function testGetBeneficiaryAssetsWhenNoBeneficiaryExists() public {
        address nonExistent = makeAddr("nonExistentBeneficiary");
        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, nonExistent);
        assertEq(assets.length, 0, "Should return empty array for beneficiary with no assets");
    }

    function testGetBeneficiaryAssetsAfterSingleETHDeposit() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, 1, "Beneficiary should have 1 asset");
        assertEq(assets[0], 0, "First asset index should be 0");
    }

    function testGetBeneficiaryAssetsAfterMultipleETHDeposits() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);

        vm.stopPrank();

        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, 3, "Beneficiary should have 3 assets");
        assertEq(assets[0], 0, "First asset index should be 0");
        assertEq(assets[1], 1, "Second asset index should be 1");
        assertEq(assets[2], 2, "Third asset index should be 2");
    }

    function testGetBeneficiaryAssetsAfterMixedAssetTypes() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit ETH
        factory.depositETH{value: 1 ether}(_beneficiary);

        // Deposit ERC20
        uint256 tokenAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, tokenAmount);
        mockToken.approve(address(factory), tokenAmount);
        factory.depositERC20(address(mockToken), tokenAmount, _beneficiary);

        // Deposit ERC721
        uint256 nftTokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), nftTokenId);
        factory.depositERC721(address(mockNFT), nftTokenId, _beneficiary);

        vm.stopPrank();

        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, 3, "Beneficiary should have 3 assets of different types");
        assertEq(assets[0], 0, "First asset index should be 0");
        assertEq(assets[1], 1, "Second asset index should be 1");
        assertEq(assets[2], 2, "Third asset index should be 2");
    }

    function testGetBeneficiaryAssetsWithMultipleBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit to beneficiary1
        factory.depositETH{value: 1 ether}(beneficiary1);

        // Deposit to beneficiary2
        factory.depositETH{value: 2 ether}(beneficiary2);
        factory.depositETH{value: 2 ether}(beneficiary2);

        // Deposit to beneficiary3
        factory.depositETH{value: 3 ether}(beneficiary3);

        vm.stopPrank();

        // Check beneficiary1
        uint256[] memory assets1 = factory.getBeneficiaryAssets(_grantor, beneficiary1);
        assertEq(assets1.length, 1, "Beneficiary1 should have 1 asset");
        assertEq(assets1[0], 0, "Beneficiary1's asset should be at index 0");

        // Check beneficiary2
        uint256[] memory assets2 = factory.getBeneficiaryAssets(_grantor, beneficiary2);
        assertEq(assets2.length, 2, "Beneficiary2 should have 2 assets");
        assertEq(assets2[0], 1, "Beneficiary2's first asset should be at index 1");
        assertEq(assets2[1], 2, "Beneficiary2's second asset should be at index 2");

        // Check beneficiary3
        uint256[] memory assets3 = factory.getBeneficiaryAssets(_grantor, beneficiary3);
        assertEq(assets3.length, 1, "Beneficiary3 should have 1 asset");
        assertEq(assets3[0], 3, "Beneficiary3's asset should be at index 3");
    }

    function testGetBeneficiaryAssetsAfterPartialClaim() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);

        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim one asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, 3, "Beneficiary should still have 3 asset indices even after claiming");
        assertEq(assets[0], 0, "First asset index should still be 0");
        assertEq(assets[1], 1, "Second asset index should still be 1");
        assertEq(assets[2], 2, "Third asset index should still be 2");
    }

    function testGetBeneficiaryAssetsAfterAllClaimed() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);

        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim all assets
        vm.startPrank(_beneficiary);
        factory.claimAsset(_grantor, 0);
        factory.claimAsset(_grantor, 1);
        vm.stopPrank();

        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, 2, "Beneficiary should still have 2 asset indices even after claiming all");
    }

    function testGetBeneficiaryAssetsInterleavedDeposits() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Interleave deposits between two beneficiaries
        factory.depositETH{value: 1 ether}(beneficiary1); // index 0
        factory.depositETH{value: 2 ether}(beneficiary2); // index 1
        factory.depositETH{value: 1 ether}(beneficiary1); // index 2
        factory.depositETH{value: 2 ether}(beneficiary2); // index 3
        factory.depositETH{value: 1 ether}(beneficiary1); // index 4

        vm.stopPrank();

        // Check beneficiary1
        uint256[] memory assets1 = factory.getBeneficiaryAssets(_grantor, beneficiary1);
        assertEq(assets1.length, 3, "Beneficiary1 should have 3 assets");
        assertEq(assets1[0], 0, "Beneficiary1's first asset should be at index 0");
        assertEq(assets1[1], 2, "Beneficiary1's second asset should be at index 2");
        assertEq(assets1[2], 4, "Beneficiary1's third asset should be at index 4");

        // Check beneficiary2
        uint256[] memory assets2 = factory.getBeneficiaryAssets(_grantor, beneficiary2);
        assertEq(assets2.length, 2, "Beneficiary2 should have 2 assets");
        assertEq(assets2[0], 1, "Beneficiary2's first asset should be at index 1");
        assertEq(assets2[1], 3, "Beneficiary2's second asset should be at index 3");
    }

    function testGetBeneficiaryAssetsWithERC20AndERC721() public {
        vm.startPrank(_grantor);

        // Deposit ERC20
        uint256 tokenAmount1 = 1000 * 10 ** 18;
        mockToken.mint(_grantor, tokenAmount1);
        mockToken.approve(address(factory), tokenAmount1);
        factory.depositERC20(address(mockToken), tokenAmount1, _beneficiary);

        // Deposit ERC721
        uint256 nftTokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), nftTokenId);
        factory.depositERC721(address(mockNFT), nftTokenId, _beneficiary);

        // Deposit another ERC20
        uint256 tokenAmount2 = 2000 * 10 ** 18;
        mockToken.mint(_grantor, tokenAmount2);
        mockToken.approve(address(factory), tokenAmount2);
        factory.depositERC20(address(mockToken), tokenAmount2, _beneficiary);

        vm.stopPrank();

        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, 3, "Beneficiary should have 3 assets");
        assertEq(assets[0], 0, "First asset (ERC20) should be at index 0");
        assertEq(assets[1], 1, "Second asset (ERC721) should be at index 1");
        assertEq(assets[2], 2, "Third asset (ERC20) should be at index 2");
    }

    function testGetBeneficiaryAssetsEmptyAfterNoDeposit() public view {
        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, 0, "Beneficiary should have no assets initially");
    }

    function testGetBeneficiaryAssetsWithZeroAddress() public view {
        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, address(0));
        assertEq(assets.length, 0, "Zero address should have no assets");
    }

    function testGetBeneficiaryAssetsIsolationBetweenBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Only deposit to beneficiary1 and beneficiary2
        factory.depositETH{value: 1 ether}(beneficiary1);
        factory.depositETH{value: 2 ether}(beneficiary2);

        vm.stopPrank();

        // Check beneficiary1
        uint256[] memory assets1 = factory.getBeneficiaryAssets(_grantor, beneficiary1);
        assertEq(assets1.length, 1, "Beneficiary1 should have 1 asset");

        // Check beneficiary2
        uint256[] memory assets2 = factory.getBeneficiaryAssets(_grantor, beneficiary2);
        assertEq(assets2.length, 1, "Beneficiary2 should have 1 asset");

        // Check beneficiary3 (should have nothing)
        uint256[] memory assets3 = factory.getBeneficiaryAssets(_grantor, beneficiary3);
        assertEq(assets3.length, 0, "Beneficiary3 should have no assets");
    }

    // Fuzz tests
    function testFuzzGetBeneficiaryAssetsWithVariousAssetCounts(uint8 numAssets) public {
        // Bound to reasonable number (0-50)
        numAssets = uint8(bound(numAssets, 0, 50));

        vm.startPrank(_grantor);
        vm.deal(_grantor, uint256(numAssets) * 1 ether);

        for (uint256 i = 0; i < numAssets; i++) {
            factory.depositETH{value: 1 ether}(_beneficiary);
        }

        vm.stopPrank();

        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, numAssets, "Beneficiary should have correct number of assets");

        // Verify indices are correct
        for (uint256 i = 0; i < numAssets; i++) {
            assertEq(assets[i], i, "Asset indices should be sequential");
        }
    }

    function testFuzzGetBeneficiaryAssetsWithMultipleBeneficiaries(uint8 numBeneficiaries) public {
        // Bound to reasonable number (1-10)
        numBeneficiaries = uint8(bound(numBeneficiaries, 1, 10));

        address[] memory beneficiaries = new address[](numBeneficiaries);
        uint256 assetIndex = 0;

        vm.startPrank(_grantor);
        vm.deal(_grantor, uint256(numBeneficiaries) * 3 ether);

        for (uint256 i = 0; i < numBeneficiaries; i++) {
            beneficiaries[i] = makeAddr(string(abi.encodePacked("beneficiary", i)));

            // Each beneficiary gets a variable number of assets (1-3)
            uint256 numAssetsForBeneficiary = (i % 3) + 1;

            for (uint256 j = 0; j < numAssetsForBeneficiary; j++) {
                factory.depositETH{value: 1 ether}(beneficiaries[i]);
                assetIndex++;
            }
        }

        vm.stopPrank();

        // Verify each beneficiary has correct assets
        assetIndex = 0;
        for (uint256 i = 0; i < numBeneficiaries; i++) {
            uint256 numAssetsForBeneficiary = (i % 3) + 1;
            uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, beneficiaries[i]);
            assertEq(assets.length, numAssetsForBeneficiary, "Beneficiary should have correct number of assets");

            for (uint256 j = 0; j < numAssetsForBeneficiary; j++) {
                assertEq(assets[j], assetIndex, "Asset index should match expected index");
                assetIndex++;
            }
        }
    }

    function testFuzzGetBeneficiaryAssetsAfterClaiming(uint8 numAssets, uint8 numClaims) public {
        // Bound assets to reasonable number (1-20)
        numAssets = uint8(bound(numAssets, 1, 20));
        // Bound claims to not exceed assets
        numClaims = uint8(bound(numClaims, 0, numAssets));

        vm.startPrank(_grantor);
        vm.deal(_grantor, uint256(numAssets) * 1 ether);

        for (uint256 i = 0; i < numAssets; i++) {
            factory.depositETH{value: 1 ether}(_beneficiary);
        }

        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim some assets
        vm.startPrank(_beneficiary);
        for (uint256 i = 0; i < numClaims; i++) {
            factory.claimAsset(_grantor, i);
        }
        vm.stopPrank();

        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, numAssets, "Number of asset indices should remain constant");

        // Verify indices are still correct
        for (uint256 i = 0; i < numAssets; i++) {
            assertEq(assets[i], i, "Asset indices should still be sequential");
        }
    }

    function testFuzzGetBeneficiaryAssetsInterleavedDeposits(uint8 numRounds) public {
        // Bound to reasonable number of rounds (1-10)
        numRounds = uint8(bound(numRounds, 1, 10));

        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");

        uint256[] memory expectedIndicesBen1 = new uint256[](numRounds);
        uint256[] memory expectedIndicesBen2 = new uint256[](numRounds);

        vm.startPrank(_grantor);
        vm.deal(_grantor, uint256(numRounds) * 3 ether);

        uint256 assetIndex = 0;
        for (uint256 i = 0; i < numRounds; i++) {
            // Deposit to beneficiary1
            factory.depositETH{value: 1 ether}(beneficiary1);
            expectedIndicesBen1[i] = assetIndex;
            assetIndex++;

            // Deposit to beneficiary2
            factory.depositETH{value: 1 ether}(beneficiary2);
            expectedIndicesBen2[i] = assetIndex;
            assetIndex++;
        }

        vm.stopPrank();

        // Verify beneficiary1
        uint256[] memory assets1 = factory.getBeneficiaryAssets(_grantor, beneficiary1);
        assertEq(assets1.length, numRounds, "Beneficiary1 should have correct number of assets");
        for (uint256 i = 0; i < numRounds; i++) {
            assertEq(assets1[i], expectedIndicesBen1[i], "Beneficiary1 asset indices should match expected");
        }

        // Verify beneficiary2
        uint256[] memory assets2 = factory.getBeneficiaryAssets(_grantor, beneficiary2);
        assertEq(assets2.length, numRounds, "Beneficiary2 should have correct number of assets");
        for (uint256 i = 0; i < numRounds; i++) {
            assertEq(assets2[i], expectedIndicesBen2[i], "Beneficiary2 asset indices should match expected");
        }
    }

    function testFuzzGetBeneficiaryAssetsWithMixedTypes(uint8 numETH, uint8 numERC20, uint8 numERC721) public {
        // Bound each type to reasonable numbers
        numETH = uint8(bound(numETH, 0, 15));
        numERC20 = uint8(bound(numERC20, 0, 15));
        numERC721 = uint8(bound(numERC721, 0, 15));

        uint256 totalAssets = uint256(numETH) + uint256(numERC20) + uint256(numERC721);

        vm.startPrank(_grantor);
        vm.deal(_grantor, uint256(numETH) * 1 ether);

        // Deposit ETH
        for (uint256 i = 0; i < numETH; i++) {
            factory.depositETH{value: 1 ether}(_beneficiary);
        }

        // Deposit ERC20
        uint256 amountPerDeposit = 100 * 10 ** 18;
        mockToken.mint(_grantor, uint256(numERC20) * amountPerDeposit);
        for (uint256 i = 0; i < numERC20; i++) {
            mockToken.approve(address(factory), amountPerDeposit);
            factory.depositERC20(address(mockToken), amountPerDeposit, _beneficiary);
        }

        // Deposit ERC721
        for (uint256 i = 0; i < numERC721; i++) {
            uint256 tokenId = mockNFT.mint(_grantor);
            mockNFT.approve(address(factory), tokenId);
            factory.depositERC721(address(mockNFT), tokenId, _beneficiary);
        }

        vm.stopPrank();

        uint256[] memory assets = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assets.length, totalAssets, "Beneficiary should have correct total number of assets");

        // Verify indices are sequential
        for (uint256 i = 0; i < totalAssets; i++) {
            assertEq(assets[i], i, "Asset indices should be sequential");
        }
    }
}
