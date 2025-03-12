// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";

// interfaces
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";

// modules
import {BaseHook} from "uniswap-hooks/src/base/BaseHook.sol";

// libraries
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDeltaLibrary, BeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

// constants
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

contract MyDynamicFeeHook is BaseHook {
    // Use CurrencyLibrary and BalanceDeltaLibrary
    // to add some helper functions over the Currency and BalanceDelta data types
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using LPFeeLibrary for uint24;

    /// @dev Oracle used to retrieve the current volatility of the pair
    IVolatilityOracle public immutable VOLATILITY_ORACLE;

    // Volatility thresholds
    uint256 public constant HIGH_VOLATILITY_TRIGGER = 150_000; // 15%
    uint256 public constant LOW_VOLATILITY_TRIGGER = 50_000; // 5%

    /// LP fee tiers based on volatility
    /// @notice the lp fee is represented in hundredths of a bip, so the max is 100%
    /// uint24 public constant MAX_LP_FEE = 1000000;
    uint24 public constant HIGH_VOLATILITY_FEE = 10_000; // 1%
    uint24 public constant REGULAR_VOLATILITY_FEE = 5_000; // 0.5%
    uint24 public constant LOW_VOLATILITY_FEE = 1_000; // 0.1%

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
    //
    // Example of fee values (to memorize):
    //
    // 1000000 = 100% ----> (1 million bps)
    //  100000 =  10% ----> (100 thousand bps)
    //   10000 =   1% ----> (10 thousand bps)
    //    5000 =   0.5% --> (5 thousand bps)

    error MustUseDynamicFee();

    constructor(IPoolManager _poolManager, IVolatilityOracle _volatilityOracle) BaseHook(_poolManager) {
        VOLATILITY_ORACLE = _volatilityOracle;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
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

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal pure override returns (bytes4) {
        // `.isDynamicFee()` function comes from `using LPFeeLibrary for uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        return this.beforeInitialize.selector;
    }

    // Set a regular fee outside of the Low and High volatility range (which adjust dynamically the fees).
    // This is set here otherwise the dynamic fee pool starts with a 0 fee.
    function _afterInitialize(address, PoolKey calldata poolKey, uint160, int24) internal override returns (bytes4) {
        poolManager.updateDynamicLPFee(poolKey, REGULAR_VOLATILITY_FEE);
        return this.afterInitialize.selector;
    }

    function _beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24 lpfee)
    {
        uint256 volatility = VOLATILITY_ORACLE.getVolatility();

        // Use an override fee by setting the 2nd highest bit of the uint24 (this 2nd bit MUST be set for the override to work).
        // This enables to override the fee on a per-swap basis.
        // If we wanted to generally update LP fee for a longer-term than per-swap basis, we would use `poolManager.updateDynamicLPFee(poolKey, adjustedFee)`​.
        // Override fees are also a more gas-efficient alternative to calling ‌`poolManager.updateDynamicLPFee(poolKey, adjustedFee)`​.
        if (volatility >= HIGH_VOLATILITY_TRIGGER) {
            lpfee = HIGH_VOLATILITY_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        } else if (volatility <= LOW_VOLATILITY_TRIGGER) {
            lpfee = LOW_VOLATILITY_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        } else {
            lpfee = REGULAR_VOLATILITY_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, lpfee);
    }

    // function _afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta delta, bytes calldata)
    //     internal
    //     pure
    //     override
    //     returns (bytes4, int128)
    // {
    //     return (this.afterSwap.selector, 0);
    // }
}
