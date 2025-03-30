// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";

// interfaces
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IVolatilityDataOracle} from "./interfaces/IVolatilityDataOracle.sol";

// modules
import {BaseHook} from "uniswap-hooks/src/base/BaseHook.sol";

// libraries
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDeltaLibrary, BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

// constants
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/**
 * @title Adaptive Swap Hook
 * @author Jean Cavallera
 */
contract AdaptiveSwapHook is BaseHook {
    // Helper functions for the `Currency` and `BalanceDelta` data types
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;

    /// @dev Oracle used to retrieve the short, medium and long terms volatility of the pair
    IVolatilityDataOracle public immutable VOLATILITY_ORACLE;

    /// Volatility thresholds (in bps, 1 bps = 0.01%)
    /// @dev The volatility is represented in bips (1/10000), so 1% = 100 bips
    uint256 public constant HIGH_VOLATILITY_TRIGGER = 125; // 1.25% weighted average
    uint256 public constant LOW_VOLATILITY_TRIGGER = 75; // 0.75% weighted average

    /// LP fee tiers based on the volatility
    /// @notice the lp fee is represented in hundredths of a bip
    /// - 1% = 10_000
    /// - 100% = 1_000_000
    uint24 public constant HIGH_VOLATILITY_FEE = 10_000; // 1%
    uint24 public constant REGULAR_VOLATILITY_FEE = 3_000; // 0.30%
    uint24 public constant LOW_VOLATILITY_FEE = 500; // 0.05%

    /// @dev Timestamp at which the fee were last updated
    uint256 public lastFeeUpdate;

    error MustUseDynamicFee();

    constructor(IPoolManager _poolManager, IVolatilityDataOracle _volatilityOracle) BaseHook(_poolManager) {
        VOLATILITY_ORACLE = _volatilityOracle;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _afterInitialize(address, /* sender */ PoolKey calldata key, uint160, /* sqrtPriceX96 */ int24 /* tick */ )
        internal
        virtual
        override
        returns (bytes4)
    {
        poolManager.updateDynamicLPFee(key, REGULAR_VOLATILITY_FEE);
        return this.afterInitialize.selector;
    }

    /// @dev Reduce drastic fee fluctations (for instance, when fee increase during short-term price spikes)
    /// using a weighted averages of volatility over different time frames (= 1 minute, 1 hour and 1 day).
    ///
    /// This hook function calculates this weighted average of volatility and adjust the fees accordingly.
    /// This protects liquidity providers from short-lived volatility, and offer "smooth fee adjustments" 🥤
    function _beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 overridenLpFee = getSwapFeeBasedOnWeightedVolatility() | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        lastFeeUpdate = block.timestamp;

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, overridenLpFee);
    }

    /// @dev Get the swap fee to be adjusted based on the price volatility of the asset
    function getSwapFeeBasedOnWeightedVolatility() public view returns (uint24) {
        // get volatility data
        uint256 currentVolatility = uint256(VOLATILITY_ORACLE.getLatestVolatilityData());
        console.log(unicode"🔍 Weighted average volatility retrieved: %s", currentVolatility);

        if (currentVolatility >= HIGH_VOLATILITY_TRIGGER) {
            console.log(unicode"📈 High volatility detected! Fee adjusted to: %s bps", HIGH_VOLATILITY_FEE);
            return HIGH_VOLATILITY_FEE;
        }

        if (currentVolatility <= LOW_VOLATILITY_TRIGGER) {
            console.log(unicode"📉 Low volatility detected! Fee adjusted to: %s bps", LOW_VOLATILITY_FEE);
            return LOW_VOLATILITY_FEE;
        }

        // Regular volatility
        console.log(unicode"🧘‍♂️ Regular volatility fee applied: %s bps", REGULAR_VOLATILITY_FEE);
        return REGULAR_VOLATILITY_FEE;
    }
}
