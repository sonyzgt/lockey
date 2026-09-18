// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDexAdapter} from "../interfaces/IDexAdapter.sol";

// ─── Uniswap V3 Interfaces ────────────────────────────────────────────────────
// These are the minimal Uniswap V3 interfaces needed for pool creation and
// liquidity addition. In production, import from @uniswap/v3-core and
// @uniswap/v3-periphery packages.

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    struct MintReturn {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
    }

    function mint(MintParams calldata params)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

/// @title UniswapV3Adapter
/// @notice Implements IDexAdapter for Uniswap V3 on Arc.
///
/// USAGE:
///   1. Call createPoolAndAddLiquidity() with token pair and amounts.
///   2. If pool doesn't exist, it creates it and initializes price.
///   3. Adds full-range liquidity position.
///   4. LP NFT is sent to lpRecipient (burn address for production).
///
/// FULL-RANGE LIQUIDITY:
///   We add liquidity at the full range [MIN_TICK, MAX_TICK] for V3.
///   This is equivalent to Uniswap V2 behavior — all price ranges covered.
///   This maximizes simplicity and ensures liquidity is always available.
///
/// CONFIGURATION:
///   Set NEXT_PUBLIC_UNISWAP_V3_FACTORY, NEXT_PUBLIC_UNISWAP_V3_NFPM addresses
///   from official Uniswap documentation for Arc (Chain ID 5042).
///
/// NOTE ON ADDRESSES:
///   Do NOT hardcode addresses here. They are passed via constructor so
///   the deployer sets them from .env after verifying against official docs.
contract UniswapV3Adapter is IDexAdapter {
    using SafeERC20 for IERC20;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error UniswapV3Adapter__ZeroAddress();
    error UniswapV3Adapter__PoolCreationFailed();
    error UniswapV3Adapter__InvalidFeeTier();

    // ─── Constants ────────────────────────────────────────────────────────────

    /// @dev Uniswap V3 tick bounds for full-range liquidity.
    ///      tickSpacing = 60 for fee=3000 (0.3%), so we round to nearest multiple.
    ///      MIN_TICK for spacing 60 = -887220
    ///      MAX_TICK for spacing 60 = 887220
    int24 public constant MIN_TICK = -887220;
    int24 public constant MAX_TICK = 887220;

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice Uniswap V3 Factory on Arc.
    ///         Set from UNISWAP_V3_FACTORY env var.
    IUniswapV3Factory public immutable factory;

    /// @notice Uniswap V3 NonFungiblePositionManager on Arc.
    ///         Set from UNISWAP_V3_NFPM env var.
    INonfungiblePositionManager public immutable nfpm;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param factory_ Uniswap V3 Factory address on Arc.
    /// @param nfpm_    Uniswap V3 NonFungiblePositionManager address on Arc.
    constructor(address factory_, address nfpm_) {
        if (factory_ == address(0) || nfpm_ == address(0)) {
            revert UniswapV3Adapter__ZeroAddress();
        }
        factory = IUniswapV3Factory(factory_);
        nfpm = INonfungiblePositionManager(nfpm_);
    }

    // ─── IDexAdapter Implementation ───────────────────────────────────────────

    /// @inheritdoc IDexAdapter
    function createPoolAndAddLiquidity(AddLiquidityParams calldata params)
        external
        override
        returns (LiquidityResult memory result)
    {
        // ─── Sort tokens (Uniswap V3 requires token0 < token1 by address) ────

        address token0;
        address token1;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint160 sqrtPriceX96 = params.sqrtPriceX96;

        if (params.token < params.quoteToken) {
            token0 = params.token;
            token1 = params.quoteToken;
            amount0Desired = params.tokenAmount;
            amount1Desired = params.quoteAmount;
            // sqrtPriceX96 already computed for token0=launchToken, token1=quote
        } else {
            token0 = params.quoteToken;
            token1 = params.token;
            amount0Desired = params.quoteAmount;
            amount1Desired = params.tokenAmount;
            // Invert sqrtPriceX96: new_sqrt = 2^192 / old_sqrt
            if (sqrtPriceX96 != 0) {
                sqrtPriceX96 = uint160((1 << 192) / sqrtPriceX96);
            }
        }

        // ─── If simulated / dev mode (e.g. factory is 0x1 or has no deployed code) ───
        if (address(factory).code.length == 0 || address(factory) == address(0x1)) {
            result.pool = address(uint160(uint256(keccak256(abi.encodePacked(token0, token1, params.feeTier)))));
            result.lpTokenIdOrAmount = 1;
            result.tokenAmountAdded = params.tokenAmount;
            result.quoteAmountAdded = params.quoteAmount;

            // Safely lock liquidity to lpRecipient (burn address)
            IERC20(token0).safeTransferFrom(msg.sender, params.lpRecipient, amount0Desired);
            IERC20(token1).safeTransferFrom(msg.sender, params.lpRecipient, amount1Desired);
            return result;
        }

        // ─── Get or Create Pool ───────────────────────────────────────────────

        address pool = factory.getPool(token0, token1, params.feeTier);

        if (pool == address(0)) {
            // Create the pool
            pool = factory.createPool(token0, token1, params.feeTier);
            if (pool == address(0)) revert UniswapV3Adapter__PoolCreationFailed();

            // Initialize price
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        }

        result.pool = pool;

        // ─── Determine Tick Range ─────────────────────────────────────────────

        int24 tickSpacing = _getTickSpacing(params.feeTier);
        int24 tickLower = (MIN_TICK / tickSpacing) * tickSpacing;
        int24 tickUpper = (MAX_TICK / tickSpacing) * tickSpacing;

        // ─── Pull tokens from caller ──────────────────────────────────────────

        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0Desired);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1Desired);

        // ─── Approve NFPM ─────────────────────────────────────────────────────

        IERC20(token0).safeIncreaseAllowance(address(nfpm), amount0Desired);
        IERC20(token1).safeIncreaseAllowance(address(nfpm), amount1Desired);

        // ─── Mint Position ────────────────────────────────────────────────────

        (uint256 tokenId,, uint256 amount0Used, uint256 amount1Used) = nfpm.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: params.feeTier,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0, // MigrationManager handles slippage at a higher level
                amount1Min: 0,
                recipient: params.lpRecipient, // burn address or locker
                deadline: params.deadline
            })
        );

        // ─── Reset allowances (safety) ────────────────────────────────────────

        IERC20(token0).forceApprove(address(nfpm), 0);
        IERC20(token1).forceApprove(address(nfpm), 0);

        // ─── Return unused tokens to caller ──────────────────────────────────

        uint256 unused0 = amount0Desired - amount0Used;
        uint256 unused1 = amount1Desired - amount1Used;
        if (unused0 > 0) IERC20(token0).safeTransfer(msg.sender, unused0);
        if (unused1 > 0) IERC20(token1).safeTransfer(msg.sender, unused1);

        // ─── Build Result ─────────────────────────────────────────────────────

        if (params.token < params.quoteToken) {
            result.tokenAmountAdded = amount0Used;
            result.quoteAmountAdded = amount1Used;
        } else {
            result.tokenAmountAdded = amount1Used;
            result.quoteAmountAdded = amount0Used;
        }
        result.lpTokenIdOrAmount = tokenId;
    }

    /// @inheritdoc IDexAdapter
    function getPool(address tokenA, address tokenB, uint24 feeTier)
        external
        view
        override
        returns (address pool)
    {
        pool = factory.getPool(tokenA, tokenB, feeTier);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    /// @dev Returns tick spacing for a given Uniswap V3 fee tier.
    function _getTickSpacing(uint24 feeTier) internal pure returns (int24) {
        if (feeTier == 100) return 1;
        if (feeTier == 500) return 10;
        if (feeTier == 3000) return 60;
        if (feeTier == 10000) return 200;
        revert UniswapV3Adapter__InvalidFeeTier();
    }
}
