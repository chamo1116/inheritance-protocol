// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/DigitalWillFactory.sol";

/**
 * @title Base
 * @notice Base test contract with comprehensive helper functions for all tests
 * @dev Inherit from this contract to access common test utilities
 */
contract Base is Test {
    DigitalWillFactory public factory;

    // ============ User Creation Helpers ============

    /**
     * @notice Create a labeled address for testing
     * @param name The label for the address
     * @return addr The created address
     */
    function createUser(string memory name) internal returns (address addr) {
        addr = makeAddr(name);
        vm.label(addr, name);
    }

    /**
     * @notice Create multiple labeled addresses
     * @param names Array of names for addresses
     * @return addrs Array of created addresses
     */
    function createUsers(string[] memory names) internal returns (address[] memory addrs) {
        addrs = new address[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            addrs[i] = createUser(names[i]);
        }
    }

    /**
     * @notice Create a contract beneficiary for testing
     * @return contractAddr Address of the deployed mock contract
     */
    function createContractBeneficiary() internal returns (address contractAddr) {
        MockBeneficiary mock = new MockBeneficiary();
        contractAddr = address(mock);
        vm.label(contractAddr, "ContractBeneficiary");
    }

    // ============ Will Setup Helpers ============

    /**
     * @notice Create a will for a grantor
     * @param grantor The grantor address
     * @param heartbeatInterval The heartbeat interval in seconds
     */
    function createWillFor(address grantor, uint256 heartbeatInterval) internal {
        vm.prank(grantor);
        factory.createWill(heartbeatInterval);
    }

    /**
     * @notice Setup a basic will with default heartbeat (30 days)
     * @param grantor The grantor address
     */
    function setupBasicWill(address grantor) internal {
        createWillFor(grantor, 30 days);
    }

    // ============ Asset Deposit Helpers ============

    /**
     * @notice Deposit ETH to a will
     * @param grantor The grantor depositing
     * @param amount Amount of ETH to deposit
     * @param beneficiary The beneficiary of the asset
     */
    function depositETH(address grantor, uint256 amount, address beneficiary) internal {
        // Add to existing balance instead of setting it
        vm.deal(grantor, grantor.balance + amount);
        vm.prank(grantor);
        factory.depositETH{value: amount}(beneficiary);
    }

    /**
     * @notice Deposit ERC20 to a will
     * @param grantor The grantor depositing
     * @param token The ERC20 token address
     * @param amount Amount to deposit
     * @param beneficiary The beneficiary of the asset
     */
    function depositERC20(address grantor, address token, uint256 amount, address beneficiary) internal {
        // Mint tokens to grantor (assumes MockERC20 or similar)
        vm.prank(grantor);
        IERC20(token).approve(address(factory), amount);

        vm.prank(grantor);
        factory.depositERC20(token, amount, beneficiary);
    }

    /**
     * @notice Deposit ERC721 to a will
     * @param grantor The grantor depositing
     * @param nft The ERC721 token address
     * @param tokenId The token ID to deposit
     * @param beneficiary The beneficiary of the asset
     */
    function depositERC721(address grantor, address nft, uint256 tokenId, address beneficiary) internal {
        vm.prank(grantor);
        IERC721(nft).approve(address(factory), tokenId);

        vm.prank(grantor);
        factory.depositERC721(nft, tokenId, beneficiary);
    }

    // ============ Beneficiary Management Helpers ============

    /**
     * @notice Make a beneficiary accept their designation
     * @param beneficiary The beneficiary address
     * @param grantor The grantor address
     */
    function acceptBeneficiary(address beneficiary, address grantor) internal {
        vm.prank(beneficiary);
        factory.acceptBeneficiary(grantor);
    }

    /**
     * @notice Accept designation for multiple beneficiaries
     * @param beneficiaries Array of beneficiary addresses
     * @param grantor The grantor address
     */
    function acceptBeneficiaries(address[] memory beneficiaries, address grantor) internal {
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            if (beneficiaries[i] != address(0)) {
                vm.prank(beneficiaries[i]);
                factory.acceptBeneficiary(grantor);
            }
        }
    }

    /**
     * @notice Reject beneficiary designation
     * @param beneficiary The beneficiary address
     * @param grantor The grantor address
     */
    function rejectBeneficiary(address beneficiary, address grantor) internal {
        vm.prank(beneficiary);
        factory.rejectBeneficiary(grantor);
    }

    /**
     * @notice Approve a contract as beneficiary
     * @param grantor The grantor address
     * @param contractAddr The contract beneficiary address
     */
    function approveContractBeneficiary(address grantor, address contractAddr) internal {
        vm.prank(grantor);
        factory.approveContractBeneficiary(contractAddr);
    }

    // ============ Will State Helpers ============

    /**
     * @notice Make a will claimable by warping time
     * @param grantor The grantor address
     * @param heartbeatInterval The heartbeat interval to warp past
     */
    function makeWillClaimable(address grantor, uint256 heartbeatInterval) internal {
        vm.warp(block.timestamp + heartbeatInterval + 1);
        vm.prank(grantor);
        factory.updateState(grantor);
    }

    /**
     * @notice Make a will claimable with default 30 day heartbeat
     * @param grantor The grantor address
     */
    function makeWillClaimable(address grantor) internal {
        makeWillClaimable(grantor, 30 days);
    }

    /**
     * @notice Perform check-in for a grantor
     * @param grantor The grantor address
     */
    function checkIn(address grantor) internal {
        vm.prank(grantor);
        factory.checkIn();
    }

    /**
     * @notice Update will state
     * @param caller The address calling updateState
     * @param grantor The grantor whose will to update
     */
    function updateState(address caller, address grantor) internal {
        vm.prank(caller);
        factory.updateState(grantor);
    }

    // ============ Asset Claiming Helpers ============

    /**
     * @notice Claim an asset as beneficiary
     * @param beneficiary The beneficiary claiming
     * @param grantor The grantor address
     * @param assetIndex The index of the asset to claim
     */
    function claimAsset(address beneficiary, address grantor, uint256 assetIndex) internal {
        vm.prank(beneficiary);
        factory.claimAsset(grantor, assetIndex);
    }

    /**
     * @notice Claim multiple assets
     * @param beneficiary The beneficiary claiming
     * @param grantor The grantor address
     * @param assetIndices Array of asset indices to claim
     */
    function claimAssets(address beneficiary, address grantor, uint256[] memory assetIndices) internal {
        vm.startPrank(beneficiary);
        for (uint256 i = 0; i < assetIndices.length; i++) {
            factory.claimAsset(grantor, assetIndices[i]);
        }
        vm.stopPrank();
    }

    // ============ Setup & Teardown Helpers ============

    /**
     * @notice Complete setup: create will, deposit asset, accept
     * @param grantor The grantor address
     * @param beneficiary The beneficiary address
     * @param depositAmount Amount of ETH to deposit
     * @return assetIndex The index of the deposited asset
     */
    function setupWillWithETH(address grantor, address beneficiary, uint256 depositAmount)
        internal
        returns (uint256 assetIndex)
    {
        setupBasicWill(grantor);
        depositETH(grantor, depositAmount, beneficiary);
        acceptBeneficiary(beneficiary, grantor);
        return 0; // First asset index
    }

    /**
     * @notice Setup will and make it immediately claimable
     * @param grantor The grantor address
     * @param beneficiary The beneficiary address
     * @param depositAmount Amount of ETH to deposit
     */
    function setupClaimableWill(address grantor, address beneficiary, uint256 depositAmount) internal {
        setupWillWithETH(grantor, beneficiary, depositAmount);
        makeWillClaimable(grantor);
    }

    // ============ Utility Helpers ============

    /**
     * @notice Check if an address is a contract
     * @param account The address to check
     * @return True if address has code
     */
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @notice Fund an address with ETH
     * @param user The address to fund
     * @param amount Amount of ETH to give
     */
    function fundUser(address user, uint256 amount) internal {
        vm.deal(user, amount);
    }

    /**
     * @notice Fund multiple addresses with ETH
     * @param users Array of addresses to fund
     * @param amount Amount of ETH to give each
     */
    function fundUsers(address[] memory users, uint256 amount) internal {
        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], amount);
        }
    }

    /**
     * @notice Get will state for a grantor
     * @param grantor The grantor address
     * @return state The current contract state
     */
    function getWillState(address grantor) internal view returns (DigitalWillFactory.ContractState state) {
        (,, state,) = factory.getWillInfo(grantor);
    }

    /**
     * @notice Assert will is in expected state
     * @param grantor The grantor address
     * @param expectedState The expected state
     * @param message Error message if assertion fails
     */
    function assertWillState(address grantor, DigitalWillFactory.ContractState expectedState, string memory message)
        internal
        view
    {
        DigitalWillFactory.ContractState actualState = getWillState(grantor);
        assertEq(uint256(actualState), uint256(expectedState), message);
    }

    /**
     * @notice Fast forward time by specified duration
     * @param duration Time to advance in seconds
     */
    function skipTime(uint256 duration) internal {
        vm.warp(block.timestamp + duration);
    }

    // ============ Assertion Helpers ============

    /**
     * @notice Assert asset is claimed
     * @param grantor The grantor address
     * @param assetIndex The asset index
     */
    function assertAssetClaimed(address grantor, uint256 assetIndex) internal view {
        (,,,,, bool claimed) = factory.getAsset(grantor, assetIndex);
        assertTrue(claimed, "Asset should be claimed");
    }

    /**
     * @notice Assert asset is not claimed
     * @param grantor The grantor address
     * @param assetIndex The asset index
     */
    function assertAssetNotClaimed(address grantor, uint256 assetIndex) internal view {
        (,,,,, bool claimed) = factory.getAsset(grantor, assetIndex);
        assertFalse(claimed, "Asset should not be claimed");
    }

    /**
     * @notice Assert beneficiary has accepted
     * @param grantor The grantor address
     * @param beneficiary The beneficiary address
     */
    function assertBeneficiaryAccepted(address grantor, address beneficiary) internal view {
        assertTrue(factory.hasBeneficiaryAccepted(grantor, beneficiary), "Beneficiary should have accepted");
    }

    /**
     * @notice Assert beneficiary has not accepted
     * @param grantor The grantor address
     * @param beneficiary The beneficiary address
     */
    function assertBeneficiaryNotAccepted(address grantor, address beneficiary) internal view {
        assertFalse(factory.hasBeneficiaryAccepted(grantor, beneficiary), "Beneficiary should not have accepted");
    }
}

/**
 * @title MockBeneficiary
 * @notice Simple mock contract that can receive ETH and act as beneficiary
 */
contract MockBeneficiary {
    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
