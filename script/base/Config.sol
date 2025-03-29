// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IVolatilityDataOracle} from "../../src/interfaces/IVolatilityDataOracle.sol";

// libraries
import {Currency} from "v4-core/src/types/Currency.sol";

/// @notice Shared configuration between scripts
contract Config {
    /// @dev populated with default anvil addresses
    IERC20 constant token0 = IERC20(address(0x0165878A594ca255338adfa4d48449f69242Eb8F));
    IERC20 constant token1 = IERC20(address(0xa513E6E4b8f2a923D98304ec87F64353C4D5C853));

    /// @dev Hook AdaptiveSwap Hook contract address
    /// @notice this is the address of the hook contract that will be linked to the pool
    IHooks constant hookContract = IHooks(address(0x0));

    /// @dev Volatility data oracle as an Eigenlayer Service Manager
    /// @notice this is the address of the oracle that will be used to retrieve the volatility data
    IVolatilityDataOracle constant volatilityOracle = IVolatilityDataOracle(0x36C02dA8a0983159322a80FFE9F24b1acfF8B570);

    Currency constant currency0 = Currency.wrap(address(token0));
    Currency constant currency1 = Currency.wrap(address(token1));
}
