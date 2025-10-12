// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DigitalWill is ReentrancyGuard {
    // Contract state
    enum ContractState {
        ACTIVE,
        CLAIMABLE,
        COMPLETED
    }

    // Asset types supported
    enum AssetType {
        ETH,
        ERC20,
        ERC721,
        ERC1155
    }

    // Asset structure
    struct Asset {
        AssetType assetType;
        address tokenAddress;
        uint256 tokenId; // For ERC721 and ERC1155
        uint256 amount; // For ERC20 and ERC1155
        address beneficiary;
        bool claimed;
    }

    // Contract metadata
    address public immutable grantor;
    uint256 public lastCheckIn;
    ContractState public state;
    uint256 public heartbeatInterval;

    // Assets management
    Asset[] public assets;
    mapping(address => uint256[]) public beneficiaryAssets;

    // Events
    event CheckIn(uint256 timestamp);

    event ContractDeployed(address grantor);

    event AssetDeposited(
        address indexed grantor,
        AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount,
        address beneficiary
    );

    event AssetClaimed(
        address indexed beneficiary,
        uint256 assetIndex,
        AssetType assetType,
        address tokenAddress,
        uint256 tokenId,
        uint256 amount
    );

    event ContractCompleted(address indexed grantor);

    event HeartbeatExtended(address indexed grantor, uint256 newInterval);

    // Modifiers
    modifier onlyGrantor() {
        require(msg.sender == grantor, "You are not the grantor");
        _;
    }

    modifier onlyWhenActive() {
        require(state == ContractState.ACTIVE, "Contract must be active");
        _;
    }

    modifier onlyWhenNotCompleted() {
        require(state != ContractState.COMPLETED, "Contract already completed");
        _;
    }

    constructor(uint256 _heartbeatInterval) {
        require(_heartbeatInterval > 0, "Heartbeat interval must be greater than 0");
        heartbeatInterval = _heartbeatInterval;
        grantor = msg.sender;
        state = ContractState.ACTIVE;
        lastCheckIn = block.timestamp;

        emit ContractDeployed(msg.sender);
    }

    // Public functions

    /**
     * Check if the contract is claimable (heartbeat period expired)
     */
    function isClaimable() public view returns (bool) {
        return state == ContractState.CLAIMABLE
            || (state == ContractState.ACTIVE && block.timestamp >= lastCheckIn + heartbeatInterval);
    }

    /**
     * Update contract state based on heartbeat
     */
    function updateState() public {
        if (state == ContractState.ACTIVE && isClaimable()) {
            state = ContractState.CLAIMABLE;
        }
    }

    // External functions

    /**
     * Check-in function to reset the inactivity timer
     */
    function checkIn() external onlyGrantor onlyWhenActive {
        lastCheckIn = block.timestamp;

        emit CheckIn(block.timestamp);
    }

    /**
     * Deposit ETH function
     */
    function depositETH(address _beneficiary) external payable onlyGrantor onlyWhenActive {
        require(msg.value > 0, "Must send ETH");

        // beneficiary cannot be the grantor
        require(_beneficiary != address(0), "Invalid beneficiary address");

        uint256 assetIndex = assets.length;

        assets.push(
            Asset({
                assetType: AssetType.ETH,
                tokenAddress: address(0),
                tokenId: 0,
                amount: msg.value,
                beneficiary: _beneficiary,
                claimed: false
            })
        );

        beneficiaryAssets[_beneficiary].push(assetIndex);

        emit AssetDeposited(msg.sender, AssetType.ETH, address(0), 0, msg.value, _beneficiary);
    }

    /**
     * Fallback function to receive ETH
     */
    receive() external payable {
        // ETH can only be deposited through depositETH function
        revert("Use depositETH function");
    }

    /**
     * Deposit ERC20 tokens into the contract
     */
    function depositERC20(address _tokenAddress, uint256 _amount, address _beneficiary)
        external
        onlyGrantor
        onlyWhenActive
    {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than 0");
        require(_beneficiary != address(0), "Invalid beneficiary address");

        IERC20 token = IERC20(_tokenAddress);
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        uint256 assetIndex = assets.length;
        assets.push(
            Asset({
                assetType: AssetType.ERC20,
                tokenAddress: _tokenAddress,
                tokenId: 0,
                amount: _amount,
                beneficiary: _beneficiary,
                claimed: false
            })
        );

        beneficiaryAssets[_beneficiary].push(assetIndex);

        emit AssetDeposited(msg.sender, AssetType.ERC20, _tokenAddress, 0, _amount, _beneficiary);
    }

    /**
     * Deposit ERC721 tokens into the contract
     */
    function depositERC721(address _tokenAddress, uint256 _tokenId, address _beneficiary)
        external
        onlyGrantor
        onlyWhenActive
    {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_beneficiary != address(0), "Invalid beneficiary address");

        IERC721 nft = IERC721(_tokenAddress);
        require(nft.ownerOf(_tokenId) == msg.sender, "Not the owner of NFT");
        nft.transferFrom(msg.sender, address(this), _tokenId);

        uint256 assetIndex = assets.length;
        assets.push(
            Asset({
                assetType: AssetType.ERC721,
                tokenAddress: _tokenAddress,
                tokenId: _tokenId,
                amount: 1,
                beneficiary: _beneficiary,
                claimed: false
            })
        );

        beneficiaryAssets[_beneficiary].push(assetIndex);

        emit AssetDeposited(msg.sender, AssetType.ERC721, _tokenAddress, _tokenId, 1, _beneficiary);
    }

    /**
     * Claim a specific asset
     */
    function claimSpecificAsset(uint256 _assetIndex) external nonReentrant onlyWhenNotCompleted {
        updateState();
        require(state == ContractState.CLAIMABLE, "Contract not yet claimable");

        Asset storage asset = assets[_assetIndex];
        require(asset.beneficiary == msg.sender, "Not the beneficiary");
        require(!asset.claimed, "Asset already claimed");

        _transferAsset(_assetIndex);
        _checkCompletion();
    }

    /**
     * Extend the heartbeat interval (only grantor) and most be longer than initial
     */
    function extendHeartbeat(uint256 newInterval) external onlyGrantor onlyWhenActive {
        require(newInterval > heartbeatInterval, "New interval must be longer");
        heartbeatInterval = newInterval;
        emit HeartbeatExtended(grantor, newInterval);
    }

    /**
     * Get total number of assets in the contract
     */
    function getAssetCount() external view returns (uint256) {
        return assets.length;
    }

    /**
     * Get assets for a specific beneficiary
     */
    function getBeneficiaryAssets(address beneficiary) external view returns (uint256[] memory) {
        return beneficiaryAssets[beneficiary];
    }

    // Internal functions

    /**
     * Internal function to transfer an asset to beneficiary
     */
    function _transferAsset(uint256 assetIndex) internal {
        Asset storage asset = assets[assetIndex];

        if (asset.assetType == AssetType.ETH) {
            // Transfer ETH
            payable(asset.beneficiary).transfer(asset.amount);
        } else if (asset.assetType == AssetType.ERC20) {
            // Transfer ERC20
            IERC20(asset.tokenAddress).transfer(asset.beneficiary, asset.amount);
        } else if (asset.assetType == AssetType.ERC721) {
            // Transfer ERC721
            IERC721(asset.tokenAddress).safeTransferFrom(address(this), asset.beneficiary, asset.tokenId);
        }

        asset.claimed = true;

        emit AssetClaimed(
            asset.beneficiary, assetIndex, asset.assetType, asset.tokenAddress, asset.tokenId, asset.amount
        );
    }

    /**
     * Internal function to check if contract is completed
     */
    function _checkCompletion() internal {
        bool allClaimed = true;
        for (uint256 i = 0; i < assets.length; i++) {
            if (!assets[i].claimed) {
                allClaimed = false;
                break;
            }
        }

        if (allClaimed) {
            state = ContractState.COMPLETED;
            emit ContractCompleted(grantor);
        }
    }
}
