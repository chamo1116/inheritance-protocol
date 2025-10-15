// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {DigitalWillFactory} from "../src/DigitalWillFactory.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is Script {
    function run() external returns (DigitalWillFactory) {
        // Get private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        DigitalWillFactory willFactory = new DigitalWillFactory();

        console.log("DigitalWillFactory deployed to:", address(willFactory));
        console.log("Deployer address:", vm.addr(deployerPrivateKey));

        vm.stopBroadcast();

        return willFactory;
    }
}
