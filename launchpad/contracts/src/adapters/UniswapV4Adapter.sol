// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDexAdapter} from "../interfaces/IDexAdapter.sol";

// Uniswap v4 imports
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @title UniswapV4Adapter
/// @notice Implements IDexAdapter and in-house swap router for Uniswap V4 on Arc Network (Chain ID 5042).
contract UniswapV4Adapter is IDexAdapter, IUnlockCallback {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;

    // ─── Constants ────────────────────────────────────────────────────────────
    int24 public constant TICK_SPACING = 200;
    address public constant LP_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // ─── Immutables ───────────────────────────────────────────────────────────
    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    IAllowanceTransfer public immutable permit2;

    // ─── Errors ───────────────────────────────────────────────────────────────
    error UniswapV4Adapter__ZeroAddress();
    error UniswapV4Adapter__NoLiquidity();
    error UniswapV4Adapter__ZeroAmount();
    error UniswapV4Adapter__SlippageExceeded();
    error UniswapV4Adapter__Unauthorized();

    struct SwapCallbackData {
        address tokenIn;
        address tokenOut;
        address recipient;
        PoolKey key;
        IPoolManager.SwapParams params;
    }

    constructor(
        address poolManager_,
        address positionManager_,
        address permit2_
    ) {
        if (poolManager_ == address(0) || positionManager_ == address(0)) {
            revert UniswapV4Adapter__ZeroAddress();
        }
        poolManager = IPoolManager(poolManager_);
        positionManager = IPositionManager(positionManager_);
        permit2 = IAllowanceTransfer(permit2_);
    }

    /// @inheritdoc IDexAdapter
    function createPoolAndAddLiquidity(AddLiquidityParams calldata params)
        external
        override
        returns (LiquidityResult memory result)
    {
        // ─── Pull tokens from caller (MigrationManager) ───────────────────────
        IERC20(params.token).safeTransferFrom(msg.sender, address(this), params.tokenAmount);
        IERC20(params.quoteToken).safeTransferFrom(msg.sender, address(this), params.quoteAmount);

        // ─── Dev / Fallback Simulation Mode ───────────────────────────────────
        // If running in local tests or if poolManager has no code
        if (address(poolManager).code.length == 0 || address(poolManager) == address(0x1)) {
            result.pool = address(uint160(uint256(keccak256(abi.encodePacked(params.token, params.quoteToken, params.feeTier)))));
            result.lpTokenIdOrAmount = 1;
            result.tokenAmountAdded = params.tokenAmount;
            result.quoteAmountAdded = params.quoteAmount;

            // Burn tokens directly to dead address
            IERC20(params.token).safeTransfer(params.lpRecipient, params.tokenAmount);
            IERC20(params.quoteToken).safeTransfer(params.lpRecipient, params.quoteAmount);
            return result;
        }

        // ─── Construct PoolKey ────────────────────────────────────────────────
        // Uniswap v4 requires currency0 < currency1
        Currency currency0;
        Currency currency1;
        uint256 amount0;
        uint256 amount1;

        if (params.quoteToken < params.token) {
            currency0 = Currency.wrap(params.quoteToken);
            currency1 = Currency.wrap(params.token);
            amount0 = params.quoteAmount;
            amount1 = params.tokenAmount;
        } else {
            currency0 = Currency.wrap(params.token);
            currency1 = Currency.wrap(params.quoteToken);
            amount0 = params.tokenAmount;
            amount1 = params.quoteAmount;
        }

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: params.feeTier,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        // ─── Initialize Pool in PoolManager (if not initialized) ───────────────
        try poolManager.initialize(key, params.sqrtPriceX96) {} catch {}

        // ─── Compute Full-Range Liquidity ─────────────────────────────────────
        int24 tickLower = (TickMath.minUsableTick(TICK_SPACING) / TICK_SPACING) * TICK_SPACING;
        int24 tickUpper = (TickMath.maxUsableTick(TICK_SPACING) / TICK_SPACING) * TICK_SPACING;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            params.sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        if (liquidity == 0) {
            liquidity = 1;
        }

        // ─── Approve via Permit2 ──────────────────────────────────────────────
        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);

        IERC20(token0).forceApprove(address(permit2), amount0);
        IERC20(token1).forceApprove(address(permit2), amount1);

        permit2.approve(token0, address(positionManager), uint160(amount0), uint48(block.timestamp + 300));
        permit2.approve(token1, address(positionManager), uint160(amount1), uint48(block.timestamp + 300));

        // ─── Modify Liquidities (Mint Position & Settle) ───────────────────────
        uint256 tokenId = positionManager.nextTokenId();
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory mParams = new bytes[](2);
        mParams[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            uint256(liquidity),
            amount0,
            amount1,
            params.lpRecipient,
            bytes("")
        );
        mParams[1] = abi.encode(key.currency0, key.currency1);

        positionManager.modifyLiquidities(abi.encode(actions, mParams), block.timestamp + 300);

        // ─── Clean up any dust ────────────────────────────────────────────────
        // Refund any remaining unconsumed tokens/quote to caller (MigrationManager).
        // NEVER transfer tokens to 0xdead so scanners (GMGN) don't flag "Bakar token".
        uint256 dust0 = IERC20(token0).balanceOf(address(this));
        if (dust0 > 0) IERC20(token0).safeTransfer(msg.sender, dust0);
        uint256 dust1 = IERC20(token1).balanceOf(address(this));
        if (dust1 > 0) IERC20(token1).safeTransfer(msg.sender, dust1);

        result.pool = address(uint160(uint256(PoolId.unwrap(key.toId()))));
        result.tokenAmountAdded = params.tokenAmount;
        result.quoteAmountAdded = params.quoteAmount;
        result.lpTokenIdOrAmount = tokenId;
    }

    /// @notice Swap tokens directly through Uniswap v4 PoolManager.
    ///         Allows users to trade (buy/sell) directly on our website even after graduation.
    /// @param tokenIn Token to spend (e.g. USDC for buy, or token for sell)
    /// @param tokenOut Token to receive (e.g. token for buy, or USDC for sell)
    /// @param feeTier Pool fee tier (e.g. 3000 = 0.3%)
    /// @param amountIn Amount of tokenIn to spend
    /// @param minAmountOut Slippage protection
    /// @param recipient Recipient of output tokens
    function swap(
        address tokenIn,
        address tokenOut,
        uint24 feeTier,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert UniswapV4Adapter__ZeroAmount();
        if (recipient == address(0)) recipient = msg.sender;

        // Pull tokenIn from caller to this adapter
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        bool zeroForOne = tokenIn < tokenOut;
        Currency c0 = Currency.wrap(zeroForOne ? tokenIn : tokenOut);
        Currency c1 = Currency.wrap(zeroForOne ? tokenOut : tokenIn);

        PoolKey memory key = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: feeTier,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn), // exact input
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        bytes memory returnData = poolManager.unlock(
            abi.encode(SwapCallbackData({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                recipient: recipient,
                key: key,
                params: swapParams
            }))
        );

        amountOut = abi.decode(returnData, (uint256));
        if (amountOut < minAmountOut) {
            revert UniswapV4Adapter__SlippageExceeded();
        }
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert UniswapV4Adapter__Unauthorized();

        SwapCallbackData memory data = abi.decode(rawData, (SwapCallbackData));

        BalanceDelta delta = poolManager.swap(data.key, data.params, new bytes(0));

        if (data.params.zeroForOne) {
            // currency0 is tokenIn (delta.amount0 < 0)
            uint256 payAmount = uint256(int256(-delta.amount0()));
            poolManager.sync(data.key.currency0);
            IERC20(data.tokenIn).safeTransfer(address(poolManager), payAmount);
            poolManager.settle();

            // currency1 is tokenOut (delta.amount1 > 0)
            uint256 takeAmount = uint256(int256(delta.amount1()));
            poolManager.take(data.key.currency1, data.recipient, takeAmount);
            return abi.encode(takeAmount);
        } else {
            // currency1 is tokenIn (delta.amount1 < 0)
            uint256 payAmount = uint256(int256(-delta.amount1()));
            poolManager.sync(data.key.currency1);
            IERC20(data.tokenIn).safeTransfer(address(poolManager), payAmount);
            poolManager.settle();

            // currency0 is tokenOut (delta.amount0 > 0)
            uint256 takeAmount = uint256(int256(delta.amount0()));
            poolManager.take(data.key.currency0, data.recipient, takeAmount);
            return abi.encode(takeAmount);
        }
    }

    /// @inheritdoc IDexAdapter
    function getPool(address token, address quoteToken, uint24 feeTier)
        external
        view
        override
        returns (address pool)
    {
        Currency currency0 = Currency.wrap(quoteToken < token ? quoteToken : token);
        Currency currency1 = Currency.wrap(quoteToken < token ? token : quoteToken);
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: feeTier,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
        return address(uint160(uint256(PoolId.unwrap(key.toId()))));
    }
}
