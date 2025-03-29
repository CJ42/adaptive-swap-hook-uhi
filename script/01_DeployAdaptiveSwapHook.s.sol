// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {AdaptiveSwapHook} from "../src/AdaptiveSwapHook.sol";

import {Constants} from "./base/Constants.sol";
import {Config} from "./base/Config.sol";

contract DeployAdaptiveSwapHookScript is Script, Constants, Config {
    function run() external {
        vm.startBroadcast();

        // Deploy the AdaptiveSwapHook contract
        AdaptiveSwapHook adaptiveSwapHook = new AdaptiveSwapHook(POOLMANAGER, volatilityOracle);

        // Verify the contract on Etherscan
        vm.stopBroadcast();
    }
}
