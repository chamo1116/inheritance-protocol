// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DigitalWill} from "../src/DigitalWill.sol";
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

contract DigitalWillTest is Test {
    DigitalWill public digitalWill;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;

    address public grantor_;
    address public randomUser_;
    address public beneficiary_;

    // Events to test
    event CheckIn(uint256 timestamp);
    event AssetDeposited(
        address indexed grantor,
        DigitalWill.AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        address beneficiary
    );

    function setUp() public {
        grantor_ = makeAddr("grantor");
        beneficiary_ = makeAddr("beneficiary");
        randomUser_ = makeAddr("randomUser");

        // Deploy mock contracts
        mockToken = new MockERC20("MockToken", "MTK");
        mockNFT = new MockERC721("MockNFT", "MNFT");

        // Deploy contract as grantor with 30 days heartbeat interval
        vm.prank(grantor_);
        digitalWill = new DigitalWill(30 days);
    }

    // Deploy contract
    function testDeployContract() public view {
        assertEq(digitalWill.grantor(), grantor_, "Grantor should be set correctly");
        assertEq(digitalWill.lastCheckIn(), block.timestamp, "Last check-in should be set correctly");
        assertEq(uint256(digitalWill.state()), uint256(DigitalWill.ContractState.ACTIVE));
    }

    function testDeployContractRevertsWithZeroHeartbeatInterval() public {
        vm.prank(grantor_);
        vm.expectRevert("Heartbeat interval must be greater than 0");
        new DigitalWill(0);
    }

    // Check in

    function testCheckInWithNotGrantor() public {
        vm.prank(randomUser_);
        vm.expectRevert("You are not the grantor");
        digitalWill.checkIn();
    }

    function testCheckInRevertsWhenNotActive() public {
        // Note: This test assumes there will be a way to change the contract state
        // Since the current contract doesn't have methods to change state,
        // we'll need to manually set it using vm.store for testing purposes

        // Arrange - Set contract state to CLAIMABLE (1)
        // Storage: slot 0=ReentrancyGuard, slot 1=lastCheckIn, slot 2=state, slot 3=heartbeatInterval
        // Note: grantor is immutable so not in storage
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        vm.expectRevert("Contract must be active");
        vm.prank(grantor_);
        digitalWill.checkIn();
    }

    function testCheckInSuccessfully() public {
        uint256 checkInTime = block.timestamp;

        vm.prank(grantor_);
        digitalWill.checkIn();

        assertEq(digitalWill.lastCheckIn(), checkInTime, "lastCheckIn should be updated to current timestamp");
    }

    function testCheckInEmitsEvent() public {
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit CheckIn(expectedTimestamp);

        vm.prank(grantor_);
        digitalWill.checkIn();
    }

    function testCheckInMultipleCheckIns() public {
        // First check-in
        vm.prank(grantor_);
        digitalWill.checkIn();
        uint256 firstCheckIn = digitalWill.lastCheckIn();

        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);

        // Second check-in
        vm.prank(grantor_);
        digitalWill.checkIn();
        uint256 secondCheckIn = digitalWill.lastCheckIn();

        assertGt(secondCheckIn, firstCheckIn, "Second check-in should have later timestamp");
        assertEq(secondCheckIn, block.timestamp, "Second check-in should match current block timestamp");
    }

    // Deposit ETH
    function testDepositETHRevertsWhenNotGrantor() public {
        vm.startPrank(randomUser_);
        vm.deal(randomUser_, 10 ether);
        vm.expectRevert("You are not the grantor");
        digitalWill.depositETH{value: 1 ether}(beneficiary_);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroValue() public {
        vm.startPrank(grantor_);
        vm.expectRevert("Must send ETH");
        digitalWill.depositETH{value: 0}(beneficiary_);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroAddressInBeneficiary() public {
        vm.startPrank(grantor_);
        vm.deal(grantor_, 10 ether);
        vm.expectRevert("Invalid beneficiary address");

        digitalWill.depositETH{value: 1 ether}(address(0));
        vm.stopPrank();
    }

    function testDepositETHRevertsWhenNotActive() public {
        vm.startPrank(grantor_);
        vm.deal(grantor_, 10 ether);
        // Set contract state to CLAIMABLE (1)
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        vm.expectRevert("Contract must be active");
        digitalWill.depositETH{value: 1 ether}(beneficiary_);
        vm.stopPrank();
    }

    function testDepositETHSuccessfully() public {
        vm.startPrank(grantor_);
        vm.deal(grantor_, 10 ether);
        uint256 depositAmount = 5 ether;

        uint256 initialBalance = address(digitalWill).balance;

        digitalWill.depositETH{value: depositAmount}(beneficiary_);

        // Check contract balance updated
        assertEq(
            address(digitalWill).balance,
            initialBalance + depositAmount,
            "Contract balance should increase by deposit amount"
        );
        // Check beneficiaryAssets mapping updated
        uint256 assetIndex = digitalWill.beneficiaryAssets(beneficiary_, 0);
        assertEq(assetIndex, 0, "Asset index should be 0 for first asset");
        vm.stopPrank();
    }

    function testDepositETHMultipleDeposits() public {
        vm.startPrank(grantor_);

        vm.deal(grantor_, 10 ether);

        // First deposit
        digitalWill.depositETH{value: 1 ether}(beneficiary_);

        // Second deposit
        digitalWill.depositETH{value: 2 ether}(beneficiary_);

        // Third deposit
        digitalWill.depositETH{value: 3 ether}(beneficiary_);

        // Check contract balance
        assertEq(address(digitalWill).balance, 6 ether, "Contract should have 6 ETH total");

        // Check all three assets stored
        (,,, uint256 amount1,,) = digitalWill.assets(0);
        (,,, uint256 amount2,,) = digitalWill.assets(1);
        (,,, uint256 amount3,,) = digitalWill.assets(2);

        assertEq(amount1, 1 ether, "First asset amount should be 1 ETH");
        assertEq(amount2, 2 ether, "Second asset amount should be 2 ETH");
        assertEq(amount3, 3 ether, "Third asset amount should be 3 ETH");

        // Check beneficiaryAssets has all three indices
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 2), 2, "Third asset index");
        vm.stopPrank();
    }

    function testDepositETHMultipleBeneficiaries() public {
        vm.startPrank(grantor_);
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.deal(grantor_, 10 ether);

        // Deposit to different beneficiaries

        digitalWill.depositETH{value: 1 ether}(beneficiary1);

        digitalWill.depositETH{value: 2 ether}(beneficiary2);

        digitalWill.depositETH{value: 3 ether}(beneficiary3);

        // Check contract balance
        assertEq(address(digitalWill).balance, 6 ether, "Contract should have 6 ETH total");

        // Check each beneficiary has correct asset
        (,,,, address stored1,) = digitalWill.assets(0);
        (,,,, address stored2,) = digitalWill.assets(1);
        (,,,, address stored3,) = digitalWill.assets(2);

        assertEq(stored1, beneficiary1, "First beneficiary should match");
        assertEq(stored2, beneficiary2, "Second beneficiary should match");
        assertEq(stored3, beneficiary3, "Third beneficiary should match");

        // Check each beneficiary's asset mapping
        assertEq(digitalWill.beneficiaryAssets(beneficiary1, 0), 0, "Beneficiary1 asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary2, 0), 1, "Beneficiary2 asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary3, 0), 2, "Beneficiary3 asset index");
        vm.stopPrank();
    }

    function testReceiveRevertsDirectETHTransferFromGrantor() public {
        vm.startPrank(grantor_);
        vm.deal(grantor_, 10 ether);

        vm.expectRevert("Use depositETH function");
        (bool success,) = address(digitalWill).call{value: 1 ether}("");
        success; // Silence unused variable warning

        vm.stopPrank();
    }

    // depositERC20

    function testDepositERC20RevertsWhenNotGrantor() public {
        uint256 depositAmount = 1000 * 10 ** 18; // 1000 tokens
        mockToken.mint(randomUser_, depositAmount);

        vm.startPrank(randomUser_);
        mockToken.approve(address(digitalWill), depositAmount);

        vm.expectRevert("You are not the grantor");
        digitalWill.depositERC20(address(mockToken), depositAmount, beneficiary_);
        vm.stopPrank();
    }

    function testDepositERC20RevertsWithInvalidTokenAddress() public {
        vm.startPrank(grantor_);
        vm.expectRevert("Invalid token address");
        digitalWill.depositERC20(address(0), 1000, beneficiary_);
        vm.stopPrank();
    }

    function testDepositERC20RevertsWithZeroAmount() public {
        vm.startPrank(grantor_);
        vm.expectRevert("Amount must be greater than 0");
        digitalWill.depositERC20(address(mockToken), 0, beneficiary_);
        vm.stopPrank();
    }

    function testDepositERC20RevertsWithInvalidBeneficiaryAddress() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(grantor_, depositAmount);

        vm.startPrank(grantor_);
        mockToken.approve(address(digitalWill), depositAmount);

        vm.expectRevert("Invalid beneficiary address");
        digitalWill.depositERC20(address(mockToken), depositAmount, address(0));
        vm.stopPrank();
    }

    function testDepositERC20RevertsWhenNotActive() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(grantor_, depositAmount);

        vm.startPrank(grantor_);
        mockToken.approve(address(digitalWill), depositAmount);

        // Set contract state to CLAIMABLE (1)
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        vm.expectRevert("Contract must be active");
        digitalWill.depositERC20(address(mockToken), depositAmount, beneficiary_);
        vm.stopPrank();
    }

    function testDepositERC20Successfully() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(grantor_, depositAmount);

        vm.startPrank(grantor_);
        mockToken.approve(address(digitalWill), depositAmount);

        uint256 initialBalance = mockToken.balanceOf(address(digitalWill));

        digitalWill.depositERC20(address(mockToken), depositAmount, beneficiary_);

        // Check contract balance updated
        assertEq(
            mockToken.balanceOf(address(digitalWill)),
            initialBalance + depositAmount,
            "Contract balance should increase by deposit amount"
        );

        // Check asset stored correctly
        (
            DigitalWill.AssetType assetType,
            address tokenAddress,
            uint256 tokenId,
            uint256 amount,
            address storedBeneficiary,
            bool claimed
        ) = digitalWill.assets(0);

        assertEq(uint256(assetType), uint256(DigitalWill.AssetType.ERC20), "Asset type should be ERC20");
        assertEq(tokenAddress, address(mockToken), "Token address should match");
        assertEq(tokenId, 0, "Token ID should be 0 for ERC20");
        assertEq(amount, depositAmount, "Amount should match");
        assertEq(storedBeneficiary, beneficiary_, "Beneficiary should match");
        assertFalse(claimed, "Should not be claimed");

        // Check beneficiaryAssets mapping updated
        uint256 assetIndex = digitalWill.beneficiaryAssets(beneficiary_, 0);
        assertEq(assetIndex, 0, "Asset index should be 0 for first asset");
        vm.stopPrank();
    }

    function testDepositERC20EmitsEvent() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(grantor_, depositAmount);

        vm.startPrank(grantor_);
        mockToken.approve(address(digitalWill), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit AssetDeposited(grantor_, DigitalWill.AssetType.ERC20, address(mockToken), 0, depositAmount, beneficiary_);

        digitalWill.depositERC20(address(mockToken), depositAmount, beneficiary_);
        vm.stopPrank();
    }

    function testDepositERC20MultipleDeposits() public {
        vm.startPrank(grantor_);

        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;
        uint256 amount3 = 3000 * 10 ** 18;

        mockToken.mint(grantor_, amount1 + amount2 + amount3);

        // First deposit
        mockToken.approve(address(digitalWill), amount1);
        digitalWill.depositERC20(address(mockToken), amount1, beneficiary_);

        // Second deposit
        mockToken.approve(address(digitalWill), amount2);
        digitalWill.depositERC20(address(mockToken), amount2, beneficiary_);

        // Third deposit
        mockToken.approve(address(digitalWill), amount3);
        digitalWill.depositERC20(address(mockToken), amount3, beneficiary_);

        // Check contract balance
        assertEq(
            mockToken.balanceOf(address(digitalWill)),
            amount1 + amount2 + amount3,
            "Contract should have total of all deposits"
        );

        // Check all three assets stored
        (,,, uint256 storedAmount1,,) = digitalWill.assets(0);
        (,,, uint256 storedAmount2,,) = digitalWill.assets(1);
        (,,, uint256 storedAmount3,,) = digitalWill.assets(2);

        assertEq(storedAmount1, amount1, "First asset amount should match");
        assertEq(storedAmount2, amount2, "Second asset amount should match");
        assertEq(storedAmount3, amount3, "Third asset amount should match");

        // Check beneficiaryAssets has all three indices
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 2), 2, "Third asset index");
        vm.stopPrank();
    }

    function testDepositERC20MultipleBeneficiaries() public {
        vm.startPrank(grantor_);
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;
        uint256 amount3 = 3000 * 10 ** 18;

        mockToken.mint(grantor_, amount1 + amount2 + amount3);

        // Deposit to different beneficiaries
        mockToken.approve(address(digitalWill), amount1);
        digitalWill.depositERC20(address(mockToken), amount1, beneficiary1);

        mockToken.approve(address(digitalWill), amount2);
        digitalWill.depositERC20(address(mockToken), amount2, beneficiary2);

        mockToken.approve(address(digitalWill), amount3);
        digitalWill.depositERC20(address(mockToken), amount3, beneficiary3);

        // Check contract balance
        assertEq(
            mockToken.balanceOf(address(digitalWill)), amount1 + amount2 + amount3, "Contract should have total balance"
        );

        // Check each beneficiary has correct asset
        (,,,, address stored1,) = digitalWill.assets(0);
        (,,,, address stored2,) = digitalWill.assets(1);
        (,,,, address stored3,) = digitalWill.assets(2);

        assertEq(stored1, beneficiary1, "First beneficiary should match");
        assertEq(stored2, beneficiary2, "Second beneficiary should match");
        assertEq(stored3, beneficiary3, "Third beneficiary should match");

        // Check each beneficiary's asset mapping
        assertEq(digitalWill.beneficiaryAssets(beneficiary1, 0), 0, "Beneficiary1 asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary2, 0), 1, "Beneficiary2 asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary3, 0), 2, "Beneficiary3 asset index");
        vm.stopPrank();
    }

    function testDepositERC20WithDifferentTokens() public {
        // Create another ERC20 token
        MockERC20 mockToken2 = new MockERC20("MockToken2", "MTK2");

        vm.startPrank(grantor_);

        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;

        // Mint and deposit from first token
        mockToken.mint(grantor_, amount1);
        mockToken.approve(address(digitalWill), amount1);
        digitalWill.depositERC20(address(mockToken), amount1, beneficiary_);

        // Mint and deposit from second token
        mockToken2.mint(grantor_, amount2);
        mockToken2.approve(address(digitalWill), amount2);
        digitalWill.depositERC20(address(mockToken2), amount2, beneficiary_);

        // Check both tokens stored with correct addresses
        (, address token1,,,,) = digitalWill.assets(0);
        (, address token2,,,,) = digitalWill.assets(1);

        assertEq(token1, address(mockToken), "First token address should match");
        assertEq(token2, address(mockToken2), "Second token address should match");

        // Check balances
        assertEq(mockToken.balanceOf(address(digitalWill)), amount1, "Token1 balance should match");
        assertEq(mockToken2.balanceOf(address(digitalWill)), amount2, "Token2 balance should match");

        vm.stopPrank();
    }

    function testDepositERC20WithoutApprovalReverts() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(grantor_, depositAmount);

        vm.startPrank(grantor_);
        // Don't approve the transfer

        vm.expectRevert();
        digitalWill.depositERC20(address(mockToken), depositAmount, beneficiary_);

        vm.stopPrank();
    }

    function testDepositERC20WithInsufficientBalanceReverts() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        // Mint less than deposit amount
        mockToken.mint(grantor_, depositAmount / 2);

        vm.startPrank(grantor_);
        mockToken.approve(address(digitalWill), depositAmount);

        vm.expectRevert();
        digitalWill.depositERC20(address(mockToken), depositAmount, beneficiary_);

        vm.stopPrank();
    }

    function testDepositERC20WithInsufficientAllowanceReverts() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(grantor_, depositAmount);

        vm.startPrank(grantor_);
        // Approve less than deposit amount
        mockToken.approve(address(digitalWill), depositAmount / 2);

        vm.expectRevert();
        digitalWill.depositERC20(address(mockToken), depositAmount, beneficiary_);

        vm.stopPrank();
    }

    function testDepositERC20MixedWithOtherAssets() public {
        vm.startPrank(grantor_);
        vm.deal(grantor_, 10 ether);

        uint256 tokenAmount = 1000 * 10 ** 18;
        mockToken.mint(grantor_, tokenAmount);

        // Deposit ETH
        digitalWill.depositETH{value: 1 ether}(beneficiary_);

        // Deposit ERC20
        mockToken.approve(address(digitalWill), tokenAmount);
        digitalWill.depositERC20(address(mockToken), tokenAmount, beneficiary_);

        // Deposit NFT
        uint256 tokenId = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId);
        digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);

        // Check all assets stored correctly
        (DigitalWill.AssetType type0,,,,,) = digitalWill.assets(0);
        (DigitalWill.AssetType type1,,,,,) = digitalWill.assets(1);
        (DigitalWill.AssetType type2,,,,,) = digitalWill.assets(2);

        assertEq(uint256(type0), uint256(DigitalWill.AssetType.ETH), "Asset 0 should be ETH");
        assertEq(uint256(type1), uint256(DigitalWill.AssetType.ERC20), "Asset 1 should be ERC20");
        assertEq(uint256(type2), uint256(DigitalWill.AssetType.ERC721), "Asset 2 should be ERC721");

        // Check beneficiaryAssets has all three
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 2), 2, "Third asset index");

        vm.stopPrank();
    }

    // depositERC721

    function testDepositERC721RevertsWhenNotGrantor() public {
        // Mint NFT to random user
        uint256 tokenId = mockNFT.mint(randomUser_);

        vm.startPrank(randomUser_);
        mockNFT.approve(address(digitalWill), tokenId);

        vm.expectRevert("You are not the grantor");
        digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);
        vm.stopPrank();
    }

    function testDepositERC721RevertsWithInvalidTokenAddress() public {
        vm.startPrank(grantor_);

        vm.expectRevert("Invalid token address");
        digitalWill.depositERC721(address(0), 1, beneficiary_);

        vm.stopPrank();
    }

    function testDepositERC721RevertsWithInvalidBeneficiaryAddress() public {
        uint256 tokenId = mockNFT.mint(grantor_);

        vm.startPrank(grantor_);
        mockNFT.approve(address(digitalWill), tokenId);

        vm.expectRevert("Invalid beneficiary address");
        digitalWill.depositERC721(address(mockNFT), tokenId, address(0));

        vm.stopPrank();
    }

    function testDepositERC721RevertsWhenOwnerIsNotGrantor() public {
        uint256 tokenId = mockNFT.mint(randomUser_);

        vm.startPrank(grantor_);

        vm.expectRevert("Not the owner of NFT");
        digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);

        vm.stopPrank();
    }

    function testDepositERC721RevertsWhenNotActive() public {
        uint256 tokenId = mockNFT.mint(grantor_);

        vm.startPrank(grantor_);
        mockNFT.approve(address(digitalWill), tokenId);

        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        vm.expectRevert("Contract must be active");
        digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);

        vm.stopPrank();
    }

    function testDepositERC721Successfully() public {
        uint256 tokenId = mockNFT.mint(grantor_);

        vm.startPrank(grantor_);
        mockNFT.approve(address(digitalWill), tokenId);

        digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);

        // Check NFT ownership transferred
        assertEq(mockNFT.ownerOf(tokenId), address(digitalWill), "NFT should be owned by contract");

        // Check asset stored correctly
        (
            DigitalWill.AssetType assetType,
            address tokenAddress,
            uint256 storedTokenId,
            uint256 amount,
            address storedBeneficiary,
            bool claimed
        ) = digitalWill.assets(0);

        assertEq(uint256(assetType), uint256(DigitalWill.AssetType.ERC721), "Asset type should be ERC721");
        assertEq(tokenAddress, address(mockNFT), "Token address should match");
        assertEq(storedTokenId, tokenId, "Token ID should match");
        assertEq(amount, 1, "Amount should be 1");
        assertEq(storedBeneficiary, beneficiary_, "Beneficiary should match");
        assertFalse(claimed, "Should not be claimed");

        // Check beneficiaryAssets mapping
        uint256 assetIndex = digitalWill.beneficiaryAssets(beneficiary_, 0);
        assertEq(assetIndex, 0, "Asset index should be 0");

        vm.stopPrank();
    }

    function testDepositERC721EmitsEvent() public {
        // Mint NFT to grantor
        uint256 tokenId = mockNFT.mint(grantor_);

        vm.startPrank(grantor_);
        mockNFT.approve(address(digitalWill), tokenId);

        vm.expectEmit(true, true, true, true);
        emit AssetDeposited(grantor_, DigitalWill.AssetType.ERC721, address(mockNFT), tokenId, 1, beneficiary_);

        digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);

        vm.stopPrank();
    }

    function testDepositERC721MultipleNFTsToSameBeneficiary() public {
        vm.startPrank(grantor_);

        // Mint and deposit multiple NFTs
        uint256 tokenId1 = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId1);
        digitalWill.depositERC721(address(mockNFT), tokenId1, beneficiary_);

        uint256 tokenId2 = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId2);
        digitalWill.depositERC721(address(mockNFT), tokenId2, beneficiary_);

        uint256 tokenId3 = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId3);
        digitalWill.depositERC721(address(mockNFT), tokenId3, beneficiary_);

        // Check all NFTs are owned by contract
        assertEq(mockNFT.ownerOf(tokenId1), address(digitalWill), "NFT 1 should be owned by contract");
        assertEq(mockNFT.ownerOf(tokenId2), address(digitalWill), "NFT 2 should be owned by contract");
        assertEq(mockNFT.ownerOf(tokenId3), address(digitalWill), "NFT 3 should be owned by contract");

        // Check all assets stored
        (,, uint256 storedId1,,,) = digitalWill.assets(0);
        (,, uint256 storedId2,,,) = digitalWill.assets(1);
        (,, uint256 storedId3,,,) = digitalWill.assets(2);

        assertEq(storedId1, tokenId1, "Token ID 1 should match");
        assertEq(storedId2, tokenId2, "Token ID 2 should match");
        assertEq(storedId3, tokenId3, "Token ID 3 should match");

        // Check beneficiaryAssets mapping has all three
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 2), 2, "Third asset index");

        vm.stopPrank();
    }

    function testDepositERC721MultipleBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.startPrank(grantor_);

        // Mint and deposit NFTs to different beneficiaries
        uint256 tokenId1 = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId1);
        digitalWill.depositERC721(address(mockNFT), tokenId1, beneficiary1);

        uint256 tokenId2 = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId2);
        digitalWill.depositERC721(address(mockNFT), tokenId2, beneficiary2);

        uint256 tokenId3 = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId3);
        digitalWill.depositERC721(address(mockNFT), tokenId3, beneficiary3);

        // Check each beneficiary has correct asset
        (,,,, address stored1,) = digitalWill.assets(0);
        (,,,, address stored2,) = digitalWill.assets(1);
        (,,,, address stored3,) = digitalWill.assets(2);

        assertEq(stored1, beneficiary1, "Beneficiary 1 should match");
        assertEq(stored2, beneficiary2, "Beneficiary 2 should match");
        assertEq(stored3, beneficiary3, "Beneficiary 3 should match");

        // Check each beneficiary's asset mapping
        assertEq(digitalWill.beneficiaryAssets(beneficiary1, 0), 0, "Beneficiary1 asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary2, 0), 1, "Beneficiary2 asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary3, 0), 2, "Beneficiary3 asset index");

        vm.stopPrank();
    }

    function testDepositERC721WithDifferentNFTCollections() public {
        // Create another NFT collection
        MockERC721 mockNFT2 = new MockERC721("MockNFT2", "MNFT2");

        vm.startPrank(grantor_);

        // Mint and deposit from first collection
        uint256 tokenId1 = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId1);
        digitalWill.depositERC721(address(mockNFT), tokenId1, beneficiary_);

        // Mint and deposit from second collection
        uint256 tokenId2 = mockNFT2.mint(grantor_);
        mockNFT2.approve(address(digitalWill), tokenId2);
        digitalWill.depositERC721(address(mockNFT2), tokenId2, beneficiary_);

        // Check both NFTs stored with correct addresses
        (, address token1,,,,) = digitalWill.assets(0);
        (, address token2,,,,) = digitalWill.assets(1);

        assertEq(token1, address(mockNFT), "First token address should match");
        assertEq(token2, address(mockNFT2), "Second token address should match");

        // Check ownership
        assertEq(mockNFT.ownerOf(tokenId1), address(digitalWill), "NFT 1 should be owned by contract");
        assertEq(mockNFT2.ownerOf(tokenId2), address(digitalWill), "NFT 2 should be owned by contract");

        vm.stopPrank();
    }

    function testDepositERC721WithoutApprovalReverts() public {
        // Mint NFT to grantor
        uint256 tokenId = mockNFT.mint(grantor_);

        vm.startPrank(grantor_);
        // Don't approve the transfer

        vm.expectRevert();
        digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);

        vm.stopPrank();
    }

    function testDepositERC721NonExistentTokenReverts() public {
        uint256 nonExistentTokenId = 999;

        vm.startPrank(grantor_);

        vm.expectRevert();
        digitalWill.depositERC721(address(mockNFT), nonExistentTokenId, beneficiary_);

        vm.stopPrank();
    }

    function testDepositERC721MixedWithETHDeposits() public {
        vm.startPrank(grantor_);
        vm.deal(grantor_, 10 ether);

        // Deposit ETH
        digitalWill.depositETH{value: 1 ether}(beneficiary_);

        // Deposit NFT
        uint256 tokenId = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId);
        digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);

        // Deposit more ETH
        digitalWill.depositETH{value: 2 ether}(beneficiary_);

        // Check all assets stored correctly
        (DigitalWill.AssetType type0,,,,,) = digitalWill.assets(0);
        (DigitalWill.AssetType type1,,,,,) = digitalWill.assets(1);
        (DigitalWill.AssetType type2,,,,,) = digitalWill.assets(2);

        assertEq(uint256(type0), uint256(DigitalWill.AssetType.ETH), "Asset 0 should be ETH");
        assertEq(uint256(type1), uint256(DigitalWill.AssetType.ERC721), "Asset 1 should be ERC721");
        assertEq(uint256(type2), uint256(DigitalWill.AssetType.ETH), "Asset 2 should be ETH");

        // Check beneficiaryAssets has all three
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(beneficiary_, 2), 2, "Third asset index");

        vm.stopPrank();
    }

    // isClaimable Tests

    function testIsClaimableReturnsTrueWhenStateIsClaimable() public {
        // Set state to CLAIMABLE
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        bool result = digitalWill.isClaimable();
        assertTrue(result, "Should return true when state is CLAIMABLE");
    }

    function testIsClaimableReturnsFalseWhenActiveAndHeartbeatNotExpired() public view {
        // State is ACTIVE (default), and we're still within heartbeat interval
        bool result = digitalWill.isClaimable();
        assertFalse(result, "Should return false when ACTIVE and heartbeat not expired");
    }

    function testIsClaimableReturnsTrueWhenActiveAndHeartbeatExpired() public {
        // State is ACTIVE, advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        bool result = digitalWill.isClaimable();
        assertTrue(result, "Should return true when ACTIVE and heartbeat expired");
    }

    function testIsClaimableAtExactHeartbeatBoundary() public {
        // Test at exact boundary (lastCheckIn + heartbeatInterval)
        vm.warp(block.timestamp + 30 days);

        bool result = digitalWill.isClaimable();
        assertTrue(result, "Should return true at exact heartbeat boundary");
    }

    function testIsClaimableReturnsFalseWhenCompleted() public {
        // Set state to COMPLETED
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(2)) // ContractState.COMPLETED
        );

        bool result = digitalWill.isClaimable();
        assertFalse(result, "Should return false when state is COMPLETED");
    }

    function testIsClaimableAfterCheckIn() public {
        // First check that it's not claimable
        assertFalse(digitalWill.isClaimable(), "Should not be claimable initially");

        // Warp time to make it claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
        assertTrue(digitalWill.isClaimable(), "Should be claimable after heartbeat expired");

        // Check in to reset timer
        vm.prank(grantor_);
        digitalWill.checkIn();

        // Should no longer be claimable
        assertFalse(digitalWill.isClaimable(), "Should not be claimable after check-in");
    }

    function testIsClaimableJustBeforeHeartbeatExpires() public {
        // Advance time to 1 second before expiration
        vm.warp(block.timestamp + 30 days - 1 seconds);

        bool result = digitalWill.isClaimable();
        assertFalse(result, "Should return false just before heartbeat expires");
    }

    // updateState Tests

    function testUpdateStateChangesActiveToClaimableWhenHeartbeatExpired() public {
        // Verify initial state is ACTIVE
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.ACTIVE), "Initial state should be ACTIVE"
        );

        // Advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Call updateState
        digitalWill.updateState();

        // Verify state changed to CLAIMABLE
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.CLAIMABLE),
            "State should be CLAIMABLE after update"
        );
    }

    function testUpdateStateDoesNotChangeStateWhenHeartbeatNotExpired() public {
        // Verify initial state is ACTIVE
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.ACTIVE), "Initial state should be ACTIVE"
        );

        // Call updateState (heartbeat not expired)
        digitalWill.updateState();

        // Verify state remains ACTIVE
        assertEq(uint256(digitalWill.state()), uint256(DigitalWill.ContractState.ACTIVE), "State should remain ACTIVE");
    }

    function testUpdateStateDoesNotChangeWhenAlreadyClaimable() public {
        // Advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // First call to updateState
        digitalWill.updateState();
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.CLAIMABLE), "State should be CLAIMABLE"
        );

        // Second call to updateState
        digitalWill.updateState();

        // Verify state remains CLAIMABLE
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.CLAIMABLE), "State should remain CLAIMABLE"
        );
    }

    function testUpdateStateDoesNotChangeWhenCompleted() public {
        // Set state to COMPLETED
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(2)) // ContractState.COMPLETED
        );

        // Advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Call updateState
        digitalWill.updateState();

        // Verify state remains COMPLETED
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.COMPLETED), "State should remain COMPLETED"
        );
    }

    function testUpdateStateCanBeCalledByAnyone() public {
        // Advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Call updateState as random user
        vm.prank(randomUser_);
        digitalWill.updateState();

        // Verify state changed to CLAIMABLE
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.CLAIMABLE), "State should be CLAIMABLE"
        );
    }

    function testUpdateStateAtExactHeartbeatBoundary() public {
        // Advance time to exactly heartbeatInterval
        vm.warp(block.timestamp + 30 days);

        // Call updateState
        digitalWill.updateState();

        // Verify state changed to CLAIMABLE
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.CLAIMABLE),
            "State should be CLAIMABLE at exact boundary"
        );
    }

    function testUpdateStateMultipleCallsAfterExpiration() public {
        // Advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // First call
        digitalWill.updateState();
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.CLAIMABLE),
            "State should be CLAIMABLE after first call"
        );

        // Advance time further
        vm.warp(block.timestamp + 10 days);

        // Second call
        digitalWill.updateState();
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.CLAIMABLE),
            "State should remain CLAIMABLE after second call"
        );
    }

    function testUpdateStateAfterMultipleCheckIns() public {
        // First check-in at deployment
        assertEq(uint256(digitalWill.state()), uint256(DigitalWill.ContractState.ACTIVE), "Should start ACTIVE");

        // Advance time but not beyond heartbeat
        vm.warp(block.timestamp + 15 days);

        // Check in again
        vm.prank(grantor_);
        digitalWill.checkIn();

        // Update state should not change anything
        digitalWill.updateState();
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.ACTIVE),
            "Should remain ACTIVE after check-in"
        );

        // Now advance beyond new heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Update state should now change to CLAIMABLE
        digitalWill.updateState();
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.CLAIMABLE),
            "Should be CLAIMABLE after expiration"
        );
    }

    // ===========================================
    // FUZZ TESTS
    // ===========================================

    // Fuzz Tests - checkIn

    function testFuzzCheckInUpdatesTimestamp(uint256 timeWarp) public {
        // Bound the time warp to reasonable values (0 to 365 days)
        timeWarp = bound(timeWarp, 0, 365 days);

        // Warp to future time
        vm.warp(block.timestamp + timeWarp);

        vm.prank(grantor_);
        digitalWill.checkIn();

        assertEq(digitalWill.lastCheckIn(), block.timestamp, "lastCheckIn should match current timestamp");
    }

    // Fuzz Tests - depositETH

    function testFuzzDepositETHAmount(uint256 amount) public {
        // Bound amount between 0.001 ether and 1000 ether
        amount = bound(amount, 0.001 ether, 1000 ether);

        vm.startPrank(grantor_);
        vm.deal(grantor_, amount);

        digitalWill.depositETH{value: amount}(beneficiary_);

        // Verify balance and storage
        assertEq(address(digitalWill).balance, amount, "Contract balance should match deposit");
        (,,, uint256 storedAmount,,) = digitalWill.assets(0);
        assertEq(storedAmount, amount, "Stored amount should match");

        vm.stopPrank();
    }

    // Fuzz Tests - depositERC721

    function testFuzzDepositERC721TokenId(uint256 tokenId) public {
        // Bound token ID to reasonable range
        tokenId = bound(tokenId, 0, type(uint128).max);

        vm.startPrank(grantor_);

        // Mint with specific token ID
        mockNFT.mintWithId(grantor_, tokenId);
        mockNFT.approve(address(digitalWill), tokenId);

        digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);

        // Verify storage
        (,, uint256 storedTokenId,,,) = digitalWill.assets(0);
        assertEq(storedTokenId, tokenId, "Token ID should match");
        assertEq(mockNFT.ownerOf(tokenId), address(digitalWill), "Contract should own NFT");

        vm.stopPrank();
    }

    function testFuzzDepositERC721MultipleBeneficiaries(address beneficiary1, address beneficiary2) public {
        // Ensure addresses are valid and different
        vm.assume(beneficiary1 != address(0));
        vm.assume(beneficiary2 != address(0));
        vm.assume(beneficiary1 != beneficiary2);

        vm.startPrank(grantor_);

        // Mint and deposit to first beneficiary
        uint256 tokenId1 = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId1);
        digitalWill.depositERC721(address(mockNFT), tokenId1, beneficiary1);

        // Mint and deposit to second beneficiary
        uint256 tokenId2 = mockNFT.mint(grantor_);
        mockNFT.approve(address(digitalWill), tokenId2);
        digitalWill.depositERC721(address(mockNFT), tokenId2, beneficiary2);

        // Verify storage
        (,,,, address stored1,) = digitalWill.assets(0);
        (,,,, address stored2,) = digitalWill.assets(1);

        assertEq(stored1, beneficiary1, "First beneficiary should match");
        assertEq(stored2, beneficiary2, "Second beneficiary should match");

        vm.stopPrank();
    }

    function testFuzzDepositERC721MultipleTokens(uint8 numTokens) public {
        // Bound to reasonable number of tokens (1-20)
        numTokens = uint8(bound(numTokens, 1, 20));

        vm.startPrank(grantor_);

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = mockNFT.mint(grantor_);
            mockNFT.approve(address(digitalWill), tokenId);
            digitalWill.depositERC721(address(mockNFT), tokenId, beneficiary_);
        }

        // Verify all tokens deposited
        for (uint256 i = 0; i < numTokens; i++) {
            assertEq(mockNFT.ownerOf(i), address(digitalWill), "Contract should own all NFTs");
            uint256 assetIndex = digitalWill.beneficiaryAssets(beneficiary_, i);
            assertEq(assetIndex, i, "Asset indices should match");
        }

        vm.stopPrank();
    }

    // Fuzz Tests - depositERC20

    function testFuzzDepositERC20Amount(uint256 amount) public {
        // Bound amount between 1 and 1 billion tokens (with 18 decimals)
        amount = bound(amount, 1, 1_000_000_000 * 10 ** 18);

        mockToken.mint(grantor_, amount);

        vm.startPrank(grantor_);
        mockToken.approve(address(digitalWill), amount);

        digitalWill.depositERC20(address(mockToken), amount, beneficiary_);

        // Verify balance and storage
        assertEq(mockToken.balanceOf(address(digitalWill)), amount, "Contract balance should match deposit");
        (,,, uint256 storedAmount,,) = digitalWill.assets(0);
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

        mockToken.mint(grantor_, amount1 + amount2);

        vm.startPrank(grantor_);

        // Deposit to first beneficiary
        mockToken.approve(address(digitalWill), amount1);
        digitalWill.depositERC20(address(mockToken), amount1, beneficiary1);

        // Deposit to second beneficiary
        mockToken.approve(address(digitalWill), amount2);
        digitalWill.depositERC20(address(mockToken), amount2, beneficiary2);

        // Verify storage
        (,,,, address stored1,) = digitalWill.assets(0);
        (,,,, address stored2,) = digitalWill.assets(1);

        assertEq(stored1, beneficiary1, "First beneficiary should match");
        assertEq(stored2, beneficiary2, "Second beneficiary should match");

        vm.stopPrank();
    }

    function testFuzzDepositERC20MultipleDeposits(uint8 numDeposits) public {
        // Bound to reasonable number of deposits (1-20)
        numDeposits = uint8(bound(numDeposits, 1, 20));

        uint256 depositAmount = 100 * 10 ** 18;
        uint256 totalAmount = depositAmount * numDeposits;

        mockToken.mint(grantor_, totalAmount);

        vm.startPrank(grantor_);

        for (uint256 i = 0; i < numDeposits; i++) {
            mockToken.approve(address(digitalWill), depositAmount);
            digitalWill.depositERC20(address(mockToken), depositAmount, beneficiary_);
        }

        // Verify all deposits
        assertEq(mockToken.balanceOf(address(digitalWill)), totalAmount, "Contract should have all deposits");

        for (uint256 i = 0; i < numDeposits; i++) {
            (,,, uint256 storedAmount,,) = digitalWill.assets(i);
            assertEq(storedAmount, depositAmount, "Each deposit amount should match");
            uint256 assetIndex = digitalWill.beneficiaryAssets(beneficiary_, i);
            assertEq(assetIndex, i, "Asset indices should match");
        }

        vm.stopPrank();
    }

    // Fuzz Tests - isClaimable and updateState

    function testFuzzIsClaimableWithVariousTimeOffsets(uint256 timeOffset) public {
        // Bound time offset to reasonable range (0 to 365 days)
        timeOffset = bound(timeOffset, 0, 365 days);

        vm.warp(block.timestamp + timeOffset);

        bool expectedResult = timeOffset >= 30 days;
        bool actualResult = digitalWill.isClaimable();

        assertEq(actualResult, expectedResult, "isClaimable result should match expected based on time offset");
    }

    function testFuzzUpdateStateWithVariousTimeOffsets(uint256 timeOffset) public {
        // Bound time offset to reasonable range (0 to 365 days)
        timeOffset = bound(timeOffset, 0, 365 days);

        vm.warp(block.timestamp + timeOffset);

        // Call updateState
        digitalWill.updateState();

        // Expected state
        DigitalWill.ContractState expectedState =
            timeOffset >= 30 days ? DigitalWill.ContractState.CLAIMABLE : DigitalWill.ContractState.ACTIVE;

        assertEq(
            uint256(digitalWill.state()), uint256(expectedState), "State should match expected based on time offset"
        );
    }
}
