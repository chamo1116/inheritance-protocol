// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract DigitalWill {
    // Contract state
    enum ContractState {
        ACTIVE,
        CLAIMABLE,
        COMPLETED
    }

    // State variables
    address public grantor;
    uint256 public lastCheckIn;
    ContractState public state;

    // Events
    event CheckIn(uint256 timestamp);
    event ContractDeployed(address grantor);

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
}
