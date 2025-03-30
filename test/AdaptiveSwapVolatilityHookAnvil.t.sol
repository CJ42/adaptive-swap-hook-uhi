// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// test lib
import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

// modules
import {PoolManager} from "v4-core/src/PoolManager.sol";

// libraries
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

// interfaces
import {IVolatilityDataOracle} from "../src/interfaces/IVolatilityDataOracle.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

// constants
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

// contract to test
import {AdaptiveSwapHook} from "../src/AdaptiveSwapHook.sol";

contract TestAdaptiveSwapHookAnvil is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    AdaptiveSwapHook hook;
    IVolatilityDataOracle volatilityOracle;

    function setUp() public {
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        deployMintAndApprove2Currencies();

        // Deploy our hook with the proper flags
        address hookAddress = address(uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG));

        // deploy our mock volatity oracle
        // TODO: to be replaced every time you re-deploy the oracle
        volatilityOracle = IVolatilityDataOracle(0x36C02dA8a0983159322a80FFE9F24b1acfF8B570);

        // deploy our hook
        deployCodeTo("AdaptiveSwapHook.sol", abi.encode(manager, volatilityOracle), hookAddress);
        hook = AdaptiveSwapHook(hookAddress);

        // Initialize a pool
        (key,) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_PRICE_1_1
        );

        // Add some liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_initialFee() public view {
        (,,, uint24 fee) = manager.getSlot0(key.toId());
        assertEq(fee, hook.REGULAR_VOLATILITY_FEE());
    }

    function test_overrideFeeBasedOnVolatility() public {
        // Set up our swap parameters
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.00001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // ==========================

        // Perform a swap
        uint256 balanceOfToken0Before = currency0.balanceOfSelf();
        uint256 balanceOfToken1Before = currency1.balanceOfSelf();

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 balanceOfToken0After = currency0.balanceOfSelf();
        uint256 balanceOfToken1After = currency1.balanceOfSelf();

        // Show the volatility data
        int256 latestVolatilityData = volatilityOracle.getLatestVolatilityData();
        console.log("Latest volatility data from test: ", latestVolatilityData);

        // Regular test
        // CHECK we obtained more token1
        assertGt(balanceOfToken1After, balanceOfToken1Before);

        // CHECK we have less token0
        assertLt(balanceOfToken0After, balanceOfToken0Before);
    }
}
