// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title BondingCurveMath
/// @notice Pure mathematical functions for the constant-product bonding curve.
///
/// MODEL: x * y = k
///   x = effectiveQuoteReserve  = virtualQuoteReserve + realQuoteReserve
///   y = effectiveTokenReserve  = virtualTokenReserve - tokensSold
///   k = constant (computed at initialization, never changes during bonding)
///
/// All token amounts use their native decimals (no additional scaling here).
/// The caller is responsible for passing correctly-scaled amounts.
///
/// ROUNDING CONVENTION:
///   - Amounts OUT (received by user): round DOWN (favor protocol).
///   - Amounts IN (paid by user):      round UP   (favor protocol).
///   This ensures the invariant k never decreases.
library BondingCurveMath {
    // ─── Errors ───────────────────────────────────────────────────────────────

    error BondingCurveMath__ZeroAmount();
    error BondingCurveMath__InsufficientLiquidity();
    error BondingCurveMath__Overflow();

    // ─── Buy ─────────────────────────────────────────────────────────────────

    /// @notice Calculate tokens received when spending `quoteIn` quote tokens.
    /// @param effectiveQuoteReserve  Virtual + real quote reserve.
    /// @param effectiveTokenReserve  Virtual token reserve - tokens already sold.
    /// @param quoteIn                Quote token amount in (NET, after fee deduction).
    /// @return tokensOut             Tokens the buyer receives (rounded down).
    function getBuyTokensOut(
        uint256 effectiveQuoteReserve,
        uint256 effectiveTokenReserve,
        uint256 quoteIn
    ) internal pure returns (uint256 tokensOut) {
        if (quoteIn == 0) revert BondingCurveMath__ZeroAmount();
        if (effectiveTokenReserve == 0) revert BondingCurveMath__InsufficientLiquidity();

        // tokensOut = effectiveTokenReserve * quoteIn / (effectiveQuoteReserve + quoteIn)
        // Use mulDiv pattern to avoid overflow: (a * b) / c
        // Safe because Solidity 0.8+ reverts on overflow, but let's be explicit.
        uint256 numerator = effectiveTokenReserve * quoteIn;
        uint256 denominator = effectiveQuoteReserve + quoteIn;

        // Overflow check: if effectiveTokenReserve * quoteIn overflows uint256
        // This is extremely unlikely for realistic values but we check anyway.
        unchecked {
            if (effectiveTokenReserve != 0 && numerator / effectiveTokenReserve != quoteIn) {
                revert BondingCurveMath__Overflow();
            }
        }

        tokensOut = numerator / denominator; // rounds down — user gets slightly less
    }

    // ─── Sell ─────────────────────────────────────────────────────────────────

    /// @notice Calculate quote received when selling `tokenIn` tokens.
    /// @param effectiveQuoteReserve  Virtual + real quote reserve.
    /// @param effectiveTokenReserve  Virtual token reserve - tokens already sold.
    /// @param tokenIn                Token amount in.
    /// @return quoteOut              Quote tokens the seller receives (rounded down).
    function getSellQuoteOut(
        uint256 effectiveQuoteReserve,
        uint256 effectiveTokenReserve,
        uint256 tokenIn
    ) internal pure returns (uint256 quoteOut) {
        if (tokenIn == 0) revert BondingCurveMath__ZeroAmount();
        if (effectiveQuoteReserve == 0) revert BondingCurveMath__InsufficientLiquidity();

        // quoteOut = effectiveQuoteReserve * tokenIn / (effectiveTokenReserve + tokenIn)
        uint256 numerator = effectiveQuoteReserve * tokenIn;
        uint256 denominator = effectiveTokenReserve + tokenIn;

        unchecked {
            if (effectiveQuoteReserve != 0 && numerator / effectiveQuoteReserve != tokenIn) {
                revert BondingCurveMath__Overflow();
            }
        }

        quoteOut = numerator / denominator; // rounds down — seller gets slightly less
    }

    // ─── Price ─────────────────────────────────────────────────────────────────

    /// @notice Spot price, scaled by `precision`.
    /// @dev    price = effectiveQuoteReserve * precision / effectiveTokenReserve
    ///         To get price in quote-per-token with 18 decimal precision, pass precision=1e18.
    ///         BUT reserves may have different decimals (e.g. quote=6, token=18),
    ///         so the caller must normalize the result externally.
    function getSpotPrice(
        uint256 effectiveQuoteReserve,
        uint256 effectiveTokenReserve,
        uint256 precision
    ) internal pure returns (uint256 priceScaled) {
        if (effectiveTokenReserve == 0) revert BondingCurveMath__InsufficientLiquidity();
        // Multiply first to maintain precision before dividing.
        priceScaled = (effectiveQuoteReserve * precision) / effectiveTokenReserve;
    }

    // ─── Price Impact ──────────────────────────────────────────────────────────

    /// @notice Computes price impact in basis points.
    /// @param priceBefore  Spot price before trade (scaled).
    /// @param priceAfter   Spot price after trade (scaled).
    /// @return impactBps   |delta| in basis points (always positive).
    function getPriceImpactBps(uint256 priceBefore, uint256 priceAfter)
        internal
        pure
        returns (uint256 impactBps)
    {
        if (priceBefore == 0) return 0;
        if (priceAfter >= priceBefore) {
            // Buy: price went up
            impactBps = ((priceAfter - priceBefore) * 10_000) / priceBefore;
        } else {
            // Sell: price went down
            impactBps = ((priceBefore - priceAfter) * 10_000) / priceBefore;
        }
    }

    // ─── Market Cap ───────────────────────────────────────────────────────────

    /// @notice Computes market cap = spotPrice * totalSupply.
    /// @dev    marketCap is returned in the same unit as effectiveQuoteReserve
    ///         but scaled by (totalSupply / effectiveTokenReserve).
    ///         Caller must interpret units correctly.
    ///
    ///         Formula:
    ///           spotPrice (in quote per token) = effectiveQuoteReserve / effectiveTokenReserve
    ///           marketCap = spotPrice * totalSupply
    ///                     = effectiveQuoteReserve * totalSupply / effectiveTokenReserve
    ///
    /// @param effectiveQuoteReserve  In quote decimals (e.g., 6 for USDC).
    /// @param effectiveTokenReserve  In token decimals (e.g., 1e18).
    /// @param totalSupply            Total token supply in token decimals (e.g., 1e18).
    /// @return marketCap             In quote decimals.
    function getMarketCap(
        uint256 effectiveQuoteReserve,
        uint256 effectiveTokenReserve,
        uint256 totalSupply
    ) internal pure returns (uint256 marketCap) {
        if (effectiveTokenReserve == 0) revert BondingCurveMath__InsufficientLiquidity();
        // Safe: effectiveQuoteReserve is in 1e6, totalSupply in 1e18.
        // effectiveTokenReserve is also in 1e18, so the 1e18 cancels out.
        // Result is in 1e6 (USDC).
        marketCap = (effectiveQuoteReserve * totalSupply) / effectiveTokenReserve;
    }

    // ─── Progress ─────────────────────────────────────────────────────────────

    /// @notice Returns graduation progress in basis points (0–10000).
    /// @param currentMarketCap     Current market cap in quote decimals.
    /// @param initialMarketCap     Market cap at launch in quote decimals.
    /// @param graduationMarketCap  Market cap target for graduation in quote decimals.
    function getProgressBps(
        uint256 currentMarketCap,
        uint256 initialMarketCap,
        uint256 graduationMarketCap
    ) internal pure returns (uint256 progressBps) {
        if (currentMarketCap <= initialMarketCap) return 0;
        if (currentMarketCap >= graduationMarketCap) return 10_000;
        uint256 range = graduationMarketCap - initialMarketCap;
        progressBps = ((currentMarketCap - initialMarketCap) * 10_000) / range;
    }

    // ─── Invariant Computation ─────────────────────────────────────────────────

    /// @notice Computes k = x * y for invariant validation.
    /// @dev    Used during initialization. Not called on every trade (too expensive).
    function computeK(uint256 x, uint256 y) internal pure returns (uint256 k) {
        // Check for overflow before computing
        if (x != 0 && y > type(uint256).max / x) revert BondingCurveMath__Overflow();
        k = x * y;
    }
}
