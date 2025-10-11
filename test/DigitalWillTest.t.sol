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

    address public _grantor;
    address public _randomUser;
    address public _beneficiary;

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
        _grantor = makeAddr("grantor");
        _beneficiary = makeAddr("beneficiary");
        _randomUser = makeAddr("randomUser");

        // Deploy mock contracts
        mockToken = new MockERC20("MockToken", "MTK");
        mockNFT = new MockERC721("MockNFT", "MNFT");

        // Deploy contract as grantor with 30 days heartbeat interval
        vm.prank(_grantor);
        digitalWill = new DigitalWill(30 days);
    }

    // Deploy contract
    function testDeployContract() public view {
        assertEq(digitalWill.grantor(), _grantor, "Grantor should be set correctly");
        assertEq(digitalWill.lastCheckIn(), block.timestamp, "Last check-in should be set correctly");
        assertEq(uint256(digitalWill.state()), uint256(DigitalWill.ContractState.ACTIVE));
    }

    function testDeployContractRevertsWithZeroHeartbeatInterval() public {
        vm.prank(_grantor);
        vm.expectRevert("Heartbeat interval must be greater than 0");
        new DigitalWill(0);
    }

    // Check in

    function testCheckInWithNotGrantor() public {
        vm.prank(_randomUser);
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
        vm.prank(_grantor);
        digitalWill.checkIn();
    }

    function testCheckInSuccessfully() public {
        uint256 checkInTime = block.timestamp;

        vm.prank(_grantor);
        digitalWill.checkIn();

        assertEq(digitalWill.lastCheckIn(), checkInTime, "lastCheckIn should be updated to current timestamp");
    }

    function testCheckInEmitsEvent() public {
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit CheckIn(expectedTimestamp);

        vm.prank(_grantor);
        digitalWill.checkIn();
    }

    function testCheckInMultipleCheckIns() public {
        // First check-in
        vm.prank(_grantor);
        digitalWill.checkIn();
        uint256 firstCheckIn = digitalWill.lastCheckIn();

        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);

        // Second check-in
        vm.prank(_grantor);
        digitalWill.checkIn();
        uint256 secondCheckIn = digitalWill.lastCheckIn();

        assertGt(secondCheckIn, firstCheckIn, "Second check-in should have later timestamp");
        assertEq(secondCheckIn, block.timestamp, "Second check-in should match current block timestamp");
    }

    // Deposit ETH
    function testDepositETHRevertsWhenNotGrantor() public {
        vm.startPrank(_randomUser);
        vm.deal(_randomUser, 10 ether);
        vm.expectRevert("You are not the grantor");
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroValue() public {
        vm.startPrank(_grantor);
        vm.expectRevert("Must send ETH");
        digitalWill.depositETH{value: 0}(_beneficiary);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroAddressInBeneficiary() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        vm.expectRevert("Invalid beneficiary address");

        digitalWill.depositETH{value: 1 ether}(address(0));
        vm.stopPrank();
    }

    function testDepositETHRevertsWhenNotActive() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        // Set contract state to CLAIMABLE (1)
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        vm.expectRevert("Contract must be active");
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();
    }

    function testDepositETHSuccessfully() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        uint256 depositAmount = 5 ether;

        uint256 initialBalance = address(digitalWill).balance;

        digitalWill.depositETH{value: depositAmount}(_beneficiary);

        // Check contract balance updated
        assertEq(
            address(digitalWill).balance,
            initialBalance + depositAmount,
            "Contract balance should increase by deposit amount"
        );
        // Check beneficiaryAssets mapping updated
        uint256 assetIndex = digitalWill.beneficiaryAssets(_beneficiary, 0);
        assertEq(assetIndex, 0, "Asset index should be 0 for first asset");
        vm.stopPrank();
    }

    function testDepositETHMultipleDeposits() public {
        vm.startPrank(_grantor);

        vm.deal(_grantor, 10 ether);

        // First deposit
        digitalWill.depositETH{value: 1 ether}(_beneficiary);

        // Second deposit
        digitalWill.depositETH{value: 2 ether}(_beneficiary);

        // Third deposit
        digitalWill.depositETH{value: 3 ether}(_beneficiary);

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
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 2), 2, "Third asset index");
        vm.stopPrank();
    }

    function testDepositETHMultipleBeneficiaries() public {
        vm.startPrank(_grantor);
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.deal(_grantor, 10 ether);

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
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        vm.expectRevert("Use depositETH function");
        (bool success,) = address(digitalWill).call{value: 1 ether}("");
        success; // Silence unused variable warning

        vm.stopPrank();
    }

    // depositERC20

    function testDepositERC20RevertsWhenNotGrantor() public {
        uint256 depositAmount = 1000 * 10 ** 18; // 1000 tokens
        mockToken.mint(_randomUser, depositAmount);

        vm.startPrank(_randomUser);
        mockToken.approve(address(digitalWill), depositAmount);

        vm.expectRevert("You are not the grantor");
        digitalWill.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20RevertsWithInvalidTokenAddress() public {
        vm.startPrank(_grantor);
        vm.expectRevert("Invalid token address");
        digitalWill.depositERC20(address(0), 1000, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20RevertsWithZeroAmount() public {
        vm.startPrank(_grantor);
        vm.expectRevert("Amount must be greater than 0");
        digitalWill.depositERC20(address(mockToken), 0, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20RevertsWithInvalidBeneficiaryAddress() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        mockToken.approve(address(digitalWill), depositAmount);

        vm.expectRevert("Invalid beneficiary address");
        digitalWill.depositERC20(address(mockToken), depositAmount, address(0));
        vm.stopPrank();
    }

    function testDepositERC20RevertsWhenNotActive() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        mockToken.approve(address(digitalWill), depositAmount);

        // Set contract state to CLAIMABLE (1)
        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        vm.expectRevert("Contract must be active");
        digitalWill.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20Successfully() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        mockToken.approve(address(digitalWill), depositAmount);

        uint256 initialBalance = mockToken.balanceOf(address(digitalWill));

        digitalWill.depositERC20(address(mockToken), depositAmount, _beneficiary);

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
        assertEq(storedBeneficiary, _beneficiary, "Beneficiary should match");
        assertFalse(claimed, "Should not be claimed");

        // Check beneficiaryAssets mapping updated
        uint256 assetIndex = digitalWill.beneficiaryAssets(_beneficiary, 0);
        assertEq(assetIndex, 0, "Asset index should be 0 for first asset");
        vm.stopPrank();
    }

    function testDepositERC20EmitsEvent() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        mockToken.approve(address(digitalWill), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit AssetDeposited(_grantor, DigitalWill.AssetType.ERC20, address(mockToken), 0, depositAmount, _beneficiary);

        digitalWill.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC20MultipleDeposits() public {
        vm.startPrank(_grantor);

        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;
        uint256 amount3 = 3000 * 10 ** 18;

        mockToken.mint(_grantor, amount1 + amount2 + amount3);

        // First deposit
        mockToken.approve(address(digitalWill), amount1);
        digitalWill.depositERC20(address(mockToken), amount1, _beneficiary);

        // Second deposit
        mockToken.approve(address(digitalWill), amount2);
        digitalWill.depositERC20(address(mockToken), amount2, _beneficiary);

        // Third deposit
        mockToken.approve(address(digitalWill), amount3);
        digitalWill.depositERC20(address(mockToken), amount3, _beneficiary);

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
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 2), 2, "Third asset index");
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

        vm.startPrank(_grantor);

        uint256 amount1 = 1000 * 10 ** 18;
        uint256 amount2 = 2000 * 10 ** 18;

        // Mint and deposit from first token
        mockToken.mint(_grantor, amount1);
        mockToken.approve(address(digitalWill), amount1);
        digitalWill.depositERC20(address(mockToken), amount1, _beneficiary);

        // Mint and deposit from second token
        mockToken2.mint(_grantor, amount2);
        mockToken2.approve(address(digitalWill), amount2);
        digitalWill.depositERC20(address(mockToken2), amount2, _beneficiary);

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
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        // Don't approve the transfer

        vm.expectRevert();
        digitalWill.depositERC20(address(mockToken), depositAmount, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC20WithInsufficientBalanceReverts() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        // Mint less than deposit amount
        mockToken.mint(_grantor, depositAmount / 2);

        vm.startPrank(_grantor);
        mockToken.approve(address(digitalWill), depositAmount);

        vm.expectRevert();
        digitalWill.depositERC20(address(mockToken), depositAmount, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC20WithInsufficientAllowanceReverts() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, depositAmount);

        vm.startPrank(_grantor);
        // Approve less than deposit amount
        mockToken.approve(address(digitalWill), depositAmount / 2);

        vm.expectRevert();
        digitalWill.depositERC20(address(mockToken), depositAmount, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC20MixedWithOtherAssets() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        uint256 tokenAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, tokenAmount);

        // Deposit ETH
        digitalWill.depositETH{value: 1 ether}(_beneficiary);

        // Deposit ERC20
        mockToken.approve(address(digitalWill), tokenAmount);
        digitalWill.depositERC20(address(mockToken), tokenAmount, _beneficiary);

        // Deposit NFT
        uint256 tokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId);
        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);

        // Check all assets stored correctly
        (DigitalWill.AssetType type0,,,,,) = digitalWill.assets(0);
        (DigitalWill.AssetType type1,,,,,) = digitalWill.assets(1);
        (DigitalWill.AssetType type2,,,,,) = digitalWill.assets(2);

        assertEq(uint256(type0), uint256(DigitalWill.AssetType.ETH), "Asset 0 should be ETH");
        assertEq(uint256(type1), uint256(DigitalWill.AssetType.ERC20), "Asset 1 should be ERC20");
        assertEq(uint256(type2), uint256(DigitalWill.AssetType.ERC721), "Asset 2 should be ERC721");

        // Check beneficiaryAssets has all three
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 2), 2, "Third asset index");

        vm.stopPrank();
    }

    // depositERC721

    function testDepositERC721RevertsWhenNotGrantor() public {
        // Mint NFT to random user
        uint256 tokenId = mockNFT.mint(_randomUser);

        vm.startPrank(_randomUser);
        mockNFT.approve(address(digitalWill), tokenId);

        vm.expectRevert("You are not the grantor");
        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);
        vm.stopPrank();
    }

    function testDepositERC721RevertsWithInvalidTokenAddress() public {
        vm.startPrank(_grantor);

        vm.expectRevert("Invalid token address");
        digitalWill.depositERC721(address(0), 1, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721RevertsWithInvalidBeneficiaryAddress() public {
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        mockNFT.approve(address(digitalWill), tokenId);

        vm.expectRevert("Invalid beneficiary address");
        digitalWill.depositERC721(address(mockNFT), tokenId, address(0));

        vm.stopPrank();
    }

    function testDepositERC721RevertsWhenOwnerIsNotGrantor() public {
        uint256 tokenId = mockNFT.mint(_randomUser);

        vm.startPrank(_grantor);

        vm.expectRevert("Not the owner of NFT");
        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721RevertsWhenNotActive() public {
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        mockNFT.approve(address(digitalWill), tokenId);

        vm.store(
            address(digitalWill),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(1)) // ContractState.CLAIMABLE
        );

        vm.expectRevert("Contract must be active");
        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721Successfully() public {
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        mockNFT.approve(address(digitalWill), tokenId);

        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);

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
        assertEq(storedBeneficiary, _beneficiary, "Beneficiary should match");
        assertFalse(claimed, "Should not be claimed");

        // Check beneficiaryAssets mapping
        uint256 assetIndex = digitalWill.beneficiaryAssets(_beneficiary, 0);
        assertEq(assetIndex, 0, "Asset index should be 0");

        vm.stopPrank();
    }

    function testDepositERC721EmitsEvent() public {
        // Mint NFT to grantor
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        mockNFT.approve(address(digitalWill), tokenId);

        vm.expectEmit(true, true, true, true);
        emit AssetDeposited(_grantor, DigitalWill.AssetType.ERC721, address(mockNFT), tokenId, 1, _beneficiary);

        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721MultipleNFTsToSameBeneficiary() public {
        vm.startPrank(_grantor);

        // Mint and deposit multiple NFTs
        uint256 tokenId1 = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId1);
        digitalWill.depositERC721(address(mockNFT), tokenId1, _beneficiary);

        uint256 tokenId2 = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId2);
        digitalWill.depositERC721(address(mockNFT), tokenId2, _beneficiary);

        uint256 tokenId3 = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId3);
        digitalWill.depositERC721(address(mockNFT), tokenId3, _beneficiary);

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
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 2), 2, "Third asset index");

        vm.stopPrank();
    }

    function testDepositERC721MultipleBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        vm.startPrank(_grantor);

        // Mint and deposit NFTs to different beneficiaries
        uint256 tokenId1 = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId1);
        digitalWill.depositERC721(address(mockNFT), tokenId1, beneficiary1);

        uint256 tokenId2 = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId2);
        digitalWill.depositERC721(address(mockNFT), tokenId2, beneficiary2);

        uint256 tokenId3 = mockNFT.mint(_grantor);
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

        vm.startPrank(_grantor);

        // Mint and deposit from first collection
        uint256 tokenId1 = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId1);
        digitalWill.depositERC721(address(mockNFT), tokenId1, _beneficiary);

        // Mint and deposit from second collection
        uint256 tokenId2 = mockNFT2.mint(_grantor);
        mockNFT2.approve(address(digitalWill), tokenId2);
        digitalWill.depositERC721(address(mockNFT2), tokenId2, _beneficiary);

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
        uint256 tokenId = mockNFT.mint(_grantor);

        vm.startPrank(_grantor);
        // Don't approve the transfer

        vm.expectRevert();
        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721NonExistentTokenReverts() public {
        uint256 nonExistentTokenId = 999;

        vm.startPrank(_grantor);

        vm.expectRevert();
        digitalWill.depositERC721(address(mockNFT), nonExistentTokenId, _beneficiary);

        vm.stopPrank();
    }

    function testDepositERC721MixedWithETHDeposits() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit ETH
        digitalWill.depositETH{value: 1 ether}(_beneficiary);

        // Deposit NFT
        uint256 tokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId);
        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);

        // Deposit more ETH
        digitalWill.depositETH{value: 2 ether}(_beneficiary);

        // Check all assets stored correctly
        (DigitalWill.AssetType type0,,,,,) = digitalWill.assets(0);
        (DigitalWill.AssetType type1,,,,,) = digitalWill.assets(1);
        (DigitalWill.AssetType type2,,,,,) = digitalWill.assets(2);

        assertEq(uint256(type0), uint256(DigitalWill.AssetType.ETH), "Asset 0 should be ETH");
        assertEq(uint256(type1), uint256(DigitalWill.AssetType.ERC721), "Asset 1 should be ERC721");
        assertEq(uint256(type2), uint256(DigitalWill.AssetType.ETH), "Asset 2 should be ETH");

        // Check beneficiaryAssets has all three
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 0), 0, "First asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 1), 1, "Second asset index");
        assertEq(digitalWill.beneficiaryAssets(_beneficiary, 2), 2, "Third asset index");

        vm.stopPrank();
    }

    // claimSpecificAsset Tests

    // Event for testing claims
    event AssetClaimed(
        address indexed beneficiary,
        uint256 assetIndex,
        DigitalWill.AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    );

    event ContractCompleted(address indexed grantor);

    // Helper function to setup claimable state
    function _setupClaimableState() internal {
        // Warp time to make contract claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
    }

    // Test: Revert when contract not claimable (heartbeat not expired)
    function testClaimSpecificAssetRevertsWhenNotClaimable() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Try to claim before heartbeat expires
        vm.prank(_beneficiary);
        vm.expectRevert("Contract not yet claimable");
        digitalWill.claimSpecificAsset(0);
    }

    // Test: Revert when caller is not the beneficiary
    function testClaimSpecificAssetRevertsWhenNotBeneficiary() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Try to claim with wrong beneficiary
        vm.prank(_randomUser);
        vm.expectRevert("Not the beneficiary");
        digitalWill.claimSpecificAsset(0);
    }

    // Test: Revert when asset already claimed
    function testClaimSpecificAssetRevertsWhenAlreadyClaimed() public {
        // Setup: Deposit two ETH assets so contract doesn't complete after first claim
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim the first asset
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        // Try to claim the same asset again
        vm.prank(_beneficiary);
        vm.expectRevert("Asset already claimed");
        digitalWill.claimSpecificAsset(0);
    }

    // Test: Revert when asset index is invalid
    function testClaimSpecificAssetRevertsWithInvalidIndex() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Try to claim non-existent asset
        vm.prank(_beneficiary);
        vm.expectRevert();
        digitalWill.claimSpecificAsset(999);
    }

    // Test: Revert when contract already completed
    function testClaimSpecificAssetRevertsWhenContractCompleted() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim the asset (this completes the contract)
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        // Verify contract is completed
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.COMPLETED), "Contract should be completed"
        );

        // Try to claim again after completion
        vm.prank(_beneficiary);
        vm.expectRevert("Contract already completed");
        digitalWill.claimSpecificAsset(0);
    }

    // Test: Successfully claim ETH asset
    function testClaimSpecificAssetETHSuccessfully() public {
        uint256 depositAmount = 5 ether;

        // Setup: Deposit ETH
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: depositAmount}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Record initial balances
        uint256 beneficiaryBalanceBefore = _beneficiary.balance;
        uint256 contractBalanceBefore = address(digitalWill).balance;

        // Claim the asset
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        // Verify balances updated
        assertEq(_beneficiary.balance, beneficiaryBalanceBefore + depositAmount, "Beneficiary should receive ETH");
        assertEq(
            address(digitalWill).balance, contractBalanceBefore - depositAmount, "Contract balance should decrease"
        );

        // Verify asset marked as claimed
        (,,,,, bool claimed) = digitalWill.assets(0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    // Test: Successfully claim ERC20 asset
    function testClaimSpecificAssetERC20Successfully() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // Setup: Deposit ERC20
        mockToken.mint(_grantor, depositAmount);
        vm.startPrank(_grantor);
        mockToken.approve(address(digitalWill), depositAmount);
        digitalWill.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Record initial balances
        uint256 beneficiaryBalanceBefore = mockToken.balanceOf(_beneficiary);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(digitalWill));

        // Claim the asset
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        // Verify balances updated
        assertEq(
            mockToken.balanceOf(_beneficiary),
            beneficiaryBalanceBefore + depositAmount,
            "Beneficiary should receive tokens"
        );
        assertEq(
            mockToken.balanceOf(address(digitalWill)),
            contractBalanceBefore - depositAmount,
            "Contract balance should decrease"
        );

        // Verify asset marked as claimed
        (,,,,, bool claimed) = digitalWill.assets(0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    // Test: Successfully claim ERC721 asset
    function testClaimSpecificAssetERC721Successfully() public {
        // Setup: Deposit ERC721
        uint256 tokenId = mockNFT.mint(_grantor);
        vm.startPrank(_grantor);
        mockNFT.approve(address(digitalWill), tokenId);
        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim the asset
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        // Verify NFT transferred
        assertEq(mockNFT.ownerOf(tokenId), _beneficiary, "Beneficiary should own the NFT");

        // Verify asset marked as claimed
        (,,,,, bool claimed) = digitalWill.assets(0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    // Test: Emit AssetClaimed event
    function testClaimSpecificAssetEmitsEvent() public {
        uint256 depositAmount = 2 ether;

        // Setup: Deposit ETH
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: depositAmount}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit AssetClaimed(_beneficiary, 0, DigitalWill.AssetType.ETH, address(0), 0, depositAmount);

        // Claim the asset
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);
    }

    // Test: Contract completes when all assets claimed (single asset)
    function testClaimSpecificAssetCompletesContractSingleAsset() public {
        // Setup: Deposit one ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Verify state is CLAIMABLE before claim
        digitalWill.updateState();
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.CLAIMABLE), "State should be CLAIMABLE"
        );

        // Expect ContractCompleted event
        vm.expectEmit(true, true, true, true);
        emit ContractCompleted(_grantor);

        // Claim the asset
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        // Verify state changed to COMPLETED
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.COMPLETED), "State should be COMPLETED"
        );
    }

    // Test: Contract completes when all assets claimed (multiple assets)
    function testClaimSpecificAssetCompletesContractMultipleAssets() public {
        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        digitalWill.depositETH{value: 1 ether}(_beneficiary);

        mockToken.mint(_grantor, 1000 * 10 ** 18);
        mockToken.approve(address(digitalWill), 1000 * 10 ** 18);
        digitalWill.depositERC20(address(mockToken), 1000 * 10 ** 18, _beneficiary);

        uint256 tokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId);
        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        vm.startPrank(_beneficiary);

        // Claim first two assets - should not complete
        digitalWill.claimSpecificAsset(0);
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.CLAIMABLE),
            "State should still be CLAIMABLE after first claim"
        );

        digitalWill.claimSpecificAsset(1);
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.CLAIMABLE),
            "State should still be CLAIMABLE after second claim"
        );

        // Claim last asset - should complete
        digitalWill.claimSpecificAsset(2);
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.COMPLETED),
            "State should be COMPLETED after all claims"
        );

        vm.stopPrank();
    }

    // Test: Multiple beneficiaries claiming their respective assets
    function testClaimSpecificAssetMultipleBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        // Setup: Deposit assets for different beneficiaries
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        digitalWill.depositETH{value: 1 ether}(beneficiary1);
        digitalWill.depositETH{value: 2 ether}(beneficiary2);
        digitalWill.depositETH{value: 3 ether}(beneficiary3);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Each beneficiary claims their asset
        vm.prank(beneficiary1);
        digitalWill.claimSpecificAsset(0);
        assertEq(beneficiary1.balance, 1 ether, "Beneficiary1 should receive 1 ETH");

        vm.prank(beneficiary2);
        digitalWill.claimSpecificAsset(1);
        assertEq(beneficiary2.balance, 2 ether, "Beneficiary2 should receive 2 ETH");

        vm.prank(beneficiary3);
        digitalWill.claimSpecificAsset(2);
        assertEq(beneficiary3.balance, 3 ether, "Beneficiary3 should receive 3 ETH");

        // Verify contract completed
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.COMPLETED), "Contract should be completed"
        );
    }

    // Test: Beneficiary cannot claim another beneficiary's asset
    function testClaimSpecificAssetCannotClaimOtherBeneficiaryAsset() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");

        // Setup: Deposit assets for different beneficiaries
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(beneficiary1);
        digitalWill.depositETH{value: 2 ether}(beneficiary2);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Beneficiary1 tries to claim beneficiary2's asset
        vm.prank(beneficiary1);
        vm.expectRevert("Not the beneficiary");
        digitalWill.claimSpecificAsset(1);

        // Beneficiary2 tries to claim beneficiary1's asset
        vm.prank(beneficiary2);
        vm.expectRevert("Not the beneficiary");
        digitalWill.claimSpecificAsset(0);
    }

    // Test: Claiming assets out of order
    function testClaimSpecificAssetOutOfOrder() public {
        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        digitalWill.depositETH{value: 2 ether}(_beneficiary);
        digitalWill.depositETH{value: 3 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        uint256 balanceBefore = _beneficiary.balance;

        vm.startPrank(_beneficiary);

        // Claim in reverse order
        digitalWill.claimSpecificAsset(2);
        assertEq(_beneficiary.balance, balanceBefore + 3 ether, "Should receive 3 ETH");

        digitalWill.claimSpecificAsset(0);
        assertEq(_beneficiary.balance, balanceBefore + 4 ether, "Should receive additional 1 ETH");

        digitalWill.claimSpecificAsset(1);
        assertEq(_beneficiary.balance, balanceBefore + 6 ether, "Should receive additional 2 ETH");

        vm.stopPrank();

        // Verify all claimed
        (,,,,, bool claimed0) = digitalWill.assets(0);
        (,,,,, bool claimed1) = digitalWill.assets(1);
        (,,,,, bool claimed2) = digitalWill.assets(2);
        assertTrue(claimed0 && claimed1 && claimed2, "All assets should be claimed");
    }

    // Test: Partial claims (some assets claimed, some not)
    function testClaimSpecificAssetPartialClaims() public {
        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        digitalWill.depositETH{value: 2 ether}(_beneficiary);
        digitalWill.depositETH{value: 3 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim only first asset
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        // Verify first asset claimed, others not
        (,,,,, bool claimed0) = digitalWill.assets(0);
        (,,,,, bool claimed1) = digitalWill.assets(1);
        (,,,,, bool claimed2) = digitalWill.assets(2);

        assertTrue(claimed0, "Asset 0 should be claimed");
        assertFalse(claimed1, "Asset 1 should not be claimed");
        assertFalse(claimed2, "Asset 2 should not be claimed");

        // Contract should still be CLAIMABLE
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.CLAIMABLE),
            "Contract should still be CLAIMABLE"
        );
    }

    // Test: UpdateState is called automatically
    function testClaimSpecificAssetAutomaticallyUpdatesState() public {
        // Setup: Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Warp time but don't manually update state
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Verify state is still ACTIVE (not yet updated)
        assertEq(
            uint256(digitalWill.state()),
            uint256(DigitalWill.ContractState.ACTIVE),
            "State should still be ACTIVE before claim"
        );

        // Claim should automatically update state to CLAIMABLE then claim
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        // Asset should be successfully claimed
        (,,,,, bool claimed) = digitalWill.assets(0);
        assertTrue(claimed, "Asset should be claimed");
    }

    // Test: Mixed asset types claimed by single beneficiary
    function testClaimSpecificAssetMixedAssetTypes() public {
        uint256 ethAmount = 2 ether;
        uint256 tokenAmount = 500 * 10 ** 18;
        uint256 nftTokenId;

        // Setup: Deposit mixed assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        digitalWill.depositETH{value: ethAmount}(_beneficiary);

        mockToken.mint(_grantor, tokenAmount);
        mockToken.approve(address(digitalWill), tokenAmount);
        digitalWill.depositERC20(address(mockToken), tokenAmount, _beneficiary);

        nftTokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), nftTokenId);
        digitalWill.depositERC721(address(mockNFT), nftTokenId, _beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim all assets
        vm.startPrank(_beneficiary);

        digitalWill.claimSpecificAsset(0); // ETH
        digitalWill.claimSpecificAsset(1); // ERC20
        digitalWill.claimSpecificAsset(2); // ERC721

        vm.stopPrank();

        // Verify all assets transferred correctly
        assertEq(_beneficiary.balance, ethAmount, "Should receive ETH");
        assertEq(mockToken.balanceOf(_beneficiary), tokenAmount, "Should receive tokens");
        assertEq(mockNFT.ownerOf(nftTokenId), _beneficiary, "Should own NFT");

        // Verify contract completed
        assertEq(
            uint256(digitalWill.state()), uint256(DigitalWill.ContractState.COMPLETED), "Contract should be completed"
        );
    }

    // Test: Beneficiary with multiple assets of same type
    function testClaimSpecificAssetBeneficiaryWithMultipleAssetsOfSameType() public {
        // Setup: Deposit multiple ETH assets to same beneficiary
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        digitalWill.depositETH{value: 2 ether}(_beneficiary);
        digitalWill.depositETH{value: 3 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        uint256 balanceBefore = _beneficiary.balance;

        // Claim each asset individually
        vm.startPrank(_beneficiary);
        digitalWill.claimSpecificAsset(0);
        digitalWill.claimSpecificAsset(1);
        digitalWill.claimSpecificAsset(2);
        vm.stopPrank();

        // Verify total received
        assertEq(_beneficiary.balance, balanceBefore + 6 ether, "Should receive total of 6 ETH");
    }

    // Test: Contract becomes claimable at exact boundary
    function testClaimSpecificAssetAtExactHeartbeatBoundary() public {
        // Setup: Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Warp to exact boundary
        vm.warp(block.timestamp + 30 days);

        // Should be able to claim
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        (,,,,, bool claimed) = digitalWill.assets(0);
        assertTrue(claimed, "Asset should be claimed at exact boundary");
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
        vm.prank(_grantor);
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
        vm.prank(_randomUser);
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
        vm.prank(_grantor);
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

        vm.prank(_grantor);
        digitalWill.checkIn();

        assertEq(digitalWill.lastCheckIn(), block.timestamp, "lastCheckIn should match current timestamp");
    }

    // Fuzz Tests - depositETH

    function testFuzzDepositETHAmount(uint256 amount) public {
        // Bound amount between 0.001 ether and 1000 ether
        amount = bound(amount, 0.001 ether, 1000 ether);

        vm.startPrank(_grantor);
        vm.deal(_grantor, amount);

        digitalWill.depositETH{value: amount}(_beneficiary);

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

        vm.startPrank(_grantor);

        // Mint with specific token ID
        mockNFT.mintWithId(_grantor, tokenId);
        mockNFT.approve(address(digitalWill), tokenId);

        digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);

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

        vm.startPrank(_grantor);

        // Mint and deposit to first beneficiary
        uint256 tokenId1 = mockNFT.mint(_grantor);
        mockNFT.approve(address(digitalWill), tokenId1);
        digitalWill.depositERC721(address(mockNFT), tokenId1, beneficiary1);

        // Mint and deposit to second beneficiary
        uint256 tokenId2 = mockNFT.mint(_grantor);
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

        vm.startPrank(_grantor);

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = mockNFT.mint(_grantor);
            mockNFT.approve(address(digitalWill), tokenId);
            digitalWill.depositERC721(address(mockNFT), tokenId, _beneficiary);
        }

        // Verify all tokens deposited
        for (uint256 i = 0; i < numTokens; i++) {
            assertEq(mockNFT.ownerOf(i), address(digitalWill), "Contract should own all NFTs");
            uint256 assetIndex = digitalWill.beneficiaryAssets(_beneficiary, i);
            assertEq(assetIndex, i, "Asset indices should match");
        }

        vm.stopPrank();
    }

    // Fuzz Tests - depositERC20

    function testFuzzDepositERC20Amount(uint256 amount) public {
        // Bound amount between 1 and 1 billion tokens (with 18 decimals)
        amount = bound(amount, 1, 1_000_000_000 * 10 ** 18);

        mockToken.mint(_grantor, amount);

        vm.startPrank(_grantor);
        mockToken.approve(address(digitalWill), amount);

        digitalWill.depositERC20(address(mockToken), amount, _beneficiary);

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

        mockToken.mint(_grantor, amount1 + amount2);

        vm.startPrank(_grantor);

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

        mockToken.mint(_grantor, totalAmount);

        vm.startPrank(_grantor);

        for (uint256 i = 0; i < numDeposits; i++) {
            mockToken.approve(address(digitalWill), depositAmount);
            digitalWill.depositERC20(address(mockToken), depositAmount, _beneficiary);
        }

        // Verify all deposits
        assertEq(mockToken.balanceOf(address(digitalWill)), totalAmount, "Contract should have all deposits");

        for (uint256 i = 0; i < numDeposits; i++) {
            (,,, uint256 storedAmount,,) = digitalWill.assets(i);
            assertEq(storedAmount, depositAmount, "Each deposit amount should match");
            uint256 assetIndex = digitalWill.beneficiaryAssets(_beneficiary, i);
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

    // ===========================================
    // FUZZ TESTS - claimSpecificAsset
    // ===========================================

    // Fuzz Test: Claim with various asset indices
    function testFuzzClaimSpecificAssetWithVariousIndices(uint256 numAssets) public {
        // Bound to reasonable number (1-20)
        numAssets = bound(numAssets, 1, 20);

        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, numAssets * 1 ether);

        for (uint256 i = 0; i < numAssets; i++) {
            digitalWill.depositETH{value: 1 ether}(_beneficiary);
        }
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim all assets
        vm.startPrank(_beneficiary);
        for (uint256 i = 0; i < numAssets; i++) {
            digitalWill.claimSpecificAsset(i);
        }
        vm.stopPrank();

        // Verify all assets claimed
        for (uint256 i = 0; i < numAssets; i++) {
            (,,,,, bool claimed) = digitalWill.assets(i);
            assertTrue(claimed, "All assets should be claimed");
        }

        // Verify beneficiary received all ETH
        assertEq(_beneficiary.balance, numAssets * 1 ether, "Beneficiary should receive all ETH");
    }

    // Fuzz Test: Claim with various time offsets
    function testFuzzClaimSpecificAssetWithVariousTimeOffsets(uint256 timeOffset) public {
        // Bound to reasonable range (30 days to 365 days)
        timeOffset = bound(timeOffset, 30 days, 365 days);

        // Setup: Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        digitalWill.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Warp time
        vm.warp(block.timestamp + timeOffset);

        // Should be able to claim
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        (,,,,, bool claimed) = digitalWill.assets(0);
        assertTrue(claimed, "Asset should be claimable after time offset");
    }

    // Fuzz Test: Claim ERC20 with various amounts
    function testFuzzClaimSpecificAssetERC20WithVariousAmounts(uint256 amount) public {
        // Bound to reasonable range
        amount = bound(amount, 1, 1_000_000_000 * 10 ** 18);

        // Setup: Deposit ERC20
        mockToken.mint(_grantor, amount);
        vm.startPrank(_grantor);
        mockToken.approve(address(digitalWill), amount);
        digitalWill.depositERC20(address(mockToken), amount, _beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim
        vm.prank(_beneficiary);
        digitalWill.claimSpecificAsset(0);

        // Verify
        assertEq(mockToken.balanceOf(_beneficiary), amount, "Beneficiary should receive correct amount");
    }
}
