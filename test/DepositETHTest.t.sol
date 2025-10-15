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

contract DepositETHTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNft;

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
        mockNft = new MockERC721("MockNFT", "MNFT");

        // Deploy factory
        factory = new DigitalWillFactory();

        // Create will for grantor with 30 days heartbeat interval
        vm.prank(_grantor);
        factory.createWill(30 days);
    }

    // Deposit ETH tests
    function testDepositETHRevertsWhenNotGrantor() public {
        vm.startPrank(_randomUser);
        vm.deal(_randomUser, 10 ether);
        vm.expectRevert("Will does not exist");
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroValue() public {
        vm.startPrank(_grantor);
        vm.expectRevert("Must send ETH");
        factory.depositEth{value: 0}(_beneficiary);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroAddressInBeneficiary() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        vm.expectRevert("Invalid beneficiary address");

        factory.depositEth{value: 1 ether}(address(0));
        vm.stopPrank();
    }

    function testDepositETHRevertsWhenNotActive() public {
        // Make the will claimable by warping time
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.prank(_grantor);
        factory.updateState(_grantor);

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        vm.expectRevert("Will must be active");
        factory.depositEth{value: 1 ether}(_beneficiary);
        vm.stopPrank();
    }

    function testDepositETHSuccessfully() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        uint256 depositAmount = 5 ether;

        uint256 initialBalance = address(factory).balance;

        factory.depositEth{value: depositAmount}(_beneficiary);

        // Check contract balance updated
        assertEq(
            address(factory).balance,
            initialBalance + depositAmount,
            "Contract balance should increase by deposit amount"
        );
        // Check beneficiaryAssets mapping updated
        uint256[] memory assetIndices = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices[0], 0, "Asset index should be 0 for first asset");
        vm.stopPrank();
    }

    function testDepositETHMultipleDeposits() public {
        vm.startPrank(_grantor);

        vm.deal(_grantor, 10 ether);

        // First deposit
        factory.depositEth{value: 1 ether}(_beneficiary);

        // Second deposit
        factory.depositEth{value: 2 ether}(_beneficiary);

        // Third deposit
        factory.depositEth{value: 3 ether}(_beneficiary);

        // Check contract balance
        assertEq(address(factory).balance, 6 ether, "Contract should have 6 ETH total");

        // Check all three assets stored
        (,,, uint256 amount1,,) = factory.getAsset(_grantor, 0);
        (,,, uint256 amount2,,) = factory.getAsset(_grantor, 1);
        (,,, uint256 amount3,,) = factory.getAsset(_grantor, 2);

        assertEq(amount1, 1 ether, "First asset amount should be 1 ETH");
        assertEq(amount2, 2 ether, "Second asset amount should be 2 ETH");
        assertEq(amount3, 3 ether, "Third asset amount should be 3 ETH");

        // Check beneficiaryAssets has all three indices
        uint256[] memory assetIndices = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices[0], 0, "First asset index");
        assertEq(assetIndices[1], 1, "Second asset index");
        assertEq(assetIndices[2], 2, "Third asset index");
        vm.stopPrank();
    }

    function testDepositETHMultipleBeneficiaries() public {
        vm.startPrank(_grantor);
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.deal(_grantor, 10 ether);

        // Deposit to different beneficiaries

        factory.depositEth{value: 1 ether}(beneficiary1);

        factory.depositEth{value: 2 ether}(beneficiary2);

        factory.depositEth{value: 3 ether}(beneficiary3);

        // Check contract balance
        assertEq(address(factory).balance, 6 ether, "Contract should have 6 ETH total");

        // Check each beneficiary has correct asset
        (,,,, address stored1,) = factory.getAsset(_grantor, 0);
        (,,,, address stored2,) = factory.getAsset(_grantor, 1);
        (,,,, address stored3,) = factory.getAsset(_grantor, 2);

        assertEq(stored1, beneficiary1, "First beneficiary should match");
        assertEq(stored2, beneficiary2, "Second beneficiary should match");
        assertEq(stored3, beneficiary3, "Third beneficiary should match");

        // Check each beneficiary's asset mapping
        uint256[] memory indices1 = factory.getBeneficiaryAssets(_grantor, beneficiary1);
        uint256[] memory indices2 = factory.getBeneficiaryAssets(_grantor, beneficiary2);
        uint256[] memory indices3 = factory.getBeneficiaryAssets(_grantor, beneficiary3);

        assertEq(indices1[0], 0, "Beneficiary1 asset index");
        assertEq(indices2[0], 1, "Beneficiary2 asset index");
        assertEq(indices3[0], 2, "Beneficiary3 asset index");
        vm.stopPrank();
    }

    function testReceiveRevertsDirectETHTransferFromGrantor() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        vm.expectRevert("Use depositEth function");
        (bool success,) = address(factory).call{value: 1 ether}("");
        success; // Silence unused variable warning

        vm.stopPrank();
    }

    // Fuzz tests
    function testFuzzDepositETHAmount(uint256 amount) public {
        // Bound amount between 0.001 ether and 1000 ether
        amount = bound(amount, 0.001 ether, 1000 ether);

        vm.startPrank(_grantor);
        vm.deal(_grantor, amount);

        factory.depositEth{value: amount}(_beneficiary);

        // Verify balance and storage
        assertEq(address(factory).balance, amount, "Contract balance should match deposit");
        (,,, uint256 storedAmount,,) = factory.getAsset(_grantor, 0);
        assertEq(storedAmount, amount, "Stored amount should match");

        vm.stopPrank();
    }
}
