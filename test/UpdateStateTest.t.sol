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

contract UpdateStateTest is Test {
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

    // updateState tests
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

    // Fuzz tests
    function testFuzzUpdateStateWithVariousTimeOffsets(uint256 timeOffset) public {
        // Bound time offset to reasonable range (0 to 365 days)
        timeOffset = bound(timeOffset, 0, 365 days);

        vm.warp(block.timestamp + timeOffset);

        // Call updateState
        factory.updateState(_grantor);

        // Check expected state
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        if (timeOffset >= 30 days) {
            assertEq(
                uint256(willState),
                uint256(DigitalWillFactory.ContractState.CLAIMABLE),
                "Should be CLAIMABLE when time offset >= heartbeat"
            );
        } else {
            assertEq(
                uint256(willState),
                uint256(DigitalWillFactory.ContractState.ACTIVE),
                "Should be ACTIVE when time offset < heartbeat"
            );
        }
    }
}
