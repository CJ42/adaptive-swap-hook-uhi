// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// std-lib
import {Script} from "forge-std/Script.sol";

// interfaces
import {IVolatilityDataOracle} from "../src/interfaces/IVolatilityDataOracle.sol";

// modules
import {AdaptiveSwapHook} from "../src/AdaptiveSwapHook.sol";

// libraries
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

// configs
import {Constants} from "./base/Constants.sol";
import {Config} from "./base/Config.sol";

contract DeployAdaptiveSwapHookScript is Script, Constants, Config {
    function run() external {
        vm.startBroadcast();

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER, volatilityOracle);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(AdaptiveSwapHook).creationCode, constructorArgs);

        // Deploy the hook using CREATE2 (passing the volatility oracle address previously deployed)
        AdaptiveSwapHook adaptiveSwap = new AdaptiveSwapHook{salt: salt}(POOLMANAGER, volatilityOracle);
        require(address(adaptiveSwap) == hookAddress, "AdaptiveSwap: hook address mismatch");

        vm.stopBroadcast();
    }
}
