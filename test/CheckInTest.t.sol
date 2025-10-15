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

contract CheckInTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNft;

    address public _grantor;
    address public _randomUser;
    address public _beneficiary;

    // Events to test
    event CheckIn(address indexed grantor, uint256 timestamp);

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

    // Check in tests
    function testCheckInWithNotGrantor() public {
        vm.prank(_randomUser);
        vm.expectRevert("Will does not exist");
        factory.checkIn();
    }

    function testCheckInRevertsWhenNotActive() public {
        // Make the will claimable by warping time
        vm.warp(block.timestamp + 30 days + 1 seconds);
        vm.prank(_grantor);
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

    // Fuzz tests
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
}
