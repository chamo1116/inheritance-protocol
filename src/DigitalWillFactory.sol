// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DigitalWillFactory is ReentrancyGuard, IERC721Receiver, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // Contract state
    enum ContractState {
        INACTIVE,
        ACTIVE,
        CLAIMABLE,
        COMPLETED
    }

    // Asset types supported
    enum AssetType {
        ETH,
        ERC20,
        ERC721
    }

    // Asset structure
    struct Asset {
        AssetType assetType;
        address tokenAddress;
        uint256 tokenId; // For ERC721
        uint256 amount; // For ERC20
        address beneficiary;
        bool claimed;
    }

    // Will structure
    struct Will {
        uint256 lastCheckIn;
        uint256 heartbeatInterval;
        ContractState state;
        Asset[] assets;
        uint256 unclaimedAssetsCount; // Track unclaimed assets to avoid loops
    }

    // Storage
    mapping(address => Will) private wills;

    // Mapping to track approved contract beneficiaries per grantor
    // grantor => beneficiary => approved
    mapping(address => mapping(address => bool)) private approvedContractBeneficiaries;

    // Mapping to track beneficiary acceptance status
    // grantor => beneficiary => accepted
    mapping(address => mapping(address => bool)) private beneficiaryAcceptance;

    // Mapping to track deposited ERC721 tokens to prevent duplicates
    // grantor => tokenAddress => tokenId => exists
    mapping(address => mapping(address => mapping(uint256 => bool))) private depositedERC721;

    // Constructor
    constructor() Ownable(msg.sender) {}

    // Events
    event WillCreated(address indexed grantor, uint256 heartbeatInterval);

    event CheckIn(address indexed grantor, uint256 timestamp);

    event AssetDeposited(
        address indexed grantor,
        AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        address indexed beneficiary
    );

    event AssetClaimed(
        address indexed grantor,
        address indexed beneficiary,
        uint256 assetIndex,
        AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    );

    event WillCompleted(address indexed grantor);

    event HeartbeatExtended(address indexed grantor, uint256 newInterval);

    event EmergencyWithdraw(address indexed grantor, uint256 assetsReturned);

    event ContractBeneficiaryApproved(address indexed grantor, address indexed beneficiary);

    event ContractBeneficiaryRevoked(address indexed grantor, address indexed beneficiary);

    event BeneficiaryUpdated(
        address indexed grantor, uint256 assetIndex, address oldBeneficiary, address newBeneficiary
    );

    event AssetRemoved(
        address indexed grantor,
        uint256 assetIndex,
        AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    );

    event HeartbeatModified(address indexed grantor, uint256 oldInterval, uint256 newInterval);

    event StateUpdated(address indexed grantor, ContractState newState, address indexed updater);

    event BeneficiaryAccepted(address indexed grantor, address indexed beneficiary);

    event BeneficiaryRejected(address indexed grantor, address indexed beneficiary);

    // Modifiers
    modifier willExists() {
        require(wills[msg.sender].state != ContractState.INACTIVE, "Will does not exist");
        _;
    }

    modifier willActive() {
        require(wills[msg.sender].state == ContractState.ACTIVE, "Will must be active");
        _;
    }

    modifier willNotCompleted(address grantor) {
        require(wills[grantor].state != ContractState.COMPLETED, "Will already completed");
        _;
    }

    // Public functions

    /**
     * ERC721 receiver implementation
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * Check if a will is claimable (heartbeat period expired)
     */
    function isClaimable(address grantor) public view returns (bool) {
        Will storage will = wills[grantor];
        return will.state == ContractState.CLAIMABLE
            || (will.state == ContractState.ACTIVE && block.timestamp >= will.lastCheckIn + will.heartbeatInterval);
    }

    /**
     * Update will state based on heartbeat
     * Only grantor or beneficiaries can update state to prevent DoS
     */
    function updateState(address grantor) public {
        // Access control: Only grantor or beneficiaries can update state
        require(msg.sender == grantor || _isBeneficiaryOf(msg.sender, grantor), "Unauthorized to update state");

        _updateState(grantor);
    }

    // External functions
    /**
     * Create a new will
     */
    function createWill(uint256 _heartbeatInterval) external whenNotPaused {
        require(wills[msg.sender].state == ContractState.INACTIVE, "Will already exists");
        require(_heartbeatInterval > 0, "Heartbeat interval must be greater than 0");

        Will storage newWill = wills[msg.sender];
        newWill.lastCheckIn = block.timestamp;
        newWill.heartbeatInterval = _heartbeatInterval;
        newWill.state = ContractState.ACTIVE;

        emit WillCreated(msg.sender, _heartbeatInterval);
    }

    /**
     * Check-in function to reset the inactivity timer
     */
    function checkIn() external whenNotPaused willExists willActive {
        Will storage will = wills[msg.sender];
        will.lastCheckIn = block.timestamp;

        emit CheckIn(msg.sender, block.timestamp);
    }

    /**
     * Deposit ETH function
     */
    function depositETH(address _beneficiary) external payable whenNotPaused willExists willActive {
        require(msg.value > 0, "Must send ETH");
        _validateBeneficiary(_beneficiary);

        Will storage will = wills[msg.sender];

        will.assets
            .push(
                Asset({
                    assetType: AssetType.ETH,
                    tokenAddress: address(0),
                    tokenId: 0,
                    amount: msg.value,
                    beneficiary: _beneficiary,
                    claimed: false
                })
            );

        will.unclaimedAssetsCount++;

        emit AssetDeposited(msg.sender, AssetType.ETH, address(0), 0, msg.value, _beneficiary);
    }

    /**
     * Fallback function to receive ETH
     */
    receive() external payable {
        revert("Use depositETH function");
    }

    /**
     * Deposit ERC20 tokens into the contract
     */
    function depositERC20(address _tokenAddress, uint256 _amount, address _beneficiary)
        external
        whenNotPaused
        willExists
        willActive
    {
        _validateTokenContract(_tokenAddress);
        require(_amount > 0, "Amount must be greater than 0");
        _validateBeneficiary(_beneficiary);

        IERC20 token = IERC20(_tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        Will storage will = wills[msg.sender];
        will.assets
            .push(
                Asset({
                    assetType: AssetType.ERC20,
                    tokenAddress: _tokenAddress,
                    tokenId: 0,
                    amount: _amount,
                    beneficiary: _beneficiary,
                    claimed: false
                })
            );

        will.unclaimedAssetsCount++;

        emit AssetDeposited(msg.sender, AssetType.ERC20, _tokenAddress, 0, _amount, _beneficiary);
    }

    /**
     * Deposit ERC721 tokens into the contract
     */
    function depositERC721(address _tokenAddress, uint256 _tokenId, address _beneficiary)
        external
        whenNotPaused
        willExists
        willActive
    {
        _validateTokenContract(_tokenAddress);
        _validateBeneficiary(_beneficiary);

        // Check for duplicate ERC721 deposit
        require(!depositedERC721[msg.sender][_tokenAddress][_tokenId], "This NFT has already been deposited");

        IERC721 nft = IERC721(_tokenAddress);
        require(nft.ownerOf(_tokenId) == msg.sender, "Not the owner of NFT");
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);

        // Mark this NFT as deposited
        depositedERC721[msg.sender][_tokenAddress][_tokenId] = true;

        Will storage will = wills[msg.sender];
        will.assets
            .push(
                Asset({
                    assetType: AssetType.ERC721,
                    tokenAddress: _tokenAddress,
                    tokenId: _tokenId,
                    amount: 1,
                    beneficiary: _beneficiary,
                    claimed: false
                })
            );

        will.unclaimedAssetsCount++;

        emit AssetDeposited(msg.sender, AssetType.ERC721, _tokenAddress, _tokenId, 1, _beneficiary);
    }

    /**
     * Claim a specific asset from a grantor's will
     * Requires beneficiary to have explicitly accepted their designation
     */
    function claimAsset(address grantor, uint256 _assetIndex)
        external
        whenNotPaused
        nonReentrant
        willNotCompleted(grantor)
    {
        _updateState(grantor);
        Will storage will = wills[grantor];
        require(will.state == ContractState.CLAIMABLE, "Will not yet claimable");

        Asset storage asset = will.assets[_assetIndex];
        require(asset.beneficiary == msg.sender, "Not the beneficiary");
        require(!asset.claimed, "Asset already claimed");
        require(beneficiaryAcceptance[grantor][msg.sender], "Beneficiary must accept designation first");

        _transferAsset(grantor, _assetIndex);
        _checkCompletion(grantor);
    }

    /**
     * Extend the heartbeat interval (only grantor) and must be longer than current
     */
    function extendHeartbeat(uint256 newInterval) external whenNotPaused willExists willActive {
        Will storage will = wills[msg.sender];
        require(newInterval > will.heartbeatInterval, "New interval must be longer");
        will.heartbeatInterval = newInterval;
        emit HeartbeatExtended(msg.sender, newInterval);
    }

    /**
     * Update beneficiary for a specific asset
     * Allows grantor to change beneficiary without withdrawing and re-depositing
     * Can only be done when will is ACTIVE (not CLAIMABLE or COMPLETED)
     */
    function updateBeneficiary(uint256 _assetIndex, address _newBeneficiary)
        external
        whenNotPaused
        willExists
        willActive
    {
        Will storage will = wills[msg.sender];
        require(_assetIndex < will.assets.length, "Asset index out of bounds");

        Asset storage asset = will.assets[_assetIndex];
        require(!asset.claimed, "Cannot update beneficiary for claimed asset");

        address oldBeneficiary = asset.beneficiary;
        require(oldBeneficiary != _newBeneficiary, "New beneficiary must be different");

        _validateBeneficiary(_newBeneficiary);

        asset.beneficiary = _newBeneficiary;

        emit BeneficiaryUpdated(msg.sender, _assetIndex, oldBeneficiary, _newBeneficiary);
    }

    /**
     * Remove a specific asset from the will and return it to grantor
     * Allows partial modifications without canceling entire will
     * Can only be done when will is ACTIVE (not CLAIMABLE or COMPLETED)
     */
    function removeAsset(uint256 _assetIndex) external nonReentrant whenNotPaused willExists willActive {
        Will storage will = wills[msg.sender];
        require(_assetIndex < will.assets.length, "Asset index out of bounds");

        Asset storage asset = will.assets[_assetIndex];
        require(!asset.claimed, "Asset already claimed");

        // Store asset details for event before modifying
        AssetType assetType = asset.assetType;
        address tokenAddress = asset.tokenAddress;
        uint256 tokenId = asset.tokenId;
        uint256 amount = asset.amount;

        // Transfer asset back to grantor
        if (asset.assetType == AssetType.ETH) {
            (bool success,) = payable(msg.sender).call{value: asset.amount}("");
            require(success, "ETH transfer failed");
        } else if (asset.assetType == AssetType.ERC20) {
            IERC20(asset.tokenAddress).safeTransfer(msg.sender, asset.amount);
        } else if (asset.assetType == AssetType.ERC721) {
            IERC721(asset.tokenAddress).safeTransferFrom(address(this), msg.sender, asset.tokenId);
            // Clear the deposited flag to allow re-deposit if needed
            depositedERC721[msg.sender][asset.tokenAddress][asset.tokenId] = false;
        }

        // Mark asset as claimed to prevent future claims
        asset.claimed = true;
        will.unclaimedAssetsCount--;

        emit AssetRemoved(msg.sender, _assetIndex, assetType, tokenAddress, tokenId, amount);
    }

    /**
     * Modify the heartbeat interval (only grantor)
     * More flexible than extendHeartbeat - allows both increase and decrease
     * Minimum interval is 1 day to prevent abuse
     * Can only be done when will is ACTIVE
     */
    function modifyHeartbeat(uint256 newInterval) external whenNotPaused willExists willActive {
        Will storage will = wills[msg.sender];
        uint256 oldInterval = will.heartbeatInterval;

        require(newInterval != oldInterval, "New interval must be different");
        require(newInterval >= 1 days, "Interval must be at least 1 day");

        will.heartbeatInterval = newInterval;

        // Reset lastCheckIn when reducing interval to give grantor fair time
        // This prevents immediate claimability when reducing the interval
        if (newInterval < oldInterval) {
            will.lastCheckIn = block.timestamp;
        }

        emit HeartbeatModified(msg.sender, oldInterval, newInterval);
    }

    /**
     * Emergency withdraw - allows grantor to reclaim all unclaimed assets
     * This cancels the will and returns all assets to the grantor
     * Uses counter-based optimization to avoid processing all assets when not needed
     * NOTE: Cannot be called once will becomes CLAIMABLE to prevent front-running beneficiary claims
     */
    function emergencyWithdraw() external nonReentrant willExists {
        Will storage will = wills[msg.sender];
        require(will.state != ContractState.COMPLETED, "Will already completed");
        require(will.state != ContractState.CLAIMABLE, "Cannot withdraw from claimable will");
        require(!isClaimable(msg.sender), "Will is claimable, cannot withdraw");

        uint256 assetsReturned = 0;
        uint256 assetsToReturn = will.unclaimedAssetsCount;

        // Loop through all assets and return unclaimed ones to grantor
        // Optimization: break early when all unclaimed assets have been returned
        for (uint256 i = 0; i < will.assets.length && assetsReturned < assetsToReturn; i++) {
            Asset storage asset = will.assets[i];

            // Skip already claimed assets
            if (asset.claimed) {
                continue;
            }

            // Transfer asset back to grantor based on type
            if (asset.assetType == AssetType.ETH) {
                (bool success,) = payable(msg.sender).call{value: asset.amount}("");
                require(success, "ETH transfer failed");
            } else if (asset.assetType == AssetType.ERC20) {
                IERC20(asset.tokenAddress).safeTransfer(msg.sender, asset.amount);
            } else if (asset.assetType == AssetType.ERC721) {
                IERC721(asset.tokenAddress).safeTransferFrom(address(this), msg.sender, asset.tokenId);
                // Clear the deposited flag to allow re-deposit if needed
                depositedERC721[msg.sender][asset.tokenAddress][asset.tokenId] = false;
            }

            // Mark asset as claimed and decrement counter
            asset.claimed = true;
            will.unclaimedAssetsCount--;
            assetsReturned++;
        }

        // Set will state to COMPLETED
        will.state = ContractState.COMPLETED;

        emit EmergencyWithdraw(msg.sender, assetsReturned);
    }

    /**
     * Get will information
     */
    function getWillInfo(address _grantor)
        external
        view
        returns (uint256 lastCheckIn, uint256 heartbeatInterval, ContractState state, uint256 assetCount)
    {
        Will storage will = wills[_grantor];
        return (will.lastCheckIn, will.heartbeatInterval, will.state, will.assets.length);
    }

    /**
     * Get total number of assets in a will
     */
    function getAssetCount(address _grantor) external view returns (uint256) {
        return wills[_grantor].assets.length;
    }

    /**
     * Get asset details
     */
    function getAsset(address _grantor, uint256 _assetIndex)
        external
        view
        returns (
            AssetType assetType,
            address tokenAddress,
            uint256 tokenId,
            uint256 amount,
            address beneficiary,
            bool claimed
        )
    {
        Asset storage asset = wills[_grantor].assets[_assetIndex];
        return (asset.assetType, asset.tokenAddress, asset.tokenId, asset.amount, asset.beneficiary, asset.claimed);
    }

    /**
     * Get assets for a specific beneficiary from a grantor's will
     * Iterates through all assets and returns indices where beneficiary matches
     */
    function getBeneficiaryAssets(address _grantor, address _beneficiary) external view returns (uint256[] memory) {
        Will storage will = wills[_grantor];
        uint256 assetCount = will.assets.length;

        // First pass: count matching assets
        uint256 matchCount = 0;
        for (uint256 i = 0; i < assetCount; i++) {
            if (will.assets[i].beneficiary == _beneficiary) {
                matchCount++;
            }
        }

        // Second pass: populate result array
        uint256[] memory result = new uint256[](matchCount);
        uint256 resultIndex = 0;
        for (uint256 i = 0; i < assetCount; i++) {
            if (will.assets[i].beneficiary == _beneficiary) {
                result[resultIndex] = i;
                resultIndex++;
            }
        }

        return result;
    }

    /**
     * Pause the contract (only owner)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * Unpause the contract (only owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * Approve a contract address as a beneficiary
     * This is required before assigning assets to contract addresses
     */
    function approveContractBeneficiary(address _beneficiary) external willExists {
        require(_beneficiary != address(0), "Invalid beneficiary address");
        require(_isContract(_beneficiary), "Address is not a contract");

        approvedContractBeneficiaries[msg.sender][_beneficiary] = true;
        emit ContractBeneficiaryApproved(msg.sender, _beneficiary);
    }

    /**
     * Revoke approval for a contract beneficiary
     */
    function revokeContractBeneficiary(address _beneficiary) external willExists {
        approvedContractBeneficiaries[msg.sender][_beneficiary] = false;
        emit ContractBeneficiaryRevoked(msg.sender, _beneficiary);
    }

    /**
     * Accept beneficiary designation for a grantor's will
     * Must be called by the beneficiary address itself
     * Protects against address prediction attacks and confirms beneficiary can receive assets
     */
    function acceptBeneficiary(address _grantor) external {
        require(wills[_grantor].state != ContractState.INACTIVE, "Will does not exist");
        require(_isBeneficiaryOf(msg.sender, _grantor), "Not designated as beneficiary");
        require(!beneficiaryAcceptance[_grantor][msg.sender], "Already accepted");

        beneficiaryAcceptance[_grantor][msg.sender] = true;
        emit BeneficiaryAccepted(_grantor, msg.sender);
    }

    /**
     * Reject beneficiary designation for a grantor's will
     * Allows beneficiaries to opt-out if they don't want the responsibility
     */
    function rejectBeneficiary(address _grantor) external {
        require(wills[_grantor].state != ContractState.INACTIVE, "Will does not exist");
        require(_isBeneficiaryOf(msg.sender, _grantor), "Not designated as beneficiary");

        beneficiaryAcceptance[_grantor][msg.sender] = false;
        emit BeneficiaryRejected(_grantor, msg.sender);
    }

    /**
     * Check if a beneficiary has accepted their designation
     */
    function hasBeneficiaryAccepted(address _grantor, address _beneficiary) external view returns (bool) {
        return beneficiaryAcceptance[_grantor][_beneficiary];
    }

    /**
     * Check if a beneficiary is approved (for contracts) or valid (for EOAs)
     */
    function isApprovedBeneficiary(address _grantor, address _beneficiary) external view returns (bool) {
        if (_isContract(_beneficiary)) {
            return approvedContractBeneficiaries[_grantor][_beneficiary];
        }
        return _beneficiary != address(0);
    }

    // Internal functions

    /**
     * Internal helper to update state without access control
     * Used by claimAsset and other internal functions
     */
    function _updateState(address grantor) internal {
        Will storage will = wills[grantor];

        if (will.state == ContractState.ACTIVE && isClaimable(grantor)) {
            will.state = ContractState.CLAIMABLE;
            emit StateUpdated(grantor, ContractState.CLAIMABLE, msg.sender);
        }
    }

    /**
     * Check if an address is a contract
     * NOTE: This check has a timing limitation - an address may become a contract after this check.
     * The beneficiary acceptance requirement mitigates this by requiring the address to actively
     * accept their designation, which prevents address prediction attacks.
     */
    function _isContract(address _account) internal view returns (bool) {
        // Check if the address has code
        uint256 size;
        assembly {
            size := extcodesize(_account)
        }
        return size > 0;
    }

    /**
     * Validate beneficiary address
     */
    function _validateBeneficiary(address _beneficiary) internal view {
        require(_beneficiary != address(0), "Invalid beneficiary address");

        // Check if beneficiary is a contract
        if (_isContract(_beneficiary)) {
            require(
                approvedContractBeneficiaries[msg.sender][_beneficiary],
                "Contract beneficiary not approved. Use approveContractBeneficiary first"
            );
        }
    }

    /**
     * Validate token contract address
     */
    function _validateTokenContract(address _tokenAddress) internal view {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_isContract(_tokenAddress), "Token address must be a contract");
    }

    /**
     * Check if an address is a beneficiary of any unclaimed asset for a grantor
     */
    function _isBeneficiaryOf(address account, address grantor) internal view returns (bool) {
        Will storage will = wills[grantor];
        for (uint256 i = 0; i < will.assets.length; i++) {
            if (will.assets[i].beneficiary == account && !will.assets[i].claimed) {
                return true;
            }
        }
        return false;
    }

    /**
     * Internal function to transfer an asset to beneficiary
     */
    function _transferAsset(address _grantor, uint256 _assetIndex) internal {
        Will storage will = wills[_grantor];
        Asset storage asset = will.assets[_assetIndex];

        if (asset.assetType == AssetType.ETH) {
            // Transfer ETH
            (bool success,) = payable(asset.beneficiary).call{value: asset.amount}("");
            require(success, "ETH transfer failed");
        } else if (asset.assetType == AssetType.ERC20) {
            // Transfer ERC20
            IERC20(asset.tokenAddress).safeTransfer(asset.beneficiary, asset.amount);
        } else if (asset.assetType == AssetType.ERC721) {
            // Transfer ERC721
            IERC721(asset.tokenAddress).safeTransferFrom(address(this), asset.beneficiary, asset.tokenId);
            // Clear the deposited flag to allow re-deposit if needed
            depositedERC721[_grantor][asset.tokenAddress][asset.tokenId] = false;
        }

        asset.claimed = true;
        will.unclaimedAssetsCount--;

        emit AssetClaimed(
            _grantor, asset.beneficiary, _assetIndex, asset.assetType, asset.tokenAddress, asset.tokenId, asset.amount
        );
    }

    /**
     * Internal function to check if will is completed
     */
    function _checkCompletion(address _grantor) internal {
        Will storage will = wills[_grantor];

        // Check if all assets have been claimed using the counter
        if (will.unclaimedAssetsCount == 0 && will.assets.length > 0) {
            will.state = ContractState.COMPLETED;
            emit WillCompleted(_grantor);
        }
    }
}
