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

contract GetAssetCountTest is Test {
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

    // getAssetCount tests
    function testGetAssetCountWhenNoAssets() public view {
        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 0, "Asset count should be 0 when no assets deposited");
    }

    function testGetAssetCountAfterSingleETHDeposit() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 1, "Asset count should be 1 after one deposit");
    }

    function testGetAssetCountAfterSingleERC20Deposit() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        mockToken.approve(address(factory), depositAmount);
        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 1, "Asset count should be 1 after ERC20 deposit");
    }

    function testGetAssetCountAfterSingleERC721Deposit() public {
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);
        vm.stopPrank();

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 1, "Asset count should be 1 after ERC721 deposit");
    }

    function testGetAssetCountAfterMultipleETHDeposits() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);

        vm.stopPrank();

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 3, "Asset count should be 3 after three deposits");
    }

    function testGetAssetCountAfterMixedAssetTypes() public {
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

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 3, "Asset count should be 3 after mixed asset deposits");
    }

    function testGetAssetCountWithMultipleBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: 1 ether}(beneficiary1);
        factory.depositETH{value: 2 ether}(beneficiary2);
        factory.depositETH{value: 3 ether}(beneficiary3);

        vm.stopPrank();

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 3, "Asset count should be 3 for all beneficiaries combined");
    }

    function testGetAssetCountAfterClaimingAssets() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);

        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim one asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 2, "Asset count should remain 2 even after claiming one asset");
    }

    function testGetAssetCountAfterAllAssetsClaimed() public {
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

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 2, "Asset count should remain 2 even after claiming all assets");
    }

    function testGetAssetCountIncrementalDeposits() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, 0, "Initial count should be 0");

        factory.depositETH{value: 1 ether}(_beneficiary);
        count = factory.getAssetCount(_grantor);
        assertEq(count, 1, "Count should be 1 after first deposit");

        factory.depositETH{value: 1 ether}(_beneficiary);
        count = factory.getAssetCount(_grantor);
        assertEq(count, 2, "Count should be 2 after second deposit");

        factory.depositETH{value: 1 ether}(_beneficiary);
        count = factory.getAssetCount(_grantor);
        assertEq(count, 3, "Count should be 3 after third deposit");

        vm.stopPrank();
    }

    // Fuzz tests
    function testFuzzGetAssetCountWithVariousETHDeposits(uint8 numDeposits) public {
        // Bound to reasonable number (0-50)
        numDeposits = uint8(bound(numDeposits, 0, 50));

        vm.startPrank(_grantor);
        vm.deal(_grantor, uint256(numDeposits) * 1 ether);

        for (uint256 i = 0; i < numDeposits; i++) {
            factory.depositETH{value: 1 ether}(_beneficiary);
        }

        vm.stopPrank();

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, numDeposits, "Asset count should match number of deposits");
    }

    function testFuzzGetAssetCountWithVariousERC20Deposits(uint8 numDeposits) public {
        // Bound to reasonable number (0-50)
        numDeposits = uint8(bound(numDeposits, 0, 50));

        uint256 amountPerDeposit = 100 * 10 ** 18;
        mockToken.mint(_grantor, uint256(numDeposits) * amountPerDeposit);

        vm.startPrank(_grantor);

        for (uint256 i = 0; i < numDeposits; i++) {
            mockToken.approve(address(factory), amountPerDeposit);
            factory.depositERC20(address(mockToken), amountPerDeposit, _beneficiary);
        }

        vm.stopPrank();

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, numDeposits, "Asset count should match number of ERC20 deposits");
    }

    function testFuzzGetAssetCountWithVariousERC721Deposits(uint8 numDeposits) public {
        // Bound to reasonable number (0-50)
        numDeposits = uint8(bound(numDeposits, 0, 50));

        vm.startPrank(_grantor);

        for (uint256 i = 0; i < numDeposits; i++) {
            uint256 tokenId = mockNFT.mint(_grantor);
            mockNFT.approve(address(factory), tokenId);
            factory.depositERC721(address(mockNFT), tokenId, _beneficiary);
        }

        vm.stopPrank();

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, numDeposits, "Asset count should match number of ERC721 deposits");
    }

    function testFuzzGetAssetCountWithMixedAssets(uint8 numETH, uint8 numERC20, uint8 numERC721) public {
        // Bound each type to reasonable numbers
        numETH = uint8(bound(numETH, 0, 20));
        numERC20 = uint8(bound(numERC20, 0, 20));
        numERC721 = uint8(bound(numERC721, 0, 20));

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

        uint256 expectedCount = uint256(numETH) + uint256(numERC20) + uint256(numERC721);
        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, expectedCount, "Asset count should match total of all asset types");
    }

    function testFuzzGetAssetCountAfterClaiming(uint8 numDeposits, uint8 numClaims) public {
        // Bound deposits to reasonable number (1-20)
        numDeposits = uint8(bound(numDeposits, 1, 20));
        // Bound claims to not exceed deposits
        numClaims = uint8(bound(numClaims, 0, numDeposits));

        vm.startPrank(_grantor);
        vm.deal(_grantor, uint256(numDeposits) * 1 ether);

        for (uint256 i = 0; i < numDeposits; i++) {
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

        // Asset count should remain the same
        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, numDeposits, "Asset count should remain constant regardless of claims");
    }
}
