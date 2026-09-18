// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDexAdapter
/// @notice Abstract interface for any DEX liquidity provider.
///         Implement this to support Uniswap V3, V2, or any other AMM on Arc.
interface IDexAdapter {
    struct AddLiquidityParams {
        address token;
        address quoteToken;
        uint256 tokenAmount;
        uint256 quoteAmount;
        /// @dev For Uniswap V3: fee tier (500, 3000, 10000).
        uint24 feeTier;
        /// @dev For Uniswap V3: sqrtPriceX96 for initial pool price.
        ///      For V2: ignored.
        uint160 sqrtPriceX96;
        /// @dev Recipient of LP tokens / NFT position.
        address lpRecipient;
        uint256 deadline;
    }

    struct LiquidityResult {
        address pool;
        uint256 tokenAmountAdded;
        uint256 quoteAmountAdded;
        /// @dev For V2: LP token amount. For V3: token ID of NFT position.
        uint256 lpTokenIdOrAmount;
    }

    /// @notice Creates a new pool (if it doesn't exist) and adds initial liquidity.
    /// @dev Must be approved for both token and quoteToken before calling.
    function createPoolAndAddLiquidity(AddLiquidityParams calldata params)
        external
        returns (LiquidityResult memory result);

    /// @notice Returns the pool address for a token pair, or address(0) if none.
    function getPool(address token, address quoteToken, uint24 feeTier)
        external
        view
        returns (address pool);
}
