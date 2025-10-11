// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract DigitalWill {
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
    address public grantor;
    uint256 public lastCheckIn;
    ContractState public state;

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

    // Modifiers
    modifier onlyGrantor() {
        require(msg.sender == grantor, "You are not the grantor");
        _;
    }

    modifier onlyWhenActive() {
        require(state == ContractState.ACTIVE, "Contract must be active");
        _;
    }

    constructor() {
        grantor = msg.sender;
        state = ContractState.ACTIVE;
        lastCheckIn = block.timestamp;

        emit ContractDeployed(msg.sender);
    }

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
    function depositETH(address beneficiary_) external payable onlyGrantor onlyWhenActive {
        require(msg.value > 0, "Must send ETH");

        // beneficiary cannot be the grantor
        require(beneficiary_ != address(0), "Invalid beneficiary address");

        uint256 assetIndex = assets.length;

        assets.push(
            Asset({
                assetType: AssetType.ETH,
                tokenAddress: address(0),
                tokenId: 0,
                amount: msg.value,
                beneficiary: beneficiary_,
                claimed: false
            })
        );

        beneficiaryAssets[beneficiary_].push(assetIndex);

        emit AssetDeposited(msg.sender, AssetType.ETH, address(0), 0, msg.value, beneficiary_);
    }

    // Fallback function to receive ETH
    receive() external payable {
        // ETH can only be deposited through depositETH function
        revert("Use depositETH function");
    }

    /**
     * Deposit ERC721 tokens into the contract
     */
    function depositERC721(address tokenAddress_, uint256 tokenId_, address beneficiary_)
        external
        onlyGrantor
        onlyWhenActive
    {
        require(tokenAddress_ != address(0), "Invalid token address");
        require(beneficiary_ != address(0), "Invalid beneficiary address");

        IERC721 nft = IERC721(tokenAddress_);
        require(nft.ownerOf(tokenId_) == msg.sender, "Not the owner of NFT");
        nft.transferFrom(msg.sender, address(this), tokenId_);

        uint256 assetIndex = assets.length;
        assets.push(
            Asset({
                assetType: AssetType.ERC721,
                tokenAddress: tokenAddress_,
                tokenId: tokenId_,
                amount: 1,
                beneficiary: beneficiary_,
                claimed: false
            })
        );

        beneficiaryAssets[beneficiary_].push(assetIndex);

        emit AssetDeposited(msg.sender, AssetType.ERC721, tokenAddress_, tokenId_, 1, beneficiary_);
    }
}
