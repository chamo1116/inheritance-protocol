// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

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
}
