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

contract IsClaimableTest is Test {
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

    // isClaimable tests
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

    // Fuzz tests
    function testFuzzIsClaimableWithVariousTimeOffsets(uint256 timeOffset) public {
        // Bound time offset to reasonable range (0 to 365 days)
        timeOffset = bound(timeOffset, 0, 365 days);

        vm.warp(block.timestamp + timeOffset);

        bool expectedResult = timeOffset >= 30 days;
        bool actualResult = factory.isClaimable(_grantor);

        assertEq(actualResult, expectedResult, "isClaimable result should match expected based on time offset");
    }
}
