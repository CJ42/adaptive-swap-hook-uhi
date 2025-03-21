// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";

// interfaces
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IWeightedTimeBasedVolatilityOracle} from "./interfaces/IWeightedTimeBasedVolatilityOracle.sol";

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
 * @title WeightedTimeBasedVolatilityFeeHook
 * @author Jean Cavallera
 */
contract WeightedTimeBasedVolatilityFeeHook is BaseHook {
    // helper functions for the `Currency` and `BalanceDelta` data types
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;

    // Basis points to calculate percentages for the weighted average (1 % = 100 bps)
    // See: https://muens.io/solidity-percentages
    uint256 internal constant _BASIS_POINTS_BASE = 1_000_000; // 100 %

    /// @dev Oracle used to retrieve the short, medium and long terms volatility of the pair
    IWeightedTimeBasedVolatilityOracle public immutable VOLATILITY_ORACLE;

    // Table of fee tiers based on volatility.
    //
    // |-----------------------------------------------------|--------------------|
    // | Realized Volatility (in bps and %)                  | Fee (in bps and %) |
    // |-----------------------------------------------------|--------------------|
    // | >= 150,000 bps (greater than 15%)                   | 10,000 bps (= 1%)  |
    // |-----------------------------------------------------|--------------------|
    // | < 150,000 bps < x > 50,000 bps (between 5% and 15%) | 5,000 bps (= 0.5%) |
    // |-----------------------------------------------------|--------------------|
    // | <= 50,000 bps (less or equal to 5%)                 | 1,000 bps (= 0.1%) |
    // |-----------------------------------------------------|--------------------|

    // Volatility thresholds
    uint256 public constant HIGH_VOLATILITY_TRIGGER = 150_000; // 15%
    uint256 public constant LOW_VOLATILITY_TRIGGER = 50_000; // 5%

    /// LP fee tiers based on the weighted average volatility
    /// @notice the lp fee is represented in hundredths of a bip, so the max is 100%
    uint24 public constant HIGH_VOLATILITY_FEE = 10_000; // 1%
    uint24 public constant REGULAR_VOLATILITY_FEE = 5_000; // 0.5%
    uint24 public constant LOW_VOLATILITY_FEE = 1_000; // 0.1%

    /// @dev Timestamp at which the fee were last updated
    uint256 public lastFeeUpdate;

    error MustUseDynamicFee();

    constructor(IPoolManager _poolManager, IWeightedTimeBasedVolatilityOracle _volatilityOracle)
        BaseHook(_poolManager)
    {
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
        uint24 initialFee = getSwapFeeBasedOnWeightedVolatility();
        poolManager.updateDynamicLPFee(key, initialFee);
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

    /// dev Calculate the fee for the swap based on the volatility of the market.
    /// The volatility is based on a time average formula, not on the volatility at the time the swap is made
    /// This helps smoothen the swap fee paid overall, and reduce the risk of paying high fees when volatility surge in short time periods.
    /// See function `calculateWeightedTimeVolatility(...)` for more details
    function getSwapFeeBasedOnWeightedVolatility() public view returns (uint24) {
        // get volatility per day, minute and seconds
        (int256 volatilityMinute, int256 volatilityHour, int256 volatilityDay) = _getVolatilityMetrics();

        // calculate the weighted average of the volatility
        uint256 currentWeightedVolatility =
            _calculateWeightedTimeVolatility(volatilityMinute, volatilityHour, volatilityDay);

        if (currentWeightedVolatility >= HIGH_VOLATILITY_TRIGGER) {
            return HIGH_VOLATILITY_FEE;
        } else if (currentWeightedVolatility <= LOW_VOLATILITY_TRIGGER) {
            return LOW_VOLATILITY_FEE;
        } else {
            return REGULAR_VOLATILITY_FEE;
        }
    }

    /// @dev Query oracle for various volatility metrics on ETH - USD market
    /// For more details, see Chainlink oracle docs:
    /// - https://docs.chain.link/data-feeds/rates-feeds#realized-volatility
    /// - https://docs.chain.link/data-feeds/rates-feeds/addresses?network=ethereum&page=1
    function _getVolatilityMetrics() internal view returns (int256, int256, int256) {
        return (
            VOLATILITY_ORACLE.realizedVolatility24Hours(),
            VOLATILITY_ORACLE.realizedVolatility7Days(),
            VOLATILITY_ORACLE.realizedVolatility30Days()
        );
    }

    /// @dev Calculate weighted average volatility based on different time frames.
    // The volatility is weighted more heavily toward the short term (1-minute)
    // but also takes into account longer time frames to prevent overreaction to price spikes.
    function _calculateWeightedTimeVolatility(int256 volatilityMinute, int256 volatilityHour, int256 volatilityDay)
        internal
        pure
        returns (uint256)
    {
        // 50%
        uint256 weightedVolatilityMinute =
        // TODO: How to implement percentages on signed integers `intN`?
         FullMath.mulDiv({a: uint256(volatilityMinute), b: 5_000, denominator: _BASIS_POINTS_BASE});

        // 30%
        uint256 weightedVolatilityHour =
            FullMath.mulDiv({a: uint256(volatilityHour), b: 3_000, denominator: _BASIS_POINTS_BASE});

        // 20%
        uint256 weightedVolatilityDay =
            FullMath.mulDiv({a: uint256(volatilityDay), b: 2_000, denominator: _BASIS_POINTS_BASE});

        return weightedVolatilityMinute + weightedVolatilityHour + weightedVolatilityDay;
    }
}
