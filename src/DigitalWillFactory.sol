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
        mapping(address => uint256[]) beneficiaryAssets;
    }

    // Storage
    mapping(address => Will) private wills;

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
     */
    function updateState(address grantor) public {
        Will storage will = wills[grantor];
        if (will.state == ContractState.ACTIVE && isClaimable(grantor)) {
            will.state = ContractState.CLAIMABLE;
        }
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
        require(_beneficiary != address(0), "Invalid beneficiary address");

        Will storage will = wills[msg.sender];
        uint256 assetIndex = will.assets.length;

        will.assets.push(
            Asset({
                assetType: AssetType.ETH,
                tokenAddress: address(0),
                tokenId: 0,
                amount: msg.value,
                beneficiary: _beneficiary,
                claimed: false
            })
        );

        will.beneficiaryAssets[_beneficiary].push(assetIndex);

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
        require(_tokenAddress != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than 0");
        require(_beneficiary != address(0), "Invalid beneficiary address");

        IERC20 token = IERC20(_tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        Will storage will = wills[msg.sender];
        uint256 assetIndex = will.assets.length;
        will.assets.push(
            Asset({
                assetType: AssetType.ERC20,
                tokenAddress: _tokenAddress,
                tokenId: 0,
                amount: _amount,
                beneficiary: _beneficiary,
                claimed: false
            })
        );

        will.beneficiaryAssets[_beneficiary].push(assetIndex);

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
        require(_tokenAddress != address(0), "Invalid token address");
        require(_beneficiary != address(0), "Invalid beneficiary address");

        IERC721 nft = IERC721(_tokenAddress);
        require(nft.ownerOf(_tokenId) == msg.sender, "Not the owner of NFT");
        nft.transferFrom(msg.sender, address(this), _tokenId);

        Will storage will = wills[msg.sender];
        uint256 assetIndex = will.assets.length;
        will.assets.push(
            Asset({
                assetType: AssetType.ERC721,
                tokenAddress: _tokenAddress,
                tokenId: _tokenId,
                amount: 1,
                beneficiary: _beneficiary,
                claimed: false
            })
        );

        will.beneficiaryAssets[_beneficiary].push(assetIndex);

        emit AssetDeposited(msg.sender, AssetType.ERC721, _tokenAddress, _tokenId, 1, _beneficiary);
    }

    /**
     * Claim a specific asset from a grantor's will
     */
    function claimAsset(address grantor, uint256 _assetIndex)
        external
        whenNotPaused
        nonReentrant
        willNotCompleted(grantor)
    {
        updateState(grantor);
        Will storage will = wills[grantor];
        require(will.state == ContractState.CLAIMABLE, "Will not yet claimable");

        Asset storage asset = will.assets[_assetIndex];
        require(asset.beneficiary == msg.sender, "Not the beneficiary");
        require(!asset.claimed, "Asset already claimed");

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
     */
    function getBeneficiaryAssets(address _grantor, address _beneficiary) external view returns (uint256[] memory) {
        return wills[_grantor].beneficiaryAssets[_beneficiary];
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

    // Internal functions

    /**
     * Internal function to transfer an asset to beneficiary
     */
    function _transferAsset(address grantor, uint256 assetIndex) internal {
        Will storage will = wills[grantor];
        Asset storage asset = will.assets[assetIndex];

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
        }

        asset.claimed = true;

        emit AssetClaimed(
            grantor, asset.beneficiary, assetIndex, asset.assetType, asset.tokenAddress, asset.tokenId, asset.amount
        );
    }

    /**
     * Internal function to check if will is completed
     */
    function _checkCompletion(address grantor) internal {
        Will storage will = wills[grantor];
        bool allClaimed = true;
        for (uint256 i = 0; i < will.assets.length; i++) {
            if (!will.assets[i].claimed) {
                allClaimed = false;
                break;
            }
        }

        if (allClaimed && will.assets.length > 0) {
            will.state = ContractState.COMPLETED;
            emit WillCompleted(grantor);
        }
    }
}
