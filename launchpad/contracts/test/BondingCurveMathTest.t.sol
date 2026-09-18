// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {BondingCurveMath} from "../src/libraries/BondingCurveMath.sol";

/// @notice Unit tests for BondingCurveMath library.
///         Tests pure mathematical correctness in isolation.
contract BondingCurveMathTest is Test {
    // ─── Fixtures ─────────────────────────────────────────────────────────────

    uint256 constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    uint256 constant BONDING_ALLOCATION = 800_000_000 * 1e18;
    uint256 constant VIRTUAL_TOKEN = 1_073_000_191 * 1e18;
    uint256 constant VIRTUAL_QUOTE = 5_365 * 1e6;
    uint256 constant INITIAL_MC   = 5_000 * 1e6;
    uint256 constant GRAD_MC      = 20_000 * 1e6;

    // ─── Helpers (external so try/catch works for library calls) ──────────────

    function callBuyZero() external {
        BondingCurveMath.getBuyTokensOut(VIRTUAL_QUOTE, VIRTUAL_TOKEN, 0);
    }

    function callSellZero() external {
        BondingCurveMath.getSellQuoteOut(VIRTUAL_QUOTE, VIRTUAL_TOKEN, 0);
    }

    // ─── Initial Price Tests ──────────────────────────────────────────────────

    function test_InitialSpotPrice() public {
        uint256 eqr = VIRTUAL_QUOTE;
        uint256 etr = VIRTUAL_TOKEN;
        uint256 price = BondingCurveMath.getSpotPrice(eqr, etr, 1e18);
        console2.log("Initial raw spot price (scaled 1e18):", price);
        assertGt(price, 0, "Price must be > 0");
    }

    function test_InitialMarketCap() public {
        uint256 eqr = VIRTUAL_QUOTE;
        uint256 etr = VIRTUAL_TOKEN;
        uint256 mc = BondingCurveMath.getMarketCap(eqr, etr, TOTAL_SUPPLY);
        console2.log("Initial market cap (USDC 6dec):", mc);
        assertApproxEqRel(mc, INITIAL_MC, 1e16, "Initial MC should be ~$5,000");
    }

    function test_InitialProgressIsZero() public {
        uint256 eqr = VIRTUAL_QUOTE;
        uint256 etr = VIRTUAL_TOKEN;
        uint256 mc = BondingCurveMath.getMarketCap(eqr, etr, TOTAL_SUPPLY);
        uint256 progress = BondingCurveMath.getProgressBps(mc, INITIAL_MC, GRAD_MC);
        assertEq(progress, 0, "Initial progress should be 0%");
    }

    // ─── Buy Tests ────────────────────────────────────────────────────────────

    function test_BuyTokensOut_SmallAmount() public {
        uint256 quoteIn = 100 * 1e6;
        uint256 eqr = VIRTUAL_QUOTE;
        uint256 etr = VIRTUAL_TOKEN;
        uint256 tokensOut = BondingCurveMath.getBuyTokensOut(eqr, etr, quoteIn);
        console2.log("Tokens out for $100 buy:", tokensOut / 1e18, "tokens (integer part)");
        assertGt(tokensOut, 0, "Should receive tokens");
        assertLt(tokensOut, etr, "Cannot receive more than reserve");
    }

    function test_BuyIncreasesPrice() public {
        uint256 eqr = VIRTUAL_QUOTE;
        uint256 etr = VIRTUAL_TOKEN;
        uint256 priceBefore = BondingCurveMath.getSpotPrice(eqr, etr, 1e18);
        uint256 quoteIn = 1000 * 1e6;
        uint256 tokensOut = BondingCurveMath.getBuyTokensOut(eqr, etr, quoteIn);
        uint256 eqrAfter = eqr + quoteIn;
        uint256 etrAfter = etr - tokensOut;
        uint256 priceAfter = BondingCurveMath.getSpotPrice(eqrAfter, etrAfter, 1e18);
        assertGt(priceAfter, priceBefore, "Price must increase after buy");
    }

    function test_BuyZeroAmountReverts() public {
        bool caught = false;
        try this.callBuyZero() { } catch { caught = true; }
        assertTrue(caught, "Zero amount buy should revert");
    }

    // ─── Sell Tests ───────────────────────────────────────────────────────────

    function test_SellQuoteOut_SmallAmount() public {
        uint256 quoteIn = 1000 * 1e6;
        uint256 eqr = VIRTUAL_QUOTE;
        uint256 etr = VIRTUAL_TOKEN;
        uint256 tokensBought = BondingCurveMath.getBuyTokensOut(eqr, etr, quoteIn);
        uint256 eqrAfter = eqr + quoteIn;
        uint256 etrAfter = etr - tokensBought;
        uint256 tokensToSell = tokensBought / 2;
        uint256 quoteOut = BondingCurveMath.getSellQuoteOut(eqrAfter, etrAfter, tokensToSell);
        console2.log("Sell quote out:", quoteOut);
        assertGt(quoteOut, 0, "Should receive quote");
        assertLt(quoteOut, quoteIn, "Should receive less than initial buy (no gain possible)");
    }

    function test_SellDecreasesPrice() public {
        uint256 quoteIn = 5000 * 1e6;
        uint256 eqr = VIRTUAL_QUOTE + quoteIn;
        uint256 tokensSold = BondingCurveMath.getBuyTokensOut(VIRTUAL_QUOTE, VIRTUAL_TOKEN, quoteIn);
        uint256 etr = VIRTUAL_TOKEN - tokensSold;
        uint256 priceBefore = BondingCurveMath.getSpotPrice(eqr, etr, 1e18);
        uint256 tokensToSell = tokensSold / 2;
        uint256 quoteBack = BondingCurveMath.getSellQuoteOut(eqr, etr, tokensToSell);
        uint256 eqrAfter = eqr - quoteBack;
        uint256 etrAfter = etr + tokensToSell;
        uint256 priceAfter = BondingCurveMath.getSpotPrice(eqrAfter, etrAfter, 1e18);
        assertLt(priceAfter, priceBefore, "Price must decrease after sell");
    }

    function test_SellZeroAmountReverts() public {
        bool caught = false;
        try this.callSellZero() { } catch { caught = true; }
        assertTrue(caught, "Zero amount sell should revert");
    }

    // ─── Invariant Tests ──────────────────────────────────────────────────────

    function test_InvariantHolds_AfterBuy() public {
        uint256 eqr = VIRTUAL_QUOTE;
        uint256 etr = VIRTUAL_TOKEN;
        uint256 k = BondingCurveMath.computeK(eqr, etr);
        uint256 quoteIn = 500 * 1e6;
        uint256 tokensOut = BondingCurveMath.getBuyTokensOut(eqr, etr, quoteIn);
        uint256 eqrAfter = eqr + quoteIn;
        uint256 etrAfter = etr - tokensOut;
        uint256 kAfter = eqrAfter * etrAfter;
        assertGe(kAfter, k, "k must not decrease after buy (rounding favors protocol)");
    }

    function test_InvariantHolds_AfterSell() public {
        uint256 eqr = VIRTUAL_QUOTE + 5000 * 1e6;
        uint256 etr = VIRTUAL_TOKEN - 1_000_000 * 1e18;
        uint256 k = eqr * etr;
        uint256 tokensIn = 500_000 * 1e18;
        uint256 quoteOut = BondingCurveMath.getSellQuoteOut(eqr, etr, tokensIn);
        uint256 eqrAfter = eqr - quoteOut;
        uint256 etrAfter = etr + tokensIn;
        uint256 kAfter = eqrAfter * etrAfter;
        assertGe(kAfter, k, "k must not decrease after sell (rounding favors protocol)");
    }

    // ─── Progress Tests ───────────────────────────────────────────────────────

    function test_Progress_AtHalfway() public {
        uint256 halfMc = 12_500 * 1e6;
        uint256 progress = BondingCurveMath.getProgressBps(halfMc, INITIAL_MC, GRAD_MC);
        assertApproxEqAbs(progress, 5000, 10, "Halfway progress should be 50% (5000 bps)");
    }

    function test_Progress_AtGraduation() public {
        uint256 progress = BondingCurveMath.getProgressBps(GRAD_MC, INITIAL_MC, GRAD_MC);
        assertEq(progress, 10_000, "At graduation, progress = 100% (10000 bps)");
    }

    function test_Progress_BelowInitial() public {
        uint256 progress = BondingCurveMath.getProgressBps(INITIAL_MC / 2, INITIAL_MC, GRAD_MC);
        assertEq(progress, 0, "Below initial MC, progress should clamp to 0");
    }

    function test_Progress_AboveGrad() public {
        uint256 progress = BondingCurveMath.getProgressBps(GRAD_MC * 2, INITIAL_MC, GRAD_MC);
        assertEq(progress, 10_000, "Above grad MC, progress should clamp to 100%");
    }

    // ─── Price Impact Tests ───────────────────────────────────────────────────

    function test_PriceImpact_IsPositiveForBuy() public {
        uint256 eqr = VIRTUAL_QUOTE;
        uint256 etr = VIRTUAL_TOKEN;
        uint256 priceBefore = BondingCurveMath.getSpotPrice(eqr, etr, 1e18);
        uint256 quoteIn = 1000 * 1e6;
        uint256 tokensOut = BondingCurveMath.getBuyTokensOut(eqr, etr, quoteIn);
        uint256 priceAfter = BondingCurveMath.getSpotPrice(eqr + quoteIn, etr - tokensOut, 1e18);
        uint256 impact = BondingCurveMath.getPriceImpactBps(priceBefore, priceAfter);
        assertGt(impact, 0, "Buy should have positive price impact");
        console2.log("Price impact for $1000 buy:", impact, "bps");
    }

    // ─── Market Cap Tests ─────────────────────────────────────────────────────

    function test_MarketCap_IncreasesAfterBuy() public {
        uint256 eqr = VIRTUAL_QUOTE;
        uint256 etr = VIRTUAL_TOKEN;
        uint256 mcBefore = BondingCurveMath.getMarketCap(eqr, etr, TOTAL_SUPPLY);
        uint256 quoteIn = 2000 * 1e6;
        uint256 tokensOut = BondingCurveMath.getBuyTokensOut(eqr, etr, quoteIn);
        uint256 mcAfter = BondingCurveMath.getMarketCap(eqr + quoteIn, etr - tokensOut, TOTAL_SUPPLY);
        assertGt(mcAfter, mcBefore, "MC must increase after buy");
    }

    function test_MarketCap_DecreaseAfterSell() public {
        uint256 eqr = VIRTUAL_QUOTE + 5000 * 1e6;
        uint256 tokensBought = BondingCurveMath.getBuyTokensOut(VIRTUAL_QUOTE, VIRTUAL_TOKEN, 5000 * 1e6);
        uint256 etr = VIRTUAL_TOKEN - tokensBought;
        uint256 mcBefore = BondingCurveMath.getMarketCap(eqr, etr, TOTAL_SUPPLY);
        uint256 tokensIn = tokensBought / 4;
        uint256 quoteOut = BondingCurveMath.getSellQuoteOut(eqr, etr, tokensIn);
        uint256 mcAfter = BondingCurveMath.getMarketCap(eqr - quoteOut, etr + tokensIn, TOTAL_SUPPLY);
        assertLt(mcAfter, mcBefore, "MC must decrease after sell");
    }
}
