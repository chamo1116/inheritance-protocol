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

contract EmergencyWithdrawTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;

    address public _grantor;
    address public _randomUser;
    address public _beneficiary;

    // Events to test
    event EmergencyWithdraw(address indexed grantor, uint256 assetsReturned);

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

    // emergencyWithdraw tests
    function testEmergencyWithdrawRevertsWhenNoWillExists() public {
        vm.prank(_randomUser);
        vm.expectRevert("Will does not exist");
        factory.emergencyWithdraw();
    }

    function testEmergencyWithdrawRevertsWhenWillCompleted() public {
        // Deposit an asset
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        vm.stopPrank();

        // Make claimable and claim to complete
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Try emergency withdraw after completion
        vm.prank(_grantor);
        vm.expectRevert("Will already completed");
        factory.emergencyWithdraw();
    }

    function testEmergencyWithdrawETHSuccessfully() public {
        uint256 depositAmount = 5 ether;

        // Deposit ETH
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: depositAmount}(_beneficiary);
        vm.stopPrank();

        // Record initial balances
        uint256 grantorBalanceBefore = _grantor.balance;
        uint256 contractBalanceBefore = address(factory).balance;

        // Emergency withdraw
        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Verify balances updated
        assertEq(_grantor.balance, grantorBalanceBefore + depositAmount, "Grantor should receive ETH back");
        assertEq(address(factory).balance, contractBalanceBefore - depositAmount, "Contract balance should decrease");

        // Verify asset marked as claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be marked as claimed");

        // Verify will state is COMPLETED
        (,, DigitalWillFactory.ContractState state,) = factory.getWillInfo(_grantor);
        assertEq(uint256(state), uint256(DigitalWillFactory.ContractState.COMPLETED), "Will should be COMPLETED");
    }

    function testEmergencyWithdrawERC20Successfully() public {
        uint256 depositAmount = 1000 * 10 ** 18;

        // Deposit ERC20
        mockToken.mint(_grantor, depositAmount);
        vm.startPrank(_grantor);
        mockToken.approve(address(factory), depositAmount);
        factory.depositERC20(address(mockToken), depositAmount, _beneficiary);
        vm.stopPrank();

        // Record initial balances
        uint256 grantorBalanceBefore = mockToken.balanceOf(_grantor);
        uint256 contractBalanceBefore = mockToken.balanceOf(address(factory));

        // Emergency withdraw
        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Verify balances updated
        assertEq(
            mockToken.balanceOf(_grantor), grantorBalanceBefore + depositAmount, "Grantor should receive tokens back"
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

    function testEmergencyWithdrawERC721Successfully() public {
        // Deposit ERC721
        uint256 tokenId = mockNFT.mint(_grantor);
        vm.startPrank(_grantor);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);
        vm.stopPrank();

        // Emergency withdraw
        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Verify NFT transferred back
        assertEq(mockNFT.ownerOf(tokenId), _grantor, "Grantor should own the NFT again");

        // Verify asset marked as claimed
        (,,,,, bool claimed) = factory.getAsset(_grantor, 0);
        assertTrue(claimed, "Asset should be marked as claimed");
    }

    function testEmergencyWithdrawMultipleAssets() public {
        // Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        // Deposit ETH
        factory.depositETH{value: 2 ether}(_beneficiary);

        // Deposit ERC20
        uint256 tokenAmount = 1000 * 10 ** 18;
        mockToken.mint(_grantor, tokenAmount);
        mockToken.approve(address(factory), tokenAmount);
        factory.depositERC20(address(mockToken), tokenAmount, _beneficiary);

        // Deposit ERC721
        uint256 tokenId = mockNFT.mint(_grantor);
        mockNFT.approve(address(factory), tokenId);
        factory.depositERC721(address(mockNFT), tokenId, _beneficiary);

        vm.stopPrank();

        // Record initial balances
        uint256 grantorETHBefore = _grantor.balance;
        uint256 grantorTokenBefore = mockToken.balanceOf(_grantor);

        // Emergency withdraw
        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Verify all assets returned
        assertEq(_grantor.balance, grantorETHBefore + 2 ether, "Grantor should receive ETH back");
        assertEq(mockToken.balanceOf(_grantor), grantorTokenBefore + tokenAmount, "Grantor should receive tokens back");
        assertEq(mockNFT.ownerOf(tokenId), _grantor, "Grantor should own NFT again");

        // Verify all assets marked as claimed
        (,,,,, bool claimed0) = factory.getAsset(_grantor, 0);
        (,,,,, bool claimed1) = factory.getAsset(_grantor, 1);
        (,,,,, bool claimed2) = factory.getAsset(_grantor, 2);
        assertTrue(claimed0, "Asset 0 should be claimed");
        assertTrue(claimed1, "Asset 1 should be claimed");
        assertTrue(claimed2, "Asset 2 should be claimed");
    }

    function testEmergencyWithdrawMultipleBeneficiaries() public {
        address beneficiary1 = makeAddr("beneficiary1");
        address beneficiary2 = makeAddr("beneficiary2");

        // Deposit assets for different beneficiaries
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);

        factory.depositETH{value: 1 ether}(beneficiary1);
        factory.depositETH{value: 2 ether}(beneficiary2);
        factory.depositETH{value: 3 ether}(beneficiary1);

        vm.stopPrank();

        uint256 grantorBalanceBefore = _grantor.balance;

        // Emergency withdraw - should return all assets regardless of beneficiary
        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Verify all ETH returned to grantor
        assertEq(_grantor.balance, grantorBalanceBefore + 6 ether, "Grantor should receive all ETH back");

        // Verify beneficiaries didn't receive anything
        assertEq(beneficiary1.balance, 0, "Beneficiary1 should not receive anything");
        assertEq(beneficiary2.balance, 0, "Beneficiary2 should not receive anything");
    }

    function testEmergencyWithdrawAfterPartialClaim() public {
        // Deposit multiple assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);
        vm.stopPrank();

        // Make claimable
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);

        // Beneficiary claims one asset
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        // Verify first asset claimed
        (,,,,, bool claimed0) = factory.getAsset(_grantor, 0);
        assertTrue(claimed0, "First asset should be claimed");

        uint256 grantorBalanceBefore = _grantor.balance;

        // Emergency withdraw - should only return unclaimed assets
        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Verify only unclaimed assets returned (2 + 3 = 5 ETH)
        assertEq(_grantor.balance, grantorBalanceBefore + 5 ether, "Grantor should receive only unclaimed ETH");

        // Verify assets status
        (,,,,, bool claimedAfter1) = factory.getAsset(_grantor, 1);
        (,,,,, bool claimedAfter2) = factory.getAsset(_grantor, 2);
        assertTrue(claimedAfter1, "Asset 1 should now be claimed");
        assertTrue(claimedAfter2, "Asset 2 should now be claimed");
    }

    function testEmergencyWithdrawWhileActive() public {
        // Deposit assets while will is ACTIVE
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 5 ether}(_beneficiary);
        vm.stopPrank();

        // Verify will is ACTIVE
        (,, DigitalWillFactory.ContractState stateBefore,) = factory.getWillInfo(_grantor);
        assertEq(uint256(stateBefore), uint256(DigitalWillFactory.ContractState.ACTIVE), "Will should be ACTIVE");

        uint256 grantorBalanceBefore = _grantor.balance;

        // Emergency withdraw while ACTIVE
        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Verify withdrawal successful
        assertEq(_grantor.balance, grantorBalanceBefore + 5 ether, "Grantor should receive ETH back");

        // Verify will state changed to COMPLETED
        (,, DigitalWillFactory.ContractState stateAfter,) = factory.getWillInfo(_grantor);
        assertEq(uint256(stateAfter), uint256(DigitalWillFactory.ContractState.COMPLETED), "Will should be COMPLETED");
    }

    function testEmergencyWithdrawWhileClaimable() public {
        // Deposit assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 5 ether}(_beneficiary);
        vm.stopPrank();

        // Make will CLAIMABLE
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);

        // Verify will is CLAIMABLE
        (,, DigitalWillFactory.ContractState stateBefore,) = factory.getWillInfo(_grantor);
        assertEq(uint256(stateBefore), uint256(DigitalWillFactory.ContractState.CLAIMABLE), "Will should be CLAIMABLE");

        uint256 grantorBalanceBefore = _grantor.balance;

        // Emergency withdraw while CLAIMABLE - grantor can still reclaim
        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Verify withdrawal successful
        assertEq(
            _grantor.balance, grantorBalanceBefore + 5 ether, "Grantor should receive ETH back even when claimable"
        );
    }

    function testEmergencyWithdrawEmitsEvent() public {
        // Deposit 3 assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);
        factory.depositETH{value: 2 ether}(_beneficiary);
        factory.depositETH{value: 3 ether}(_beneficiary);
        vm.stopPrank();

        // Expect event with correct number of assets returned
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(_grantor, 3);

        vm.prank(_grantor);
        factory.emergencyWithdraw();
    }

    function testEmergencyWithdrawWithNoAssets() public {
        // Emergency withdraw with no assets deposited
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(_grantor, 0);

        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Verify will state changed to COMPLETED even with no assets
        (,, DigitalWillFactory.ContractState state,) = factory.getWillInfo(_grantor);
        assertEq(uint256(state), uint256(DigitalWillFactory.ContractState.COMPLETED), "Will should be COMPLETED");
    }

    function testEmergencyWithdrawCannotBeCalledTwice() public {
        // Deposit assets
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 5 ether}(_beneficiary);
        vm.stopPrank();

        // First emergency withdraw
        vm.prank(_grantor);
        factory.emergencyWithdraw();

        // Try second emergency withdraw
        vm.prank(_grantor);
        vm.expectRevert("Will already completed");
        factory.emergencyWithdraw();
    }

    // Fuzz tests
    function testFuzzEmergencyWithdrawETHAmount(uint256 amount) public {
        // Bound amount between 0.001 ether and 1000 ether
        amount = bound(amount, 0.001 ether, 1000 ether);

        vm.startPrank(_grantor);
        vm.deal(_grantor, amount);
        factory.depositETH{value: amount}(_beneficiary);
        vm.stopPrank();

        uint256 grantorBalanceBefore = _grantor.balance;

        vm.prank(_grantor);
        factory.emergencyWithdraw();

        assertEq(_grantor.balance, grantorBalanceBefore + amount, "Grantor should receive correct amount back");
    }

    function testFuzzEmergencyWithdrawMultipleAssets(uint8 numAssets) public {
        // Bound to reasonable number (1-20)
        numAssets = uint8(bound(numAssets, 1, 20));

        vm.startPrank(_grantor);
        vm.deal(_grantor, uint256(numAssets) * 1 ether);

        for (uint256 i = 0; i < numAssets; i++) {
            factory.depositETH{value: 1 ether}(_beneficiary);
        }
        vm.stopPrank();

        uint256 grantorBalanceBefore = _grantor.balance;

        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(_grantor, numAssets);

        vm.prank(_grantor);
        factory.emergencyWithdraw();

        assertEq(
            _grantor.balance,
            grantorBalanceBefore + (uint256(numAssets) * 1 ether),
            "Grantor should receive all deposits back"
        );
    }

    function testFuzzEmergencyWithdrawERC20Amount(uint256 amount) public {
        // Bound amount between 1 and 1 billion tokens (with 18 decimals)
        amount = bound(amount, 1, 1_000_000_000 * 10 ** 18);

        mockToken.mint(_grantor, amount);
        vm.startPrank(_grantor);
        mockToken.approve(address(factory), amount);
        factory.depositERC20(address(mockToken), amount, _beneficiary);
        vm.stopPrank();

        uint256 grantorBalanceBefore = mockToken.balanceOf(_grantor);

        vm.prank(_grantor);
        factory.emergencyWithdraw();

        assertEq(
            mockToken.balanceOf(_grantor),
            grantorBalanceBefore + amount,
            "Grantor should receive correct token amount back"
        );
    }
}
