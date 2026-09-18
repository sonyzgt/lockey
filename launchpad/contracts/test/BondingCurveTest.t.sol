// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import "./LaunchpadTestBase.t.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {IBondingCurve} from "../src/interfaces/IBondingCurve.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @title BondingCurveTest
/// @notice Integration tests for BondingCurve contract.
contract BondingCurveTest is LaunchpadTestBase {
    address token;
    address curve;
    BondingCurve bc;

    function setUp() public override {
        super.setUp();
        (token, curve) = _createToken();
        bc = BondingCurve(curve);
    }

    // ─── Initial State ────────────────────────────────────────────────────────

    function test_InitialState_Status() public {
        assertEq(uint8(bc.status()), uint8(IBondingCurve.Status.BONDING));
    }

    function test_InitialState_Price() public {
        uint256 price = bc.getCurrentPrice();
        assertGt(price, 0, "Initial price must be > 0");
        console2.log("Initial price (scaled 1e18):", price);
    }

    function test_InitialState_MarketCap_IsApprox5K() public {
        uint256 mc = bc.getMarketCap();
        console2.log("Initial MC (USDC 6dec):", mc);
        // Allow 1% tolerance around $5,000
        assertApproxEqRel(mc, INITIAL_MC, 1e16, "Initial MC should be ~$5,000");
    }

    function test_InitialState_Progress_IsZero() public {
        uint256 progress = bc.getProgress();
        assertEq(progress, 0, "Initial progress should be 0");
    }

    function test_InitialState_Reserves() public {
        IBondingCurve.Reserves memory r = bc.getReserves();
        assertEq(r.realTokenReserve, (TOTAL_SUPPLY * 8000) / 10000, "Real token reserve = bonding allocation");
        assertEq(r.realQuoteReserve, 0, "Real quote reserve = 0 initially");
        assertGt(r.virtualTokenReserve, 0, "Virtual token reserve must be set");
        assertGt(r.virtualQuoteReserve, 0, "Virtual quote reserve must be set");
    }

    // ─── Buy Tests ────────────────────────────────────────────────────────────

    function test_Buy_ReceivesTokens() public {
        uint256 usdcIn = 100 * 1e6; // $100
        uint256 balBefore = LaunchToken(token).balanceOf(trader1);

        uint256 tokensOut = _buy(trader1, curve, usdcIn);

        uint256 balAfter = LaunchToken(token).balanceOf(trader1);
        assertEq(balAfter - balBefore, tokensOut, "Received tokens must match tokensOut");
        assertGt(tokensOut, 0, "Must receive some tokens");
    }

    function test_Buy_QuoteTransferred() public {
        uint256 usdcIn = 500 * 1e6; // $500
        uint256 totalFee = (usdcIn * (CREATOR_FEE + PROTOCOL_FEE)) / 10_000; // 1%
        uint256 netIn = usdcIn - totalFee;

        uint256 fmBalBefore = usdc.balanceOf(address(feeManager));
        _buy(trader1, curve, usdcIn);
        uint256 fmBalAfter = usdc.balanceOf(address(feeManager));

        // FeeManager should have received totalFee
        assertEq(fmBalAfter - fmBalBefore, totalFee, "FeeManager must receive total fee");

        // Curve should have received net amount
        IBondingCurve.Reserves memory r = bc.getReserves();
        assertEq(r.realQuoteReserve, netIn, "Curve quote reserve must equal net amount");
    }

    function test_Buy_PriceIncreases() public {
        uint256 priceBefore = bc.getCurrentPrice();
        _buy(trader1, curve, 1000 * 1e6);
        uint256 priceAfter = bc.getCurrentPrice();
        assertGt(priceAfter, priceBefore, "Price must increase after buy");
    }

    function test_Buy_MarketCapIncreases() public {
        uint256 mcBefore = bc.getMarketCap();
        _buy(trader1, curve, 1000 * 1e6);
        uint256 mcAfter = bc.getMarketCap();
        assertGt(mcAfter, mcBefore, "MC must increase after buy");
    }

    function test_Buy_ProgressIncreases() public {
        uint256 progBefore = bc.getProgress();
        _buy(trader1, curve, 5000 * 1e6);
        uint256 progAfter = bc.getProgress();
        assertGt(progAfter, progBefore, "Progress must increase after buy");
    }

    function test_Buy_ZeroAmount_Reverts() public {
        vm.prank(trader1);
        usdc.approve(curve, 0);
        vm.expectRevert(BondingCurve.BondingCurve__ZeroAmount.selector);
        BondingCurve(curve).buy(0, 0, block.timestamp + 300);
    }

    function test_Buy_SlippageProtection() public {
        // Get quote first
        IBondingCurve.BuyQuote memory q = bc.quoteBuy(100 * 1e6);
        uint256 minOut = q.tokensOut + 1; // demand 1 more than quote

        vm.startPrank(trader1);
        usdc.approve(curve, 100 * 1e6);
        vm.expectRevert(); // SlippageExceeded
        BondingCurve(curve).buy(100 * 1e6, minOut, block.timestamp + 300);
        vm.stopPrank();
    }

    function test_Buy_DeadlineExpired_Reverts() public {
        vm.warp(1000); // set time to 1000
        vm.startPrank(trader1);
        usdc.approve(curve, 100 * 1e6);
        vm.expectRevert(); // DeadlineExpired
        BondingCurve(curve).buy(100 * 1e6, 0, 999); // deadline in past
        vm.stopPrank();
    }

    function test_Buy_QuoteFunction_Matches_Actual() public {
        uint256 usdcIn = 1000 * 1e6;
        IBondingCurve.BuyQuote memory q = bc.quoteBuy(usdcIn);

        uint256 actualOut = _buy(trader1, curve, usdcIn);
        assertEq(actualOut, q.tokensOut, "Actual out must match quote");
    }

    // ─── Sell Tests ───────────────────────────────────────────────────────────

    function test_Sell_ReceivesUSDC() public {
        // Buy first
        uint256 tokensOut = _buy(trader1, curve, 2000 * 1e6);

        // Sell half
        uint256 sellAmount = tokensOut / 2;
        uint256 usdcBefore = usdc.balanceOf(trader1);
        uint256 quoteOut = _sell(trader1, token, curve, sellAmount);
        uint256 usdcAfter = usdc.balanceOf(trader1);

        assertEq(usdcAfter - usdcBefore, quoteOut, "Received USDC must match quoteOut");
        assertGt(quoteOut, 0, "Must receive some USDC");
    }

    function test_Sell_PriceDecreases() public {
        _buy(trader1, curve, 5000 * 1e6);
        uint256 priceBefore = bc.getCurrentPrice();

        uint256 tokensToSell = LaunchToken(token).balanceOf(trader1) / 2;
        _sell(trader1, token, curve, tokensToSell);
        uint256 priceAfter = bc.getCurrentPrice();

        assertLt(priceAfter, priceBefore, "Price must decrease after sell");
    }

    function test_Sell_ZeroAmount_Reverts() public {
        vm.prank(trader1);
        vm.expectRevert(BondingCurve.BondingCurve__ZeroAmount.selector);
        BondingCurve(curve).sell(0, 0, block.timestamp + 300);
    }

    function test_Sell_SlippageProtection() public {
        uint256 tokensOut = _buy(trader1, curve, 1000 * 1e6);

        IBondingCurve.SellQuote memory q = bc.quoteSell(tokensOut / 2);
        uint256 minOut = q.quoteOut + 1; // demand 1 more than quote

        vm.startPrank(trader1);
        LaunchToken(token).approve(curve, tokensOut / 2);
        vm.expectRevert(); // SlippageExceeded
        BondingCurve(curve).sell(tokensOut / 2, minOut, block.timestamp + 300);
        vm.stopPrank();
    }

    function test_Sell_InsufficientBalance_Reverts() public {
        // trader1 has no tokens
        uint256 tooMany = 1_000_000 * 1e18;
        vm.startPrank(trader1);
        LaunchToken(token).approve(curve, tooMany);
        vm.expectRevert(); // insufficient balance or reserve
        BondingCurve(curve).sell(tooMany, 0, block.timestamp + 300);
        vm.stopPrank();
    }

    function test_Sell_QuoteFunction_Matches_Actual() public {
        uint256 tokensOut = _buy(trader1, curve, 3000 * 1e6);
        uint256 sellAmount = tokensOut / 2;

        IBondingCurve.SellQuote memory q = bc.quoteSell(sellAmount);
        uint256 actualQuote = _sell(trader1, token, curve, sellAmount);
        assertEq(actualQuote, q.quoteOut, "Actual quote must match quoteSell");
    }

    // ─── Reserve Accounting ───────────────────────────────────────────────────

    function test_Reserves_UpdatedCorrectly_AfterBuyAndSell() public {
        uint256 usdcIn = 2000 * 1e6;
        uint256 totalFee = (usdcIn * (CREATOR_FEE + PROTOCOL_FEE)) / 10_000;
        uint256 netIn = usdcIn - totalFee;

        uint256 tokensOut = _buy(trader1, curve, usdcIn);

        IBondingCurve.Reserves memory r = bc.getReserves();
        assertEq(r.realQuoteReserve, netIn, "Quote reserve after buy");
        assertEq(r.realTokenReserve, (TOTAL_SUPPLY * 8000 / 10000) - tokensOut, "Token reserve after buy");

        // Sell back some
        uint256 sellAmt = tokensOut / 2;
        uint256 grossOut = (r.realQuoteReserve + r.virtualQuoteReserve)
            * sellAmt
            / (r.virtualTokenReserve - (TOTAL_SUPPLY * 8000 / 10000 - r.realTokenReserve) + sellAmt);
        uint256 feeOnSell = (grossOut * (CREATOR_FEE + PROTOCOL_FEE)) / 10_000;
        uint256 netOut = grossOut - feeOnSell;

        _sell(trader1, token, curve, sellAmt);

        IBondingCurve.Reserves memory r2 = bc.getReserves();
        assertEq(r2.realTokenReserve, r.realTokenReserve + sellAmt, "Token reserve after sell");
        // Quote reserve reduced by grossOut (before fee)
        assertApproxEqAbs(r2.realQuoteReserve, r.realQuoteReserve - grossOut, 1, "Quote reserve after sell");
    }

    // ─── Pause Tests ─────────────────────────────────────────────────────────

    function test_Pause_BlocksBuySell() public {
        // Admin pauses curve
        vm.prank(admin);
        factory.pauseCurve(curve);

        vm.startPrank(trader1);
        usdc.approve(curve, 100 * 1e6);
        vm.expectRevert(); // Paused
        BondingCurve(curve).buy(100 * 1e6, 0, block.timestamp + 300);
        vm.stopPrank();
    }

    function test_Unpause_AllowsTrading() public {
        vm.prank(admin);
        factory.pauseCurve(curve);

        vm.prank(admin);
        factory.unpauseCurve(curve);

        _buy(trader1, curve, 100 * 1e6); // should not revert
    }

    // ─── Snipe Protection Tests ──────────────────────────────────────────────

    function test_SnipeProtection_DecaySchedule() public {
        // Deploy a fresh token right now
        (, address freshCurve) = _createTokenAtLaunch();
        BondingCurve freshBc = BondingCurve(freshCurve);
        uint256 launched = freshBc.launchedAt();

        // t = 0: 99% (9900 bps)
        assertEq(freshBc.currentSnipeTaxBps(trader1), 9900, "t=0 must be 99%");

        // t = 1: 25% (2500 bps)
        vm.warp(launched + 1);
        assertEq(freshBc.currentSnipeTaxBps(trader1), 2500, "t=1 must be 25%");

        // t = 2: 3% (300 bps)
        vm.warp(launched + 2);
        assertEq(freshBc.currentSnipeTaxBps(trader1), 300, "t=2 must be 3%");

        // t = 3: 0.4% (40 bps)
        vm.warp(launched + 3);
        assertEq(freshBc.currentSnipeTaxBps(trader1), 40, "t=3 must be 40 bps");

        // t = 4: 0.05% (5 bps)
        vm.warp(launched + 4);
        assertEq(freshBc.currentSnipeTaxBps(trader1), 5, "t=4 must be 5 bps");

        // t >= 5: 0%
        vm.warp(launched + 5);
        assertEq(freshBc.currentSnipeTaxBps(trader1), 0, "t=5 must be 0%");

        vm.warp(launched + 100);
        assertEq(freshBc.currentSnipeTaxBps(trader1), 0, "t=100 must be 0%");
    }

    function test_SnipeProtection_CreatorIsExempt() public {
        (, address freshCurve) = _createTokenAtLaunch();
        BondingCurve freshBc = BondingCurve(freshCurve);

        // Creator has 0 snipe tax even at t=0
        assertEq(freshBc.currentSnipeTaxBps(creator), 0, "Creator must be exempt at t=0");

        // Creator can buy at t=0 without snipe fee
        vm.startPrank(creator);
        usdc.approve(freshCurve, 100 * 1e6);
        uint256 tokens = freshBc.buy(100 * 1e6, 0, block.timestamp + 300);
        vm.stopPrank();
        assertGt(tokens, 0);
    }

    function test_SnipeProtection_SniperCharged99PercentAtT0() public {
        (address freshToken, address freshCurve) = _createTokenAtLaunch();
        BondingCurve freshBc = BondingCurve(freshCurve);

        uint256 usdcIn = 100 * 1e6; // $100

        uint256 fmBalBefore = usdc.balanceOf(address(feeManager));

        vm.startPrank(trader1);
        usdc.approve(freshCurve, usdcIn);
        uint256 tokensOut = freshBc.buy(usdcIn, 0, block.timestamp + 300);
        vm.stopPrank();

        uint256 fmBalAfter = usdc.balanceOf(address(feeManager));
        // Total deduction should be 99% ($99)
        uint256 totalDeduction = fmBalAfter - fmBalBefore;
        assertEq(totalDeduction, 99 * 1e6, "FeeManager must receive 99% snipe penalty + fees");

        // Buyer still successfully received tokens from the remaining 1% ($1)
        assertGt(tokensOut, 0, "Buyer must receive tokens from 1% net spend");
        assertEq(LaunchToken(freshToken).balanceOf(trader1), tokensOut);
    }

    function test_SnipeProtection_SellsNeverTaxedBySnipe() public {
        (address freshToken, address freshCurve) = _createTokenAtLaunch();
        BondingCurve freshBc = BondingCurve(freshCurve);

        // Creator buys tokens at t=0 (exempt)
        vm.startPrank(creator);
        usdc.approve(freshCurve, 100 * 1e6);
        uint256 tokens = freshBc.buy(100 * 1e6, 0, block.timestamp + 300);
        // Transfer to trader1
        LaunchToken(freshToken).transfer(trader1, tokens);
        vm.stopPrank();

        // Trader1 sells at t=0 (during snipe window)
        uint256 traderUsdcBefore = usdc.balanceOf(trader1);
        vm.startPrank(trader1);
        LaunchToken(freshToken).approve(freshCurve, tokens);
        uint256 usdcOut = freshBc.sell(tokens, 0, block.timestamp + 300);
        vm.stopPrank();

        // Sells should only pay normal 1% fee (no 99% snipe tax on sell)
        assertGt(usdcOut, 95 * 1e6, "Sell must not be penalized by 99% snipe tax");
        assertEq(usdc.balanceOf(trader1) - traderUsdcBefore, usdcOut);
    }
}
