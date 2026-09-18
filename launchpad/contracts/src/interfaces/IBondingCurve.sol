// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IBondingCurve
/// @notice Interface for the bonding curve AMM contract.
interface IBondingCurve {
    // ─── Enums ───────────────────────────────────────────────────────────────

    enum Status {
        BONDING,
        GRADUATED
    }

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct Reserves {
        uint256 virtualQuoteReserve;
        uint256 virtualTokenReserve;
        uint256 realQuoteReserve;
        uint256 realTokenReserve;
    }

    struct BuyQuote {
        uint256 tokensOut;
        uint256 feeAmount;
        uint256 priceImpactBps; // in basis points, e.g. 42 = 0.42%
        uint256 newMarketCap;
    }

    struct SellQuote {
        uint256 quoteOut;
        uint256 feeAmount;
        uint256 priceImpactBps;
        uint256 newMarketCap;
    }

    // ─── Read Functions ───────────────────────────────────────────────────────

    /// @notice Returns current spot price in quote tokens, scaled by PRICE_PRECISION (1e18).
    /// @dev price = (virtualQuote + realQuote) * PRICE_PRECISION / (virtualToken - tokensSold)
    function getCurrentPrice() external view returns (uint256 priceScaled);

    /// @notice Returns current market cap = spotPrice * totalSupply / PRICE_PRECISION.
    /// @dev In quote token units (USDC, 6 decimals).
    function getMarketCap() external view returns (uint256 marketCapInQuote);

    /// @notice Returns graduation progress in basis points (0–10000).
    function getProgress() external view returns (uint256 progressBps);

    /// @notice Returns all four reserve values.
    function getReserves() external view returns (Reserves memory);

    /// @notice Returns current decaying snipe tax in basis points for recipient.
    /// @param recipient The address receiving the tokens.
    function currentSnipeTaxBps(address recipient) external view returns (uint256);

    /// @notice Timestamp when this bonding curve was launched.
    function launchedAt() external view returns (uint256);

    /// @notice Returns a quote for buying `quoteAmountIn` of quote token for a specific recipient.
    /// @param quoteAmountIn Amount of quote token to spend (including fee and potential snipe tax).
    /// @param recipient The buyer / receiver address.
    function quoteBuyWithRecipient(uint256 quoteAmountIn, address recipient) external view returns (BuyQuote memory);

    /// @notice Returns a quote for buying `quoteAmountIn` of quote token.
    /// @param quoteAmountIn Amount of quote token to spend (including fee).
    function quoteBuy(uint256 quoteAmountIn) external view returns (BuyQuote memory);

    /// @notice Returns a quote for selling `tokenAmountIn` tokens.
    /// @param tokenAmountIn Amount of tokens to sell.
    function quoteSell(uint256 tokenAmountIn) external view returns (SellQuote memory);

    /// @notice Current status: BONDING or GRADUATED.
    function status() external view returns (Status);

    /// @notice Total token supply.
    function totalSupply() external view returns (uint256);

    /// @notice Target market cap for graduation (in quote decimals).
    function graduationMarketCap() external view returns (uint256);

    /// @notice The token this curve serves.
    function token() external view returns (address);

    /// @notice The quote asset (e.g. USDC).
    function quoteToken() external view returns (address);

    // ─── Write Functions ──────────────────────────────────────────────────────

    /// @notice Buy tokens with quote asset.
    /// @param quoteAmountIn  Amount of quote token to spend.
    /// @param minTokensOut   Minimum tokens to receive (slippage protection).
    /// @param deadline       Transaction deadline (unix timestamp).
    /// @return tokensOut     Actual tokens received.
    function buy(uint256 quoteAmountIn, uint256 minTokensOut, uint256 deadline)
        external
        returns (uint256 tokensOut);

    /// @notice Buy tokens with quote asset for a specified recipient.
    /// @param quoteAmountIn  Amount of quote token to spend.
    /// @param minTokensOut   Minimum tokens to receive (slippage protection).
    /// @param deadline       Transaction deadline (unix timestamp).
    /// @param recipient      Address to receive the bought tokens.
    /// @return tokensOut     Actual tokens received.
    function buyFor(uint256 quoteAmountIn, uint256 minTokensOut, uint256 deadline, address recipient)
        external
        returns (uint256 tokensOut);

    /// @notice Sell tokens for quote asset.
    /// @param tokenAmountIn  Amount of tokens to sell.
    /// @param minQuoteOut    Minimum quote token to receive (slippage protection).
    /// @param deadline       Transaction deadline (unix timestamp).
    /// @return quoteOut      Actual quote tokens received.
    function sell(uint256 tokenAmountIn, uint256 minQuoteOut, uint256 deadline)
        external
        returns (uint256 quoteOut);

    /// @notice Trigger graduation if conditions are met. Can be called by anyone.
    function graduate() external;
}
