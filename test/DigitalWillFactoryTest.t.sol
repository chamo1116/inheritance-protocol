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

contract DigitalWillFactoryTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;

    address public _grantor;
    address public _randomUser;
    address public _beneficiary;

    // Events to test
    event WillCreated(address indexed grantor, uint256 heartbeatInterval);

    event CheckIn(address indexed grantor, uint256 timestamp);

    event AssetDeposited(
        address indexed grantor,
        DigitalWillFactory.AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        address indexed beneficiary
    );

    event HeartbeatExtended(address indexed grantor, uint256 newInterval);

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

    // Create will tests
    function testCreateWill() public {
        address newGrantor = makeAddr("newGrantor");
        vm.prank(newGrantor);
        factory.createWill(30 days);

        (uint256 lastCheckIn, uint256 heartbeatInterval, DigitalWillFactory.ContractState state, uint256 assetCount) =
            factory.getWillInfo(newGrantor);

        assertEq(lastCheckIn, block.timestamp, "Last check-in should be set correctly");
        assertEq(heartbeatInterval, 30 days, "Heartbeat interval should be set correctly");
        assertEq(uint256(state), uint256(DigitalWillFactory.ContractState.ACTIVE), "State should be ACTIVE");
        assertEq(assetCount, 0, "Asset count should be 0");
    }

    function testCreateWillRevertsWithZeroHeartbeatInterval() public {
        address newGrantor = makeAddr("newGrantor");
        vm.prank(newGrantor);
        vm.expectRevert("Heartbeat interval must be greater than 0");
        factory.createWill(0);
    }

    function testCreateWillRevertsIfWillAlreadyExists() public {
        vm.prank(_grantor);
        vm.expectRevert("Will already exists");
        factory.createWill(30 days);
    }

    function testCreateWillEmitsEvent() public {
        address newGrantor = makeAddr("newGrantor");

        vm.expectEmit(true, true, true, true);
        emit WillCreated(newGrantor, 30 days);

        vm.prank(newGrantor);
        factory.createWill(30 days);
    }

    // Check in

    function testCheckInWithNotGrantor() public {
        vm.prank(_randomUser);
        vm.expectRevert("Will does not exist");
        factory.checkIn();
    }

    function testCheckInRevertsWhenNotActive() public {
        // Make the will claimable by warping time
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);

        vm.expectRevert("Will must be active");
        vm.prank(_grantor);
        factory.checkIn();
    }

    function testCheckInSuccessfully() public {
        uint256 checkInTime = block.timestamp;

        vm.prank(_grantor);
        factory.checkIn();

        (uint256 lastCheckIn,,,) = factory.getWillInfo(_grantor);
        assertEq(lastCheckIn, checkInTime, "lastCheckIn should be updated to current timestamp");
    }

    function testCheckInEmitsEvent() public {
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit CheckIn(_grantor, expectedTimestamp);

        vm.prank(_grantor);
        factory.checkIn();
    }

    function testCheckInMultipleCheckIns() public {
        // First check-in
        vm.prank(_grantor);
        factory.checkIn();
        (uint256 firstCheckIn,,,) = factory.getWillInfo(_grantor);

        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);

        // Second check-in
        vm.prank(_grantor);
        factory.checkIn();
        (uint256 secondCheckIn,,,) = factory.getWillInfo(_grantor);

        assertGt(secondCheckIn, firstCheckIn, "Second check-in should have later timestamp");
        assertEq(secondCheckIn, block.timestamp, "Second check-in should match current block timestamp");
    }

    // Deposit ETH
    function testDepositETHRevertsWhenNotGrantor() public {
        vm.startPrank(_randomUser);
        vm.deal(_randomUser, 10 ether);
        vm.expectRevert("Will does not exist");
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroValue() public {
        vm.startPrank(_grantor);
        vm.expectRevert("Must send ETH");
        factory.depositETH{value: 0}(_beneficiary);
        vm.stopPrank();
    }

    function testDepositETHRevertsWithZeroAddressInBeneficiary() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        vm.expectRevert("Invalid beneficiary address");

        factory.depositETH{value: 1 ether}(address(0));
        vm.stopPrank();
    }

    function testDepositETHRevertsWhenNotActive() public {
        // Make the will claimable by warping time
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);

        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        vm.expectRevert("Will must be active");
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();
    }

    function testDepositETHSuccessfully() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        uint256 depositAmount = 5 ether;

        uint256 initialBalance = address(factory).balance;

        factory.depositETH{value: depositAmount}(_beneficiary);

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
        factory.depositETH{value: 1 ether}(_beneficiary);

        // Second deposit
        factory.depositETH{value: 2 ether}(_beneficiary);

        // Third deposit
        factory.depositETH{value: 3 ether}(_beneficiary);

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

        factory.depositETH{value: 1 ether}(beneficiary1);

        factory.depositETH{value: 2 ether}(beneficiary2);

        factory.depositETH{value: 3 ether}(beneficiary3);

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

        vm.expectRevert("Use depositETH function");
        (bool success,) = address(factory).call{value: 1 ether}("");
        success; // Silence unused variable warning

        vm.stopPrank();
    }

    // depositERC20

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

    // depositERC721

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

    // claimSpecificAsset Tests

    // Test: Revert when contract not claimable (heartbeat not expired)
    function testClaimSpecificAssetRevertsWhenNotClaimable() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Try to claim before heartbeat expires
        vm.prank(_beneficiary);
        vm.expectRevert("Will not yet claimable");
        factory.claimAsset(_grantor, 0);
    }

    // Test: Revert when caller is not the beneficiary
    function testClaimSpecificAssetRevertsWhenNotBeneficiary() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Try to claim with wrong beneficiary
        vm.prank(_randomUser);
        vm.expectRevert("Not the beneficiary");
        factory.claimAsset(_grantor, 0);
    }

    // Test: Revert when asset already claimed
    function testClaimSpecificAssetRevertsWhenAlreadyClaimed() public {
        // Setup: Deposit two ETH assets so contract doesn't complete after first claim
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim the first asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Try to claim the same asset again
        vm.prank(_beneficiary);
        vm.expectRevert("Asset already claimed");
        factory.claimAsset(_grantor, 0);
    }

    // Test: Revert when asset index is invalid
    function testClaimSpecificAssetRevertsWithInvalidIndex() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Try to claim non-existent asset
        vm.prank(_beneficiary);
        vm.expectRevert();
        factory.claimAsset(_grantor, 999);
    }

    // Test: Revert when contract already completed
    function testClaimSpecificAssetRevertsWhenContractCompleted() public {
        // Setup: Deposit an ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

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

    // Test: Successfully claim ETH asset
    function testClaimSpecificAssetETHSuccessfully() public {
        uint256 depositAmount = 5 ether;

        // Setup: Deposit ETH
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: depositAmount}(_beneficiary);
        vm.stopPrank();

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

    // Test: Successfully claim ERC20 asset
    function testClaimSpecificAssetERC20Successfully() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // Setup: Deposit ERC20
        mockToken.mint(_grantor, depositAmount);
        vm.startPrank(_grantor);
        mockToken.approve(address(factory), depositAmount);
        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();

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

    // Test: Successfully claim ERC721 asset
    function testClaimSpecificAssetERC721Successfully() public {
        // Setup: Deposit ERC721
        uint256 tokenId = mockNFT.mint(_grantor);
        vm.startPrank(_grantor);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Claim the asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify NFT transferred
        assertEq(mockNFT.ownerOf(tokenId), _beneficiary, "Beneficiary should own the NFT");

        // Verify asset marked as claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    // Test: Emit AssetClaimed event
    function testClaimSpecificAssetEmitsEvent() public {
        uint256 depositAmount = 2 ether;

        // Setup: Deposit ETH
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: depositAmount}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit AssetClaimed(_grantor, _beneficiary, 0, DigitalWillFactory.AssetType.ETH, address(0), 0, depositAmount);

        // Claim the asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);
    }

    // Test: Contract completes when all assets claimed (single asset)
    function testClaimSpecificAssetCompletesContractSingleAsset() public {
        // Setup: Deposit one ETH asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

        // Verify state is CLAIMABLE before claim
        factory.updateState(_grantor);
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.CLAIMABLE), "State should be CLAIMABLE");

        // Expect ContractCompleted event
        vm.expectEmit(true, true, true, true);
        emit WillCompleted(_grantor);

        // Claim the asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify state changed to COMPLETED
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.COMPLETED), "State should be COMPLETED");
    }

    // Test: Contract completes when all assets claimed (multiple assets)
    function testClaimSpecificAssetCompletesContractMultipleAssets() public {
        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: 1 ether}(_beneficiary);

        mockToken.mint(_grantor, 1000 * 10 ** 18);
        mockToken.approve(address(factory), 1000 * 10 ** 18);
        factory.depositERC20(address(mockToken), 1000 * 10 ** 18, _beneficiary);

        uint256 tokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);
        vm.stopPrank();

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

    // Test: Multiple beneficiaries claiming their respective assets
    function testClaimSpecificAssetMultipleBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");
        address beneficiary3 = makeAddr("beneficiary3");

        // Setup: Deposit assets for different beneficiaries
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: 1 ether}(beneficiary1);
        factory.depositETH{value: 2 ether}(beneficiary2);
        factory.depositETH{value: 3 ether}(beneficiary3);
        vm.stopPrank();

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

    // Test: Beneficiary cannot claim another beneficiary's asset
    function testClaimSpecificAssetCannotClaimOtherBeneficiaryAsset() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");

        // Setup: Deposit assets for different beneficiaries
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(beneficiary1);
        factory.depositETH{value: 2 ether}(beneficiary2);
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

    // Test: Claiming assets out of order
    function testClaimSpecificAssetOutOfOrder() public {
        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);
        vm.stopPrank();

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

    // Test: Partial claims (some assets claimed, some not)
    function testClaimSpecificAssetPartialClaims() public {
        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);
        vm.stopPrank();

        // Make contract claimable
        _setupClaimableState();

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

    // Test: UpdateState is called automatically
    function testClaimSpecificAssetAutomaticallyUpdatesState() public {
        // Setup: Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

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

    // Test: Mixed asset types claimed by single beneficiary
    function testClaimSpecificAssetMixedAssetTypes() public {
        uint256 ethAmount = 2 ether;
        uint256 tokenAmount = 500 * 10 ** 18;
        uint256 nftTokenId;

        // Setup: Deposit mixed assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: ethAmount}(_beneficiary);

        mockToken.mint(_grantor, tokenAmount);
        mockToken.approve(address(factory), tokenAmount);
        factory.depositERC20(address(mockToken), tokenAmount, _beneficiary);

        nftTokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), nftTokenId);
        factory.depositERC721(address(mockNFT), nftTokenId, _beneficiary);
        vm.stopPrank();

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
        assertEq(mockNFT.ownerOf(nftTokenId), _beneficiary, "Should own NFT");

        // Verify contract completed
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState), uint256(DigitalWillFactory.ContractState.COMPLETED), "Contract should be completed"
        );
    }

    // Test: Beneficiary with multiple assets of same type
    function testClaimSpecificAssetBeneficiaryWithMultipleAssetsOfSameType() public {
        // Setup: Deposit multiple ETH assets to same beneficiary
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);
        vm.stopPrank();

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

    // Test: Contract becomes claimable at exact boundary
    function testClaimSpecificAssetAtExactHeartbeatBoundary() public {
        // Setup: Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Warp to exact boundary
        vm.warp(block.timestamp + 30 days);

        // Should be able to claim
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be claimed at exact boundary");
    }

    // isClaimable Tests

    function testIsClaimableReturnsTrueWhenStateIsClaimable() public {
        // Make the will claimable by warping time
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);

        bool result = factory.isClaimable(_grantor);
        assertTrue(result, "Should return true when state is CLAIMABLE");
    }

    function testIsClaimableReturnsFalseWhenActiveAndHeartbeatNotExpired() public view {
        // State is ACTIVE (default), and we're still within heartbeat interval
        bool result = factory.isClaimable(_grantor);
        assertFalse(result, "Should return false when ACTIVE and heartbeat not expired");
    }

    function testIsClaimableReturnsTrueWhenActiveAndHeartbeatExpired() public {
        // State is ACTIVE, advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        bool result = factory.isClaimable(_grantor);
        assertTrue(result, "Should return true when ACTIVE and heartbeat expired");
    }

    function testIsClaimableAtExactHeartbeatBoundary() public {
        // Test at exact boundary (lastCheckIn + heartbeatInterval)
        vm.warp(block.timestamp + 30 days);

        bool result = factory.isClaimable(_grantor);
        assertTrue(result, "Should return true at exact heartbeat boundary");
    }

    function testIsClaimableReturnsFalseWhenCompleted() public {
        // Set state to COMPLETED
        vm.store(
            address(factory),
            bytes32(uint256(2)), // slot 2 for state
            bytes32(uint256(2)) // ContractState.COMPLETED
        );

        bool result = factory.isClaimable(_grantor);
        assertFalse(result, "Should return false when state is COMPLETED");
    }

    function testIsClaimableAfterCheckIn() public {
        // First check that it's not claimable
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable initially");

        // Warp time to make it claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after heartbeat expired");

        // Check in to reset timer
        vm.prank(_grantor);
        factory.checkIn();

        // Should no longer be claimable
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable after check-in");
    }

    function testIsClaimableJustBeforeHeartbeatExpires() public {
        // Advance time to 1 second before expiration
        vm.warp(block.timestamp + 30 days - 1 seconds);

        bool result = factory.isClaimable(_grantor);
        assertFalse(result, "Should return false just before heartbeat expires");
    }

    // updateState Tests

    function testUpdateStateChangesActiveToClaimableWhenHeartbeatExpired() public {
        // Verify initial state is ACTIVE
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.ACTIVE), "Initial state should be ACTIVE");

        // Advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Call updateState
        factory.updateState(_grantor);

        // Verify state changed to CLAIMABLE
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.CLAIMABLE),
            "State should be CLAIMABLE after update"
        );
    }

    function testUpdateStateDoesNotChangeStateWhenHeartbeatNotExpired() public {
        // Verify initial state is ACTIVE
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.ACTIVE), "Initial state should be ACTIVE");

        // Call updateState (heartbeat not expired)
        factory.updateState(_grantor);

        // Verify state remains ACTIVE
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.ACTIVE), "State should remain ACTIVE");
    }

    function testUpdateStateDoesNotChangeWhenAlreadyClaimable() public {
        // Advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // First call to updateState
        factory.updateState(_grantor);
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.CLAIMABLE), "State should be CLAIMABLE");

        // Second call to updateState
        factory.updateState(_grantor);

        // Verify state remains CLAIMABLE
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState), uint256(DigitalWillFactory.ContractState.CLAIMABLE), "State should remain CLAIMABLE"
        );
    }

    function testUpdateStateDoesNotChangeWhenCompleted() public {
        // Setup: Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);

        // Claim the asset to complete the will
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify state is COMPLETED
        (,, DigitalWillFactory.ContractState willState1,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState1),
            uint256(DigitalWillFactory.ContractState.COMPLETED),
            "State should be COMPLETED after claiming all assets"
        );

        // Advance time beyond heartbeat interval again
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Call updateState
        factory.updateState(_grantor);

        // Verify state remains COMPLETED
        (,, DigitalWillFactory.ContractState willState2,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState2), uint256(DigitalWillFactory.ContractState.COMPLETED), "State should remain COMPLETED"
        );
    }

    function testUpdateStateCanBeCalledByAnyone() public {
        // Advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Call updateState as random user
        vm.prank(_randomUser);
        factory.updateState(_grantor);

        // Verify state changed to CLAIMABLE
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.CLAIMABLE), "State should be CLAIMABLE");
    }

    function testUpdateStateAtExactHeartbeatBoundary() public {
        // Advance time to exactly heartbeatInterval
        vm.warp(block.timestamp + 30 days);

        // Call updateState
        factory.updateState(_grantor);

        // Verify state changed to CLAIMABLE
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.CLAIMABLE),
            "State should be CLAIMABLE at exact boundary"
        );
    }

    function testUpdateStateMultipleCallsAfterExpiration() public {
        // Advance time beyond heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // First call
        factory.updateState(_grantor);
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.CLAIMABLE),
            "State should be CLAIMABLE after first call"
        );

        // Advance time further
        vm.warp(block.timestamp + 10 days);

        // Second call
        factory.updateState(_grantor);
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.CLAIMABLE),
            "State should remain CLAIMABLE after second call"
        );
    }

    function testUpdateStateAfterMultipleCheckIns() public {
        // First check-in at deployment
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.ACTIVE), "Should start ACTIVE");

        // Advance time but not beyond heartbeat
        vm.warp(block.timestamp + 15 days);

        // Check in again
        vm.prank(_grantor);
        factory.checkIn();

        // Update state should not change anything
        factory.updateState(_grantor);
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState), uint256(DigitalWillFactory.ContractState.ACTIVE), "Should remain ACTIVE after check-in"
        );

        // Now advance beyond new heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Update state should now change to CLAIMABLE
        factory.updateState(_grantor);
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(
            uint256(willState),
            uint256(DigitalWillFactory.ContractState.CLAIMABLE),
            "Should be CLAIMABLE after expiration"
        );
    }

    // extendHeartbeat Tests

    function testExtendHeartbeatRevertsWhenNotGrantor() public {
        uint256 newInterval = 60 days;

        vm.prank(_randomUser);
        vm.expectRevert("Will does not exist");
        factory.extendHeartbeat(newInterval);
    }

    function testExtendHeartbeatRevertsWhenNotActive() public {
        uint256 newInterval = 60 days;

        // Make the will claimable by warping time
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);

        vm.prank(_grantor);
        vm.expectRevert("Will must be active");
        factory.extendHeartbeat(newInterval);
    }

    function testExtendHeartbeatRevertsWhenCompleted() public {
        uint256 newInterval = 60 days;

        // Setup: Deposit an asset and complete the will
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make claimable and claim to complete
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        vm.prank(_grantor);
        vm.expectRevert("Will must be active");
        factory.extendHeartbeat(newInterval);
    }

    function testExtendHeartbeatRevertsWhenNewIntervalNotLonger() public {
        uint256 shorterInterval = 15 days;

        vm.prank(_grantor);
        vm.expectRevert("New interval must be longer");
        factory.extendHeartbeat(shorterInterval);
    }

    function testExtendHeartbeatRevertsWhenNewIntervalEquals() public {
        uint256 sameInterval = 30 days; // Same as initial

        vm.prank(_grantor);
        vm.expectRevert("New interval must be longer");
        factory.extendHeartbeat(sameInterval);
    }

    function testExtendHeartbeatSuccessfully() public {
        uint256 newInterval = 60 days;
        (, uint256 initialInterval,,) = factory.getWillInfo(_grantor);

        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        (, uint256 updatedInterval,,) = factory.getWillInfo(_grantor);
        assertEq(updatedInterval, newInterval, "Heartbeat interval should be updated");
        assertGt(updatedInterval, initialInterval, "New interval should be longer than initial");
    }

    function testExtendHeartbeatEmitsEvent() public {
        uint256 newInterval = 60 days;

        vm.expectEmit(true, true, true, true);
        emit HeartbeatExtended(_grantor, newInterval);

        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);
    }

    function testExtendHeartbeatMultipleTimes() public {
        uint256 firstExtension = 60 days;
        uint256 secondExtension = 90 days;
        uint256 thirdExtension = 120 days;

        vm.startPrank(_grantor);

        // First extension
        factory.extendHeartbeat(firstExtension);
        (, uint256 hbInterval1,,) = factory.getWillInfo(_grantor);
        assertEq(hbInterval1, firstExtension, "First extension should be set");

        // Second extension
        factory.extendHeartbeat(secondExtension);
        (, uint256 hbInterval2,,) = factory.getWillInfo(_grantor);
        assertEq(hbInterval2, secondExtension, "Second extension should be set");

        // Third extension
        factory.extendHeartbeat(thirdExtension);
        (, uint256 hbInterval3,,) = factory.getWillInfo(_grantor);
        assertEq(hbInterval3, thirdExtension, "Third extension should be set");

        vm.stopPrank();
    }

    function testExtendHeartbeatDoesNotChangeLastCheckIn() public {
        uint256 newInterval = 60 days;
        (uint256 lastCheckInVal0,,,) = factory.getWillInfo(_grantor);
        uint256 lastCheckInBefore = lastCheckInVal0;

        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        (uint256 lastCheckInVal1,,,) = factory.getWillInfo(_grantor);
        uint256 lastCheckInAfter = lastCheckInVal1;
        assertEq(lastCheckInAfter, lastCheckInBefore, "lastCheckIn should not change when extending heartbeat");
    }

    function testExtendHeartbeatDoesNotChangeState() public {
        uint256 newInterval = 60 days;

        // Verify initial state is ACTIVE
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.ACTIVE), "Initial state should be ACTIVE");

        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        // Verify state is still ACTIVE
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.ACTIVE), "State should remain ACTIVE");
    }

    function testExtendHeartbeatAndVerifyNewIntervalUsed() public {
        uint256 newInterval = 60 days;

        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        // Warp time to just before new interval expires
        vm.warp(block.timestamp + newInterval - 1 seconds);

        // Should not be claimable yet
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable before new interval expires");

        // Warp to exactly new interval
        vm.warp(block.timestamp + 1 seconds);

        // Should now be claimable
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval expires");
    }

    function testExtendHeartbeatAfterPartialInterval() public {
        uint256 newInterval = 60 days;

        // Warp halfway through initial interval
        vm.warp(block.timestamp + 15 days);

        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        // Warp to original interval (30 days from start)
        vm.warp(block.timestamp + 15 days);

        // Should not be claimable yet (new interval is 60 days from original checkIn)
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable at old interval");

        // Warp to new interval (60 days from start)
        vm.warp(block.timestamp + 30 days);

        // Should now be claimable
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval");
    }

    function testExtendHeartbeatWithCheckInBetween() public {
        uint256 newInterval = 60 days;

        // First check in (implicit at deployment)
        (uint256 lastCheckInVal2,,,) = factory.getWillInfo(_grantor);
        uint256 firstCheckIn = lastCheckInVal2;

        // Warp some time
        vm.warp(block.timestamp + 10 days);

        // Check in again
        vm.prank(_grantor);
        factory.checkIn();
        (uint256 lastCheckInVal3,,,) = factory.getWillInfo(_grantor);
        uint256 secondCheckIn = lastCheckInVal3;

        assertGt(secondCheckIn, firstCheckIn, "Second check-in should be later");

        // Extend heartbeat
        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        // Verify new interval applies from last check-in
        vm.warp(secondCheckIn + newInterval);
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval from last check-in");
    }

    function testExtendHeartbeatRevertsAfterHeartbeatExpires() public {
        uint256 newInterval = 60 days;

        // Warp time beyond initial heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Update state to CLAIMABLE
        factory.updateState(_grantor);

        // Verify state is CLAIMABLE
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.CLAIMABLE), "State should be CLAIMABLE");

        // Try to extend heartbeat after it expired
        vm.prank(_grantor);
        vm.expectRevert("Will must be active");
        factory.extendHeartbeat(newInterval);
    }

    function testExtendHeartbeatWithMaxInterval() public {
        uint256 maxInterval = 365 days * 10; // 10 years

        vm.prank(_grantor);
        factory.extendHeartbeat(maxInterval);

        (, uint256 hbInterval0,,) = factory.getWillInfo(_grantor);
        assertEq(hbInterval0, maxInterval, "Should be able to set very long interval");
    }

    // getAssetCount Tests

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

    // getBeneficiaryAssets Tests

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
        factory.checkIn();

        (uint256 lastCheckInVal4,,,) = factory.getWillInfo(_grantor);
        assertEq(lastCheckInVal4, block.timestamp, "lastCheckIn should match current timestamp");
    }

    // Fuzz Tests - depositETH

    function testFuzzDepositETHAmount(uint256 amount) public {
        // Bound amount between 0.001 ether and 1000 ether
        amount = bound(amount, 0.001 ether, 1000 ether);

        vm.startPrank(_grantor);
        vm.deal(_grantor, amount);

        factory.depositETH{value: amount}(_beneficiary);

        // Verify balance and storage
        assertEq(address(factory).balance, amount, "Contract balance should match deposit");
        (,,, uint256 storedAmount,,) = factory.getAsset(_grantor, 0);
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

    // Fuzz Tests - depositERC20

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

    // Fuzz Tests - isClaimable and updateState

    function testFuzzIsClaimableWithVariousTimeOffsets(uint256 timeOffset) public {
        // Bound time offset to reasonable range (0 to 365 days)
        timeOffset = bound(timeOffset, 0, 365 days);

        vm.warp(block.timestamp + timeOffset);

        bool expectedResult = timeOffset >= 30 days;
        bool actualResult = factory.isClaimable(_grantor);

        assertEq(actualResult, expectedResult, "isClaimable result should match expected based on time offset");
    }

    function testFuzzUpdateStateWithVariousTimeOffsets(uint256 timeOffset) public {
        // Bound time offset to reasonable range (0 to 365 days)
        timeOffset = bound(timeOffset, 0, 365 days);

        vm.warp(block.timestamp + timeOffset);

        // Call updateState
        factory.updateState(_grantor);

        // Expected state
        DigitalWillFactory.ContractState expectedState =
            timeOffset >= 30 days ? DigitalWillFactory.ContractState.CLAIMABLE : DigitalWillFactory.ContractState.ACTIVE;

        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(expectedState), "State should match expected based on time offset");
    }

    // FUZZ TESTS - claimSpecificAsset

    // Fuzz Test: Claim with various asset indices
    function testFuzzClaimSpecificAssetWithVariousIndices(uint256 numAssets) public {
        // Bound to reasonable number (1-20)
        numAssets = bound(numAssets, 1, 20);

        // Setup: Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, numAssets * 1 ether);

        for (uint256 i = 0; i < numAssets; i++) {
            factory.depositETH{value: 1 ether}(_beneficiary);
        }
        vm.stopPrank();

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
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Warp time
        vm.warp(block.timestamp + timeOffset);

        // Should be able to claim
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be claimable after time offset");
    }

    // Fuzz Test: Claim ERC20 with various amounts
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

        // Claim
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify
        assertEq(mockToken.balanceOf(_beneficiary), amount, "Beneficiary should receive correct amount");
    }

    // FUZZ TESTS - extendHeartbeat

    // Fuzz Test: Extend heartbeat with various valid intervals
    function testFuzzExtendHeartbeatWithVariousIntervals(uint256 newInterval) public {
        // Bound to valid range (must be longer than initial 30 days, up to 10 years)
        newInterval = bound(newInterval, 30 days + 1, 365 days * 10);

        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        (, uint256 hbInterval1,,) = factory.getWillInfo(_grantor);
        assertEq(hbInterval1, newInterval, "Heartbeat interval should be updated");
        (, uint256 hbInterval20,,) = factory.getWillInfo(_grantor);
        assertGt(hbInterval20, 30 days, "New interval should be longer than initial");
    }

    // Fuzz Test: Verify extended heartbeat is enforced correctly
    function testFuzzExtendHeartbeatAndVerifyEnforcement(uint256 newInterval) public {
        // Bound to reasonable range (31 days to 365 days)
        newInterval = bound(newInterval, 31 days, 365 days);

        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        // Warp to just before new interval expires
        vm.warp(block.timestamp + newInterval - 1 seconds);
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable before new interval expires");

        // Warp to exactly new interval
        vm.warp(block.timestamp + 1 seconds);
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval expires");
    }

    // Fuzz Test: Multiple extensions with increasing intervals
    function testFuzzExtendHeartbeatMultipleExtensions(uint8 numExtensions) public {
        // Bound to reasonable number of extensions (1-10)
        numExtensions = uint8(bound(numExtensions, 1, 10));

        uint256 currentInterval = 30 days;

        vm.startPrank(_grantor);

        for (uint256 i = 0; i < numExtensions; i++) {
            // Each extension adds 30 days more
            uint256 newInterval = currentInterval + 30 days;
            factory.extendHeartbeat(newInterval);

            (, uint256 hbInterval2,,) = factory.getWillInfo(_grantor);
            assertEq(hbInterval2, newInterval, "Interval should be updated");
            currentInterval = newInterval;
        }

        vm.stopPrank();

        // Final interval should be initial + (numExtensions * 30 days)
        uint256 expectedFinalInterval = 30 days + (uint256(numExtensions) * 30 days);
        (, uint256 hbInterval3,,) = factory.getWillInfo(_grantor);
        assertEq(hbInterval3, expectedFinalInterval, "Final interval should match expected");
    }

    // Fuzz Test: Extend heartbeat at various times during initial interval
    function testFuzzExtendHeartbeatAtVariousTimes(uint256 timeOffset) public {
        // Bound to time within initial interval (0 to 29 days)
        timeOffset = bound(timeOffset, 0, 29 days);

        uint256 newInterval = 60 days;

        // Warp to some point during initial interval
        vm.warp(block.timestamp + timeOffset);

        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        // Verify interval is updated
        (, uint256 hbInterval4,,) = factory.getWillInfo(_grantor);
        assertEq(hbInterval4, newInterval, "Heartbeat interval should be updated");

        // Verify lastCheckIn remains unchanged
        (uint256 lastCheckInVal5,,,) = factory.getWillInfo(_grantor);
        assertEq(lastCheckInVal5, block.timestamp - timeOffset, "lastCheckIn should not change");
    }

    // Fuzz Test: Verify invalid intervals revert
    function testFuzzExtendHeartbeatRevertsWithInvalidIntervals(uint256 invalidInterval) public {
        // Bound to invalid range (0 to 30 days, which is not longer than initial)
        invalidInterval = bound(invalidInterval, 0, 30 days);

        vm.prank(_grantor);
        vm.expectRevert("New interval must be longer");
        factory.extendHeartbeat(invalidInterval);
    }

    // Fuzz Test: Extend heartbeat with check-ins at various times
    function testFuzzExtendHeartbeatWithCheckIns(uint256 checkInTime, uint256 extensionTime) public {
        // Bound check-in time to within initial interval
        checkInTime = bound(checkInTime, 1 days, 29 days);
        // Bound extension time to after check-in
        extensionTime = bound(extensionTime, checkInTime + 1 days, checkInTime + 10 days);

        uint256 newInterval = 60 days;

        // Warp to check-in time
        vm.warp(block.timestamp + checkInTime);

        // Check in
        vm.prank(_grantor);
        factory.checkIn();
        (uint256 lastCheckInVal6,,,) = factory.getWillInfo(_grantor);
        uint256 lastCheckInTime = lastCheckInVal6;

        // Warp to extension time
        vm.warp(block.timestamp + (extensionTime - checkInTime));

        // Extend heartbeat
        vm.prank(_grantor);
        factory.extendHeartbeat(newInterval);

        // Verify new interval applies from last check-in
        (, uint256 hbInterval5,,) = factory.getWillInfo(_grantor);
        assertEq(hbInterval5, newInterval, "Interval should be updated");

        // Warp to new interval from last check-in
        vm.warp(lastCheckInTime + newInterval);
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval from last check-in");
    }

    // FUZZ TESTS - getAssetCount

    // Fuzz Test: getAssetCount with various numbers of ETH deposits
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

    // Fuzz Test: getAssetCount with various numbers of ERC20 deposits
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

    // Fuzz Test: getAssetCount with various numbers of ERC721 deposits
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

    // Fuzz Test: getAssetCount with mixed asset types
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
        uint256 actualCount = factory.getAssetCount(_grantor);
        assertEq(actualCount, expectedCount, "Asset count should match total deposits of all types");
    }

    // Fuzz Test: getAssetCount remains constant after claiming
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

        uint256 count = factory.getAssetCount(_grantor);
        assertEq(count, numDeposits, "Asset count should remain the same after claiming");
    }

    // ===========================================
    // FUZZ TESTS - getBeneficiaryAssets
    // ===========================================

    // Fuzz Test: getBeneficiaryAssets with various numbers of assets for single beneficiary
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

    // Fuzz Test: getBeneficiaryAssets with multiple beneficiaries
    function testFuzzGetBeneficiaryAssetsWithMultipleBeneficiaries(uint8 numBeneficiaries) public {
        // Bound to reasonable number (1-10)
        numBeneficiaries = uint8(bound(numBeneficiaries, 1, 10));

        address[] memory beneficiaries = new address[](numBeneficiaries);
        uint256 assetIndex = 0;

        vm.startPrank(_grantor);
        vm.deal(_grantor, uint256(numBeneficiaries) * 3 ether);

        for (uint256 i = 0; i < numBeneficiaries; i++) {
            beneficiaries[i] = makeAddr(string(abi.encodePacked("beneficiary", i)));

            // Each beneficiary gets a random number of assets (1-3)
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
                assertEq(assets[j], assetIndex, "Asset index should match");
                assetIndex++;
            }
        }
    }

    // Fuzz Test: getBeneficiaryAssets persists after claiming
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
        assertEq(assets.length, numAssets, "Beneficiary asset list should remain unchanged after claiming");

        // Verify all indices are still present
        for (uint256 i = 0; i < numAssets; i++) {
            assertEq(assets[i], i, "Asset indices should remain sequential");
        }
    }

    // Fuzz Test: getBeneficiaryAssets with interleaved deposits
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
            assertEq(assets1[i], expectedIndicesBen1[i], "Beneficiary1 asset indices should match");
        }

        // Verify beneficiary2
        uint256[] memory assets2 = factory.getBeneficiaryAssets(_grantor, beneficiary2);
        assertEq(assets2.length, numRounds, "Beneficiary2 should have correct number of assets");
        for (uint256 i = 0; i < numRounds; i++) {
            assertEq(assets2[i], expectedIndicesBen2[i], "Beneficiary2 asset indices should match");
        }
    }

    // Fuzz Test: getBeneficiaryAssets with mixed asset types
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
        assertEq(assets.length, totalAssets, "Beneficiary should have all assets regardless of type");

        // Verify indices are sequential
        for (uint256 i = 0; i < totalAssets; i++) {
            assertEq(assets[i], i, "Asset indices should be sequential");
        }
    }
}
