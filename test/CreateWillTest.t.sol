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

contract CreateWillTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;

    address public _grantor;
    address public _randomUser;
    address public _beneficiary;

    // Events to test
    event WillCreated(address indexed grantor, uint256 heartbeatInterval);

    function setUp() public {
        _grantor = makeAddr("grantor");
        _beneficiary = makeAddr("beneficiary");
        _randomUser = makeAddr("randomUser");

        // Deploy mock contracts
        mockToken = new MockERC20("MockToken", "MTK");
        mockNFT = new MockERC721("MockNFT", "MNFT");

        // Deploy factory
        factory = new DigitalWillFactory();
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
        factory.createWill(30 days);

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
}
