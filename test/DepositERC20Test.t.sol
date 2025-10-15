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

contract DepositERC20Test is Test {
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

    // Helper function to check if address is a contract
    function _isContract(address _account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_account)
        }
        return size > 0;
    }

    // depositERC20 tests
    function testDepositERC20RevertsWhenNotGrantor() public {
        uint256 depositAmount = 1000 * 10 ** 18; // 1000 tokens
        mockToken.mint(_randomUser, depositAmount);

        vm.startPrank(_randomUser);
        mockToken.approve(address(factory), depositAmount);

        vm.expectRevert("Will does not exist");
        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20RevertsWithInvalidTokenAddress() public {
        vm.startPrank(_grantor);
        vm.expectRevert("Invalid token address");
        factory.depositERC20(address(0), 1000, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20RevertsWithZeroAmount() public {
        vm.startPrank(_grantor);
        vm.expectRevert("Amount must be greater than 0");
        factory.depositERC20(address(mockToken), 0, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20RevertsWithInvalidBeneficiaryAddress() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        mockToken.approve(address(factory), depositAmount);

        vm.expectRevert("Invalid beneficiary address");
        factory.depositERC20(address(mockToken), depositAmount, address(0));
        vm.stopPrank();
    }

    function testDepositERC20RevertsWhenNotActive() public {
        // Make the will claimable by warping time
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.prank(_grantor);
        factory.updateState(_grantor);

        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        mockToken.approve(address(factory), depositAmount);

        vm.expectRevert("Will must be active");
        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20Successfully() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        mockToken.approve(address(factory), depositAmount);

        uint256 initialBalance = mockToken.balanceOf(address(factory));

        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);

        // Check contract balance updated
        assertEq(
            mockToken.balanceOf(address(factory)),
            initialBalance + depositAmount,
            "Contract balance should increase by deposit amount"
        );

        // Check asset stored correctly
        (
            DigitalWillFactory.AssetType assetType,
            address tokenAddress,
            uint256 tokenId,
            uint256 amount,
            address storedBeneficiary,
            bool claimed
        ) = factory.getAsset(_grantor, 0);

        assertEq(uint256(assetType), uint256(DigitalWillFactory.AssetType.ERC20), "Asset type should be ERC20");
        assertEq(tokenAddress, address(mockToken), "Token address should match");
        assertEq(tokenId, 0, "Token ID should be 0 for ERC20");
        assertEq(amount, depositAmount, "Amount should match");
        assertEq(storedBeneficiary, _beneficiary, "Beneficiary should match");
        assertFalse(claimed, "Should not be claimed");

        // Check beneficiaryAssets mapping updated
        uint256[] memory assetIndices = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices[0], 0, "Asset index should be 0 for first asset");
        vm.stopPrank();
    }

    function testDepositERC20EmitsEvent() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        mockToken.approve(address(factory), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit AssetDeposited(
            _grantor, DigitalWillFactory.AssetType.ERC20, address(mockToken), 0, depositAmount, _beneficiary
        );

        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20MultipleDeposits() public {
        vm.startPrank(_grantor);

        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;
        uint256 amount3 = 3000 * 10 ** 18;

        mockToken.mint(_grantor, amount1 + amount2 + amount3);

        // First deposit
        mockToken.approve(address(factory), amount1);
        factory.depositERC20(address(mockToken), amount1, _beneficiary);

        // Second deposit
        mockToken.approve(address(factory), amount2);
        factory.depositERC20(address(mockToken), amount2, _beneficiary);

        // Third deposit
        mockToken.approve(address(factory), amount3);
        factory.depositERC20(address(mockToken), amount3, _beneficiary);

        // Check contract balance
        assertEq(
            mockToken.balanceOf(address(factory)),
            amount1 + amount2 + amount3,
            "Contract should have total of all deposits"
        );

        // Check all three assets stored
        (,,, uint256 storedAmount1,,) = factory.getAsset(_grantor, 0);
        (,,, uint256 storedAmount2,,) = factory.getAsset(_grantor, 1);
        (,,, uint256 storedAmount3,,) = factory.getAsset(_grantor, 2);

        assertEq(storedAmount1, amount1, "First asset amount should match");
        assertEq(storedAmount2, amount2, "Second asset amount should match");
        assertEq(storedAmount3, amount3, "Third asset amount should match");

        // Check beneficiaryAssets has all three indices
        uint256[] memory assetIndices = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices[0], 0, "First asset index");
        assertEq(assetIndices[1], 1, "Second asset index");
        assertEq(assetIndices[2], 2, "Third asset index");
        vm.stopPrank();
    }

    function testDepositERC20MultipleBeneficiaries() public {
        vm.startPrank(_grantor);
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;
        uint256 amount3 = 3000 * 10 ** 18;

        mockToken.mint(_grantor, amount1 + amount2 + amount3);

        // Deposit to different beneficiaries
        mockToken.approve(address(factory), amount1);
        factory.depositERC20(address(mockToken), amount1, beneficiary1);

        mockToken.approve(address(factory), amount2);
        factory.depositERC20(address(mockToken), amount2, beneficiary2);

        mockToken.approve(address(factory), amount3);
        factory.depositERC20(address(mockToken), amount3, beneficiary3);

        // Check contract balance
        assertEq(
            mockToken.balanceOf(address(factory)), amount1 + amount2 + amount3, "Contract should have total balance"
        );

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

    function testDepositERC20WithDifferentTokens() public {
        // Create another ERC20 token
        MockERC20 mockToken2 = new MockERC20("MockToken2", "MTK2");

        vm.startPrank(_grantor);

        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;

        // Mint and deposit from first token
        mockToken.mint(_grantor, amount1);
        mockToken.approve(address(factory), amount1);
        factory.depositERC20(address(mockToken), amount1, _beneficiary);

        // Mint and deposit from second token
        mockToken2.mint(_grantor, amount2);
        mockToken2.approve(address(factory), amount2);
        factory.depositERC20(address(mockToken2), amount2, _beneficiary);

        // Check both tokens stored with correct addresses
        (, address token1,,,,) = factory.getAsset(_grantor, 0);
        (, address token2,,,,) = factory.getAsset(_grantor, 1);

        assertEq(token1, address(mockToken), "First token address should match");
        assertEq(token2, address(mockToken2), "Second token address should match");

        // Check balances
        assertEq(mockToken.balanceOf(address(factory)), amount1, "Token1 balance should match");
        assertEq(mockToken2.balanceOf(address(factory)), amount2, "Token2 balance should match");

        vm.stopPrank();
    }

    function testDepositERC20WithoutApprovalReverts() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        // Don't approve the transfer

        vm.expectRevert();
        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC20WithInsufficientBalanceReverts() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        // Mint less than deposit amount
        mockToken.mint(_grantor, depositAmount / 2);

        vm.startPrank(_grantor);
        mockToken.approve(address(factory), depositAmount);

        vm.expectRevert();
        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC20WithInsufficientAllowanceReverts() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        // Approve less than deposit amount
        mockToken.approve(address(factory), depositAmount / 2);

        vm.expectRevert();
        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC20MixedWithOtherAssets() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        uint256 tokenAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, tokenAmount);

        // Deposit ETH
        factory.depositETH{value: 1 ether}(_beneficiary);

        // Deposit ERC20
        mockToken.approve(address(factory), tokenAmount);
        factory.depositERC20(address(mockToken), tokenAmount, _beneficiary);

        // Deposit NFT
        uint256 tokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        // Check all assets stored correctly
        (DigitalWillFactory.AssetType type0,,,,,) = factory.getAsset(_grantor, 0);
        (DigitalWillFactory.AssetType type1,,,,,) = factory.getAsset(_grantor, 1);
        (DigitalWillFactory.AssetType type2,,,,,) = factory.getAsset(_grantor, 2);

        assertEq(uint256(type0), uint256(DigitalWillFactory.AssetType.ETH), "Asset 0 should be ETH");
        assertEq(uint256(type1), uint256(DigitalWillFactory.AssetType.ERC20), "Asset 1 should be ERC20");
        assertEq(uint256(type2), uint256(DigitalWillFactory.AssetType.ERC721), "Asset 2 should be ERC721");

        // Check beneficiaryAssets has all three
        uint256[] memory assetIndices761 = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices761[0], 0, "First asset index");
        uint256[] memory assetIndices766 = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices766[1], 1, "Second asset index");
        uint256[] memory assetIndices771 = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        assertEq(assetIndices771[2], 2, "Third asset index");

        vm.stopPrank();
    }

    // Fuzz tests
    function testFuzzDepositERC20Amount(uint256 amount) public {
        // Bound amount between 1 and 1 billion tokens (with 18 decimals)
        amount = bound(amount, 1, 1_000_000_000 * 10 ** 18);

        mockToken.mint(_grantor, amount);

        vm.startPrank(_grantor);
        mockToken.approve(address(factory), amount);

        factory.depositERC20(address(mockToken), amount, _beneficiary);

        // Verify balance and storage
        assertEq(mockToken.balanceOf(address(factory)), amount, "Contract balance should match deposit");
        (,,, uint256 storedAmount,,) = factory.getAsset(_grantor, 0);
        assertEq(storedAmount, amount, "Stored amount should match");

        vm.stopPrank();
    }

    function testFuzzDepositERC20MultipleBeneficiaries(address beneficiary1, address beneficiary2) public {
        // Ensure addresses are valid and different
        vm.assume(beneficiary1 != address(0));
        vm.assume(beneficiary2 != address(0));
        vm.assume(beneficiary1 != beneficiary2);

        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;

        mockToken.mint(_grantor, amount1 + amount2);

        vm.startPrank(_grantor);

        // Approve contract beneficiaries if needed
        if (_isContract(beneficiary1)) {
            factory.approveContractBeneficiary(beneficiary1);
        }
        if (_isContract(beneficiary2)) {
            factory.approveContractBeneficiary(beneficiary2);
        }

        // Deposit to first beneficiary
        mockToken.approve(address(factory), amount1);
        factory.depositERC20(address(mockToken), amount1, beneficiary1);

        // Deposit to second beneficiary
        mockToken.approve(address(factory), amount2);
        factory.depositERC20(address(mockToken), amount2, beneficiary2);

        // Verify storage
        (,,,, address stored1,) = factory.getAsset(_grantor, 0);
        (,,,, address stored2,) = factory.getAsset(_grantor, 1);

        assertEq(stored1, beneficiary1, "First beneficiary should match");
        assertEq(stored2, beneficiary2, "Second beneficiary should match");

        vm.stopPrank();
    }

    function testFuzzDepositERC20MultipleDeposits(uint8 numDeposits) public {
        // Bound to reasonable number of deposits (1-20)
        numDeposits = uint8(bound(numDeposits, 1, 20));

        uint256 depositAmount = 100 * 10 ** 18;
        uint256 totalAmount = depositAmount * numDeposits;

        mockToken.mint(_grantor, totalAmount);

        vm.startPrank(_grantor);

        for (uint256 i = 0; i < numDeposits; i++) {
            mockToken.approve(address(factory), depositAmount);
            factory.depositERC20(address(mockToken), depositAmount, _beneficiary);
        }

        // Verify all deposits
        assertEq(mockToken.balanceOf(address(factory)), totalAmount, "Contract should have all deposits");

        uint256[] memory erc20AssetIndices = factory.getBeneficiaryAssets(_grantor, _beneficiary);
        for (uint256 i = 0; i < numDeposits; i++) {
            (,,, uint256 storedAmount,,) = factory.getAsset(_grantor, i);
            assertEq(storedAmount, depositAmount, "Each deposit amount should match");
            assertEq(erc20AssetIndices[i], i, "Asset indices should match");
        }

        vm.stopPrank();
    }
}
