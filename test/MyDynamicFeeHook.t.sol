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
import {IVolatilityOracle} from "../src/IVolatilityOracle.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

// constants
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

// mocks
import {VolatilityOracleMock} from "./mocks/VolatilityOracleMock.m.sol";

// contract to test
import {MyDynamicFeeHook} from "../src/MyDynamicFeeHook.sol";

contract TestMyDynamicFeesHook is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    MyDynamicFeeHook hook;
    VolatilityOracleMock volatilityOracle;

    function setUp() public {
        // Deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        deployMintAndApprove2Currencies();

        // Deploy our hook with the proper flags
        address hookAddress =
            address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG));

        // deploy our mock volatity oracle
        volatilityOracle = new VolatilityOracleMock();

        // deploy our hook
        deployCodeTo("MyDynamicFeeHook.sol", abi.encode(manager, volatilityOracle), hookAddress);
        hook = MyDynamicFeeHook(hookAddress);

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
        // case of regular volatility
        // ==========================

        volatilityOracle.setRegularVolatility();
        assertEq(volatilityOracle.getVolatility(), 80_000);

        // Perform a swap
        uint256 balanceOfToken0Before = currency0.balanceOfSelf();
        uint256 balanceOfToken1Before = currency1.balanceOfSelf();

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 balanceOfToken0AfterRegular = currency0.balanceOfSelf();
        uint256 balanceOfToken1AfterRegular = currency1.balanceOfSelf();

        // Regular test
        // CHECK we obtained more token1
        assertGt(balanceOfToken1AfterRegular, balanceOfToken1Before);

        // CHECK we have less token0
        assertLt(balanceOfToken0AfterRegular, balanceOfToken0Before);

        // Fee is charged on the output token
        uint256 balanceDifferenceRegularVolatility = balanceOfToken1AfterRegular - balanceOfToken1Before;

        // =======================
        // case of high volatility
        // =======================

        volatilityOracle.setHighVolatility();
        assertEq(volatilityOracle.getVolatility(), 220_000);

        uint256 balanceOfToken1BeforeHighVolatility = currency1.balanceOfSelf();
        // Perform a swap
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        uint256 balanceOfToken1AfterHighVolatility = currency1.balanceOfSelf();

        uint256 balanceDifferenceHighVolatility =
            balanceOfToken1AfterHighVolatility - balanceOfToken1BeforeHighVolatility;

        // CHECK we received less token1 because the user paid higher fees on the output token due to high volatility
        assertLt(balanceDifferenceHighVolatility, balanceDifferenceRegularVolatility);

        // ==========================
        // case of low volatility
        // ==========================

        volatilityOracle.setLowVolatility();
        assertEq(volatilityOracle.getVolatility(), 30_000);

        uint256 balanceOfToken1BeforeLowVolatility = currency1.balanceOfSelf();
        // Perform a swap
        swapRouter.swap(key, params, testSettings, ZERO_BYTES);
        uint256 balanceOfToken1AfterLowVolatility = currency1.balanceOfSelf();

        uint256 balanceDifferenceLowVolatility = balanceOfToken1AfterLowVolatility - balanceOfToken1BeforeLowVolatility;

        // ---------------------------------------------------------------|
        // 57896044618658097711785492504343953926634992332820282019728492438460973741874
        // 57896044618658097711785492504343953926634992332820282019728492458460973741874

        // CHECK the user received more token1 with low volatility compared to:
        // - regular volatility
        assertGt(balanceDifferenceLowVolatility, balanceDifferenceRegularVolatility);
        // // - high volatility
        // assertLt(balanceDifferenceLowVolatility, balanceDifferenceHighVolatility);

        // because the user paid lower fees
    }
}
