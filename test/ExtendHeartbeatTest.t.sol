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

contract ExtendHeartbeatTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;

    address public _grantor;
    address public _randomUser;
    address public _beneficiary;

    // Events to test
    event HeartbeatExtended(address indexed grantor, uint256 newInterval);

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

    // extendHeartbeat tests
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

    // Fuzz tests
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

    function testFuzzExtendHeartbeatRevertsWithInvalidIntervals(uint256 invalidInterval) public {
        // Bound to invalid range (0 to 30 days, which is not longer than initial)
        invalidInterval = bound(invalidInterval, 0, 30 days);

        vm.prank(_grantor);
        vm.expectRevert("New interval must be longer");
        factory.extendHeartbeat(invalidInterval);
    }

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
        assertEq(hbInterval5, newInterval, "Heartbeat interval should be updated");

        // Verify can claim after new interval from last check-in
        vm.warp(lastCheckInTime + newInterval);
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval from last check-in");
    }
}
