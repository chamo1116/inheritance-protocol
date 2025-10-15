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
}

contract ModifyHeartbeatTest is Test {
    DigitalWillFactory public factory;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;

    address public _grantor;
    address public _beneficiary;
    address public _randomUser;

    // Events to test
    event HeartbeatModified(address indexed grantor, uint256 oldInterval, uint256 newInterval);

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

    // Basic functionality tests - Increase
    function testModifyHeartbeatIncreaseSuccessfully() public {
        uint256 newInterval = 60 days;
        (, uint256 initialInterval,,) = factory.getWillInfo(_grantor);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        (, uint256 updatedInterval,,) = factory.getWillInfo(_grantor);
        assertEq(updatedInterval, newInterval, "Heartbeat interval should be updated");
        assertGt(updatedInterval, initialInterval, "New interval should be longer than initial");
    }

    function testModifyHeartbeatDecreaseSuccessfully() public {
        uint256 newInterval = 7 days;
        (, uint256 initialInterval,,) = factory.getWillInfo(_grantor);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        (, uint256 updatedInterval,,) = factory.getWillInfo(_grantor);
        assertEq(updatedInterval, newInterval, "Heartbeat interval should be decreased");
        assertLt(updatedInterval, initialInterval, "New interval should be shorter than initial");
    }

    function testModifyHeartbeatResetsCheckInWhenDecreasing() public {
        uint256 newInterval = 7 days;
        (uint256 lastCheckIn1,,,) = factory.getWillInfo(_grantor);

        // Warp time forward
        vm.warp(block.timestamp + 10 days);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        (uint256 lastCheckIn2,,,) = factory.getWillInfo(_grantor);

        // lastCheckIn should be reset to current timestamp when decreasing
        assertEq(lastCheckIn2, block.timestamp, "lastCheckIn should be reset when decreasing interval");
        assertGt(lastCheckIn2, lastCheckIn1, "lastCheckIn should be updated");
    }

    function testModifyHeartbeatDoesNotResetCheckInWhenIncreasing() public {
        uint256 newInterval = 60 days;
        (uint256 lastCheckIn1,,,) = factory.getWillInfo(_grantor);

        // Warp time forward
        vm.warp(block.timestamp + 10 days);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        (uint256 lastCheckIn2,,,) = factory.getWillInfo(_grantor);

        // lastCheckIn should NOT be reset when increasing
        assertEq(lastCheckIn2, lastCheckIn1, "lastCheckIn should not change when increasing interval");
    }

    function testModifyHeartbeatEmitsEvent() public {
        uint256 newInterval = 60 days;
        uint256 oldInterval = 30 days;

        vm.expectEmit(true, true, true, true);
        emit HeartbeatModified(_grantor, oldInterval, newInterval);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);
    }

    // Revert tests
    function testModifyHeartbeatRevertsWhenNotGrantor() public {
        uint256 newInterval = 60 days;

        vm.prank(_randomUser);
        vm.expectRevert("Will does not exist");
        factory.modifyHeartbeat(newInterval);
    }

    function testModifyHeartbeatRevertsWhenNotActive() public {
        uint256 newInterval = 60 days;

        // Make the will claimable by warping time
        vm.warp(block.timestamp + 30 days + 1 seconds);
        factory.updateState(_grantor);

        vm.prank(_grantor);
        vm.expectRevert("Will must be active");
        factory.modifyHeartbeat(newInterval);
    }

    function testModifyHeartbeatRevertsWhenCompleted() public {
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
        factory.modifyHeartbeat(newInterval);
    }

    function testModifyHeartbeatRevertsWhenSameInterval() public {
        uint256 sameInterval = 30 days; // Same as initial

        vm.prank(_grantor);
        vm.expectRevert("New interval must be different");
        factory.modifyHeartbeat(sameInterval);
    }

    function testModifyHeartbeatRevertsWhenLessThanMinimum() public {
        uint256 tooShort = 23 hours; // Less than 1 day

        vm.prank(_grantor);
        vm.expectRevert("Interval must be at least 1 day");
        factory.modifyHeartbeat(tooShort);
    }

    function testModifyHeartbeatRevertsWhenZero() public {
        vm.prank(_grantor);
        vm.expectRevert("Interval must be at least 1 day");
        factory.modifyHeartbeat(0);
    }

    function testModifyHeartbeatRevertsWhenExactly1DayMinusOne() public {
        uint256 tooShort = 1 days - 1;

        vm.prank(_grantor);
        vm.expectRevert("Interval must be at least 1 day");
        factory.modifyHeartbeat(tooShort);
    }

    // Edge case: exactly 1 day should work
    function testModifyHeartbeatAcceptsExactly1Day() public {
        uint256 minInterval = 1 days;

        vm.prank(_grantor);
        factory.modifyHeartbeat(minInterval);

        (, uint256 updatedInterval,,) = factory.getWillInfo(_grantor);
        assertEq(updatedInterval, minInterval, "Should accept exactly 1 day");
    }

    // Multiple modifications
    function testModifyHeartbeatMultipleTimes() public {
        vm.startPrank(_grantor);

        // Increase
        factory.modifyHeartbeat(60 days);
        (, uint256 interval1,,) = factory.getWillInfo(_grantor);
        assertEq(interval1, 60 days, "First modification should be set");

        // Decrease
        factory.modifyHeartbeat(7 days);
        (, uint256 interval2,,) = factory.getWillInfo(_grantor);
        assertEq(interval2, 7 days, "Second modification should be set");

        // Increase again
        factory.modifyHeartbeat(90 days);
        (, uint256 interval3,,) = factory.getWillInfo(_grantor);
        assertEq(interval3, 90 days, "Third modification should be set");

        vm.stopPrank();
    }

    // Verification tests
    function testModifyHeartbeatAndVerifyNewIntervalUsedWhenIncreasing() public {
        uint256 newInterval = 60 days;
        (uint256 lastCheckIn,,,) = factory.getWillInfo(_grantor);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        // Warp to just before new interval expires
        vm.warp(lastCheckIn + newInterval - 1 seconds);

        // Should not be claimable yet
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable before new interval expires");

        // Warp to exactly new interval
        vm.warp(block.timestamp + 1 seconds);

        // Should now be claimable
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval expires");
    }

    function testModifyHeartbeatAndVerifyNewIntervalUsedWhenDecreasing() public {
        uint256 newInterval = 7 days;

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        (uint256 lastCheckIn,,,) = factory.getWillInfo(_grantor);

        // Warp to just before new interval expires (from reset lastCheckIn)
        vm.warp(lastCheckIn + newInterval - 1 seconds);

        // Should not be claimable yet
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable before new interval expires");

        // Warp to exactly new interval
        vm.warp(block.timestamp + 1 seconds);

        // Should now be claimable
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval expires");
    }

    function testModifyHeartbeatDoesNotCauseImmediateClaimability() public {
        // Warp halfway through initial interval
        vm.warp(block.timestamp + 15 days);

        uint256 newInterval = 5 days;

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        // Should NOT be immediately claimable after reducing interval
        // because lastCheckIn is reset
        assertFalse(factory.isClaimable(_grantor), "Should not be immediately claimable");

        // Should be claimable after new interval from reset
        vm.warp(block.timestamp + newInterval);
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval");
    }

    function testModifyHeartbeatPreventsAbuse() public {
        // Grantor can't set very short interval and immediately make will claimable
        uint256 veryShort = 1 days;

        // Warp close to expiry
        vm.warp(block.timestamp + 29 days);

        vm.prank(_grantor);
        factory.modifyHeartbeat(veryShort);

        // Should NOT be claimable immediately
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable immediately after decrease");

        (uint256 lastCheckIn,,,) = factory.getWillInfo(_grantor);

        // Should be claimable after new interval from reset lastCheckIn
        vm.warp(lastCheckIn + veryShort);
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval");
    }

    // Integration with check-in
    function testModifyHeartbeatWithCheckInBetween() public {
        uint256 newInterval = 60 days;

        // First check in (implicit at deployment)
        (uint256 firstCheckIn,,,) = factory.getWillInfo(_grantor);

        // Warp some time
        vm.warp(block.timestamp + 10 days);

        // Check in again
        vm.prank(_grantor);
        factory.checkIn();
        (uint256 secondCheckIn,,,) = factory.getWillInfo(_grantor);

        assertGt(secondCheckIn, firstCheckIn, "Second check-in should be later");

        // Modify heartbeat (increase)
        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        // Verify new interval applies from last check-in (which doesn't change for increase)
        vm.warp(secondCheckIn + newInterval);
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval from last check-in");
    }

    function testModifyHeartbeatAfterPartialInterval() public {
        uint256 newInterval = 60 days;

        // Warp halfway through initial interval
        vm.warp(block.timestamp + 15 days);

        (uint256 lastCheckIn,,,) = factory.getWillInfo(_grantor);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        // Warp to original interval (30 days from start)
        vm.warp(lastCheckIn + 30 days);

        // Should not be claimable yet (new interval is 60 days from original checkIn)
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable at old interval");

        // Warp to new interval (60 days from start)
        vm.warp(lastCheckIn + newInterval);

        // Should now be claimable
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval");
    }

    // Integration with assets
    function testModifyHeartbeatDoesNotAffectAssets() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);

        (,,, uint256 assetCountBefore) = factory.getWillInfo(_grantor);

        factory.modifyHeartbeat(60 days);

        (,,, uint256 assetCountAfter) = factory.getWillInfo(_grantor);
        vm.stopPrank();

        assertEq(assetCountAfter, assetCountBefore, "Asset count should not change");

        // Verify asset still intact
        (,,, uint256 amount, address beneficiary, bool claimed) = factory.getAsset(_grantor, 0);
        assertEq(amount, 1 ether, "Asset amount should be unchanged");
        assertEq(beneficiary, _beneficiary, "Beneficiary should be unchanged");
        assertFalse(claimed, "Asset should not be claimed");
    }

    function testModifyHeartbeatThenClaim() public {
        vm.startPrank(_grantor);
        vm.deal(_grantor, 10 ether);
        factory.depositETH{value: 1 ether}(_beneficiary);

        // Reduce interval
        factory.modifyHeartbeat(7 days);
        vm.stopPrank();

        (uint256 lastCheckIn,,,) = factory.getWillInfo(_grantor);

        // Warp to new interval
        vm.warp(lastCheckIn + 7 days);
        factory.updateState(_grantor);

        // Beneficiary should be able to claim
        uint256 balanceBefore = _beneficiary.balance;
        vm.prank(_beneficiary);
        factory.claimAsset(_grantor, 0);

        assertEq(_beneficiary.balance, balanceBefore + 1 ether, "Beneficiary should receive asset");
    }

    // State management
    function testModifyHeartbeatDoesNotChangeState() public {
        // Verify initial state is ACTIVE
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.ACTIVE), "Initial state should be ACTIVE");

        vm.prank(_grantor);
        factory.modifyHeartbeat(60 days);

        // Verify state is still ACTIVE
        (,, willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.ACTIVE), "State should remain ACTIVE");
    }

    function testModifyHeartbeatRevertsAfterHeartbeatExpires() public {
        uint256 newInterval = 60 days;

        // Warp time beyond initial heartbeat interval
        vm.warp(block.timestamp + 30 days + 1 seconds);

        // Update state to CLAIMABLE
        factory.updateState(_grantor);

        // Verify state is CLAIMABLE
        (,, DigitalWillFactory.ContractState willState,) = factory.getWillInfo(_grantor);
        assertEq(uint256(willState), uint256(DigitalWillFactory.ContractState.CLAIMABLE), "State should be CLAIMABLE");

        // Try to modify heartbeat after it expired
        vm.prank(_grantor);
        vm.expectRevert("Will must be active");
        factory.modifyHeartbeat(newInterval);
    }

    // Extreme values
    function testModifyHeartbeatWithMaxInterval() public {
        uint256 maxInterval = 365 days * 10; // 10 years

        vm.prank(_grantor);
        factory.modifyHeartbeat(maxInterval);

        (, uint256 interval,,) = factory.getWillInfo(_grantor);
        assertEq(interval, maxInterval, "Should be able to set very long interval");
    }

    function testModifyHeartbeatWithMinInterval() public {
        uint256 minInterval = 1 days;

        vm.prank(_grantor);
        factory.modifyHeartbeat(minInterval);

        (, uint256 interval,,) = factory.getWillInfo(_grantor);
        assertEq(interval, minInterval, "Should be able to set minimum interval");
    }

    // Fuzz tests
    function testFuzzModifyHeartbeatIncrease(uint256 newInterval) public {
        // Bound to valid range (must be longer than initial 30 days, up to 10 years)
        newInterval = bound(newInterval, 30 days + 1, 365 days * 10);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        (, uint256 interval,,) = factory.getWillInfo(_grantor);
        assertEq(interval, newInterval, "Heartbeat interval should be updated");
        assertGt(interval, 30 days, "New interval should be longer than initial");
    }

    function testFuzzModifyHeartbeatDecrease(uint256 newInterval) public {
        // Bound to valid range (1 day to less than 30 days)
        newInterval = bound(newInterval, 1 days, 30 days - 1);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        (, uint256 interval,,) = factory.getWillInfo(_grantor);
        assertEq(interval, newInterval, "Heartbeat interval should be updated");
        assertLt(interval, 30 days, "New interval should be shorter than initial");
    }

    function testFuzzModifyHeartbeatAndVerifyEnforcement(uint256 newInterval) public {
        // Bound to reasonable range (1 day to 365 days), excluding current 30 days
        // Split into two ranges to avoid the current interval
        if (newInterval % 2 == 0) {
            newInterval = bound(newInterval, 1 days, 30 days - 1);
        } else {
            newInterval = bound(newInterval, 30 days + 1, 365 days);
        }

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        (uint256 lastCheckIn,,,) = factory.getWillInfo(_grantor);

        // Warp to just before new interval expires
        vm.warp(lastCheckIn + newInterval - 1 seconds);
        assertFalse(factory.isClaimable(_grantor), "Should not be claimable before new interval expires");

        // Warp to exactly new interval
        vm.warp(block.timestamp + 1 seconds);
        assertTrue(factory.isClaimable(_grantor), "Should be claimable after new interval expires");
    }

    function testFuzzModifyHeartbeatMultipleModifications(uint8 numModifications) public {
        // Bound to reasonable number of modifications (1-10)
        numModifications = uint8(bound(numModifications, 1, 10));

        vm.startPrank(_grantor);

        uint256 currentInterval = 30 days;

        for (uint256 i = 0; i < numModifications; i++) {
            // Alternate between increasing and decreasing
            uint256 newInterval;
            if (i % 2 == 0) {
                newInterval = currentInterval + 10 days;
            } else {
                newInterval = currentInterval > 11 days ? currentInterval - 10 days : 1 days;
            }

            factory.modifyHeartbeat(newInterval);

            (, uint256 interval,,) = factory.getWillInfo(_grantor);
            assertEq(interval, newInterval, "Interval should be updated");
            currentInterval = newInterval;
        }

        vm.stopPrank();
    }

    function testFuzzModifyHeartbeatAtVariousTimes(uint256 timeOffset) public {
        // Bound to time within initial interval (0 to 29 days)
        timeOffset = bound(timeOffset, 0, 29 days);

        uint256 newInterval = 60 days;

        // Warp to some point during initial interval
        vm.warp(block.timestamp + timeOffset);

        (uint256 lastCheckInBefore,,,) = factory.getWillInfo(_grantor);

        vm.prank(_grantor);
        factory.modifyHeartbeat(newInterval);

        // Verify interval is updated
        (, uint256 interval,,) = factory.getWillInfo(_grantor);
        assertEq(interval, newInterval, "Heartbeat interval should be updated");

        // Verify lastCheckIn remains unchanged (because we're increasing)
        (uint256 lastCheckInAfter,,,) = factory.getWillInfo(_grantor);
        assertEq(lastCheckInAfter, lastCheckInBefore, "lastCheckIn should not change when increasing");
    }

    function testFuzzModifyHeartbeatRevertsWithInvalidIntervals(uint256 invalidInterval) public {
        // Bound to invalid range (0 to less than 1 day)
        invalidInterval = bound(invalidInterval, 0, 1 days - 1);

        vm.prank(_grantor);
        vm.expectRevert("Interval must be at least 1 day");
        factory.modifyHeartbeat(invalidInterval);
    }
}
