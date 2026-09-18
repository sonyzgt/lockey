// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IBondingCurve} from "./interfaces/IBondingCurve.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IMigrationManager} from "./interfaces/IMigrationManager.sol";
import {BondingCurveMath} from "./libraries/BondingCurveMath.sol";

/// @title BondingCurve
/// @notice Constant-product AMM bonding curve for a single launched token.
///
/// ARCHITECTURE:
///   - One BondingCurve instance per launched token.
///   - Deployed by LaunchpadFactory.
///   - Stores virtual + real reserves on-chain as the single source of truth.
///   - Fees are forwarded to FeeManager on every trade.
///   - Graduation is triggered automatically when market cap target is reached.
///   - After graduation, buy() and sell() permanently revert.
///
/// SECURITY:
///   - ReentrancyGuard on all state-changing functions.
///   - CEI (Checks-Effects-Interactions) pattern throughout.
///   - SafeERC20 for all token transfers.
///   - All arithmetic via BondingCurveMath (safe, no overflow).
///   - Pausable by factory owner for emergency scenarios only.
///   - Graduation and migration each have a one-time flag.
///
/// DECIMALS NOTE:
///   - token decimals  = 18
///   - quote decimals  = 6 (USDC)
///   - virtual reserves are stored in their native decimals.
///   - Market cap is returned in quote decimals (1e6 USDC).
///   - Spot price is returned scaled by PRICE_PRECISION (1e18) but must be
///     interpreted relative to token/quote decimal difference.
contract BondingCurve is IBondingCurve, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using BondingCurveMath for uint256;

    // ─── Constants ────────────────────────────────────────────────────────────

    /// @dev Used to scale spot price for precision. 1e18 = WAD.
    uint256 public constant PRICE_PRECISION = 1e18;

    /// @dev Fee denominator. All fees expressed in basis points.
    uint256 public constant FEE_DENOMINATOR = 10_000;

    /// @dev Maximum allowed fee: 5% total.
    uint256 public constant MAX_FEE_BPS = 500;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error BondingCurve__AlreadyGraduated();
    error BondingCurve__NotGraduated();
    error BondingCurve__SlippageExceeded(uint256 got, uint256 minimum);
    error BondingCurve__DeadlineExpired(uint256 deadline, uint256 currentTime);
    error BondingCurve__ZeroAmount();
    error BondingCurve__InsufficientTokenReserve(uint256 available, uint256 requested);
    error BondingCurve__InsufficientQuoteReserve(uint256 available, uint256 requested);
    error BondingCurve__FeeTooHigh();
    error BondingCurve__Unauthorized();
    error BondingCurve__ZeroAddress();
    error BondingCurve__AlreadyInitialized();
    error BondingCurve__MigrationFailed();

    // ─── Events ───────────────────────────────────────────────────────────────

    event TokenBought(
        address indexed token,
        address indexed buyer,
        uint256 quoteAmountIn,
        uint256 tokensOut,
        uint256 creatorFee,
        uint256 protocolFee,
        uint256 newMarketCap,
        uint256 newPrice
    );

    event TokenSold(
        address indexed token,
        address indexed seller,
        uint256 tokensIn,
        uint256 quoteAmountOut,
        uint256 creatorFee,
        uint256 protocolFee,
        uint256 newMarketCap,
        uint256 newPrice
    );

    event Graduated(address indexed token, uint256 finalMarketCap, uint256 quoteAccumulated);

    event FeesAccrued(address indexed token, uint256 creatorFee, uint256 protocolFee);

    event SnipeTaxApplied(address indexed buyer, uint256 snipeTaxBps, uint256 snipeFeeAmount);

    // ─── Immutable State ──────────────────────────────────────────────────────

    /// @notice The launched ERC-20 token this curve serves.
    address public immutable override token;

    /// @notice The quote asset (e.g. USDC on Arc).
    address public immutable override quoteToken;

    /// @notice Address of the factory that deployed this curve.
    address public immutable factory;

    /// @notice Total token supply (fixed, used for market cap calculation).
    uint256 public immutable totalSupply;

    /// @notice Tokens allocated to this bonding curve (80% of totalSupply).
    uint256 public immutable bondingCurveAllocation;

    // Virtual reserves — set at initialization, never change.
    /// @notice Virtual quote reserve to establish non-zero initial price.
    uint256 public immutable virtualQuoteReserve;

    /// @notice Virtual token reserve to establish non-zero initial price.
    uint256 public immutable virtualTokenReserve;

    // Market cap targets (in quote token decimals, e.g. 5000 * 1e6 for $5K USDC).
    uint256 public immutable initialMarketCap;
    uint256 public immutable graduationMarketCap;

    // Fee configuration (in basis points).
    uint256 public immutable creatorFeeBps;
    uint256 public immutable protocolFeeBps;
    uint256 public immutable totalFeeBps;

    /// @notice Creator of the token (receives creator fees).
    address public immutable creator;

    /// @notice FeeManager contract address.
    address public immutable feeManager;

    /// @notice MigrationManager contract address.
    address public immutable migrationManager;

    /// @notice Timestamp when this bonding curve was launched.
    uint256 public immutable override launchedAt;

    /// @notice Snipe tax duration in seconds.
    uint256 public constant SNIPE_TAX_DURATION = 5;

    /// @notice Addresses exempt from snipe protection.
    mapping(address => bool) public isSnipeExempt;

    // ─── Mutable State ─────────────────────────────────────────────────────────

    /// @notice Real quote tokens accumulated in this curve from trades.
    uint256 public realQuoteReserve;

    /// @notice Real tokens remaining in this curve (starts at bondingCurveAllocation).
    uint256 public realTokenReserve;

    /// @notice Current status.
    Status public override status;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param token_                 Launched ERC-20 token address.
    /// @param quoteToken_            Quote asset (USDC).
    /// @param creator_               Token creator.
    /// @param feeManager_            FeeManager contract.
    /// @param migrationManager_      MigrationManager contract.
    /// @param virtualQuoteReserve_   Virtual quote reserve (e.g. 5365 * 1e6 for USDC).
    /// @param virtualTokenReserve_   Virtual token reserve (e.g. 1073000191 * 1e18).
    /// @param bondingCurveAllocation_ Token amount in this curve (80% of supply).
    /// @param totalSupply_           Total token supply.
    /// @param initialMarketCap_      Initial market cap target in quote decimals.
    /// @param graduationMarketCap_   Graduation market cap target in quote decimals.
    /// @param creatorFeeBps_         Creator fee in basis points.
    /// @param protocolFeeBps_        Protocol fee in basis points.
    constructor(
        address token_,
        address quoteToken_,
        address creator_,
        address feeManager_,
        address migrationManager_,
        uint256 virtualQuoteReserve_,
        uint256 virtualTokenReserve_,
        uint256 bondingCurveAllocation_,
        uint256 totalSupply_,
        uint256 initialMarketCap_,
        uint256 graduationMarketCap_,
        uint256 creatorFeeBps_,
        uint256 protocolFeeBps_
    ) {
        if (token_ == address(0)) revert BondingCurve__ZeroAddress();
        if (quoteToken_ == address(0)) revert BondingCurve__ZeroAddress();
        if (creator_ == address(0)) revert BondingCurve__ZeroAddress();
        if (feeManager_ == address(0)) revert BondingCurve__ZeroAddress();
        if (migrationManager_ == address(0)) revert BondingCurve__ZeroAddress();

        uint256 totalFee = creatorFeeBps_ + protocolFeeBps_;
        if (totalFee > MAX_FEE_BPS) revert BondingCurve__FeeTooHigh();

        token = token_;
        quoteToken = quoteToken_;
        creator = creator_;
        feeManager = feeManager_;
        migrationManager = migrationManager_;
        factory = msg.sender;

        virtualQuoteReserve = virtualQuoteReserve_;
        virtualTokenReserve = virtualTokenReserve_;
        bondingCurveAllocation = bondingCurveAllocation_;
        totalSupply = totalSupply_;
        initialMarketCap = initialMarketCap_;
        graduationMarketCap = graduationMarketCap_;
        creatorFeeBps = creatorFeeBps_;
        protocolFeeBps = protocolFeeBps_;
        totalFeeBps = totalFee;

        // Real reserves start at allocation (token) and zero (quote).
        realTokenReserve = bondingCurveAllocation_;
        realQuoteReserve = 0;

        launchedAt = block.timestamp;
        isSnipeExempt[creator_] = true;
        isSnipeExempt[msg.sender] = true;

        status = Status.BONDING;
    }

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyBonding() {
        if (status != Status.BONDING) revert BondingCurve__AlreadyGraduated();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert BondingCurve__Unauthorized();
        _;
    }

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) {
            revert BondingCurve__DeadlineExpired(deadline, block.timestamp);
        }
        _;
    }

    // ─── Read: Price & Market Data ────────────────────────────────────────────

    /// @inheritdoc IBondingCurve
    function getCurrentPrice() public view override returns (uint256 priceScaled) {
        (uint256 eqr, uint256 etr) = _effectiveReserves();
        // Price in quote/token, scaled by PRICE_PRECISION.
        // Because quote has 6 decimals and token has 18, we need to normalize:
        // priceScaled = eqr * PRICE_PRECISION * 1e18 / etr / 1e6
        //             = eqr * PRICE_PRECISION * 1e12 / etr
        // Result: how many quote units (6 decimals) per token unit (18 decimals),
        // scaled by 1e18. Caller divides by 1e18 to get USDC per token.
        priceScaled = (eqr * PRICE_PRECISION * 1e12) / etr;
    }

    /// @inheritdoc IBondingCurve
    function getMarketCap() public view override returns (uint256 marketCapInQuote) {
        (uint256 eqr, uint256 etr) = _effectiveReserves();
        // marketCap = price * totalSupply
        //           = (eqr / etr) * totalSupply     (in quote units)
        //           = eqr * totalSupply / etr
        // Both totalSupply and etr are in 1e18, so they cancel — result is in quote (1e6).
        marketCapInQuote = BondingCurveMath.getMarketCap(eqr, etr, totalSupply);
    }

    /// @inheritdoc IBondingCurve
    function getProgress() public view override returns (uint256 progressBps) {
        uint256 mc = getMarketCap();
        progressBps = BondingCurveMath.getProgressBps(mc, initialMarketCap, graduationMarketCap);
    }

    /// @inheritdoc IBondingCurve
    function getReserves() external view override returns (Reserves memory) {
        return Reserves({
            virtualQuoteReserve: virtualQuoteReserve,
            virtualTokenReserve: virtualTokenReserve,
            realQuoteReserve: realQuoteReserve,
            realTokenReserve: realTokenReserve
        });
    }

    // ─── Read: Quotes ─────────────────────────────────────────────────────────

    /// @inheritdoc IBondingCurve
    function currentSnipeTaxBps(address recipient) public view override returns (uint256) {
        if (isSnipeExempt[recipient]) return 0;
        if (block.timestamp >= launchedAt + SNIPE_TAX_DURATION) return 0;

        uint256 elapsed = block.timestamp - launchedAt;
        if (elapsed == 0) return 9900;
        if (elapsed == 1) return 2500;
        if (elapsed == 2) return 300;
        if (elapsed == 3) return 40;
        if (elapsed == 4) return 5;
        return 0;
    }

    /// @inheritdoc IBondingCurve
    function quoteBuyWithRecipient(uint256 quoteAmountIn, address recipient)
        public
        view
        override
        returns (BuyQuote memory q)
    {
        if (quoteAmountIn == 0) revert BondingCurve__ZeroAmount();

        uint256 snipeTax = currentSnipeTaxBps(recipient);
        if (snipeTax > 0) {
            uint256 maxSnipeBps = FEE_DENOMINATOR > (totalFeeBps + 100)
                ? (FEE_DENOMINATOR - totalFeeBps - 100)
                : 0;
            if (snipeTax > maxSnipeBps) {
                snipeTax = maxSnipeBps;
            }
        }

        uint256 totalEffectiveFeeBps = totalFeeBps + snipeTax;
        uint256 feeAmount = (quoteAmountIn * totalEffectiveFeeBps) / FEE_DENOMINATOR;
        uint256 amountInNet = quoteAmountIn - feeAmount;

        (uint256 eqr, uint256 etr) = _effectiveReserves();
        uint256 priceBefore = BondingCurveMath.getSpotPrice(eqr, etr, PRICE_PRECISION);

        uint256 tokensOut = BondingCurveMath.getBuyTokensOut(eqr, etr, amountInNet);

        // Effective reserves after trade
        uint256 eqrAfter = eqr + amountInNet;
        uint256 etrAfter = etr - tokensOut;
        uint256 priceAfter = BondingCurveMath.getSpotPrice(eqrAfter, etrAfter, PRICE_PRECISION);

        uint256 mcAfter = BondingCurveMath.getMarketCap(eqrAfter, etrAfter, totalSupply);

        q = BuyQuote({
            tokensOut: tokensOut,
            feeAmount: feeAmount,
            priceImpactBps: BondingCurveMath.getPriceImpactBps(priceBefore, priceAfter),
            newMarketCap: mcAfter
        });
    }

    /// @inheritdoc IBondingCurve
    function quoteBuy(uint256 quoteAmountIn) external view override returns (BuyQuote memory) {
        return quoteBuyWithRecipient(quoteAmountIn, address(0));
    }

    /// @inheritdoc IBondingCurve
    function quoteSell(uint256 tokenAmountIn) public view override returns (SellQuote memory q) {
        if (tokenAmountIn == 0) revert BondingCurve__ZeroAmount();

        (uint256 eqr, uint256 etr) = _effectiveReserves();
        uint256 priceBefore = BondingCurveMath.getSpotPrice(eqr, etr, PRICE_PRECISION);

        uint256 grossOut = BondingCurveMath.getSellQuoteOut(eqr, etr, tokenAmountIn);
        uint256 feeAmount = (grossOut * totalFeeBps) / FEE_DENOMINATOR;
        uint256 quoteOut = grossOut - feeAmount;

        uint256 eqrAfter = eqr - grossOut;
        uint256 etrAfter = etr + tokenAmountIn;
        uint256 priceAfter = BondingCurveMath.getSpotPrice(eqrAfter, etrAfter, PRICE_PRECISION);

        uint256 mcAfter = BondingCurveMath.getMarketCap(eqrAfter, etrAfter, totalSupply);

        q = SellQuote({
            quoteOut: quoteOut,
            feeAmount: feeAmount,
            priceImpactBps: BondingCurveMath.getPriceImpactBps(priceBefore, priceAfter),
            newMarketCap: mcAfter
        });
    }

    // ─── Write: Trading ───────────────────────────────────────────────────────

    /// @inheritdoc IBondingCurve
    function buy(uint256 quoteAmountIn, uint256 minTokensOut, uint256 deadline)
        external
        override
        returns (uint256 tokensOut)
    {
        return buyFor(quoteAmountIn, minTokensOut, deadline, msg.sender);
    }

    /// @inheritdoc IBondingCurve
    function buyFor(uint256 quoteAmountIn, uint256 minTokensOut, uint256 deadline, address recipient)
        public
        override
        nonReentrant
        whenNotPaused
        onlyBonding
        checkDeadline(deadline)
        returns (uint256 tokensOut)
    {
        if (quoteAmountIn == 0) revert BondingCurve__ZeroAmount();
        if (recipient == address(0)) revert BondingCurve__ZeroAddress();

        // ─── Checks ───────────────────────────────────────────────────────────

        // Compute snipe tax (if within decaying window and recipient not exempt)
        uint256 snipeTax = currentSnipeTaxBps(recipient);
        if (snipeTax > 0) {
            uint256 maxSnipeBps = FEE_DENOMINATOR > (totalFeeBps + 100)
                ? (FEE_DENOMINATOR - totalFeeBps - 100)
                : 0;
            if (snipeTax > maxSnipeBps) {
                snipeTax = maxSnipeBps;
            }
        }
        uint256 snipeFeeAmt = (quoteAmountIn * snipeTax) / FEE_DENOMINATOR;

        // Compute fee split
        uint256 regularFee = (quoteAmountIn * totalFeeBps) / FEE_DENOMINATOR;
        uint256 creatorFeeAmt = (quoteAmountIn * creatorFeeBps) / FEE_DENOMINATOR;
        uint256 protocolFeeAmt = (regularFee - creatorFeeAmt) + snipeFeeAmt;
        uint256 totalDeduction = regularFee + snipeFeeAmt;
        uint256 amountInNet = quoteAmountIn - totalDeduction;

        // Compute tokens out using current effective reserves
        (uint256 eqr, uint256 etr) = _effectiveReserves();
        tokensOut = BondingCurveMath.getBuyTokensOut(eqr, etr, amountInNet);

        // Slippage check
        if (tokensOut < minTokensOut) {
            revert BondingCurve__SlippageExceeded(tokensOut, minTokensOut);
        }
        // Liquidity check
        if (tokensOut > realTokenReserve) {
            revert BondingCurve__InsufficientTokenReserve(realTokenReserve, tokensOut);
        }

        // ─── Effects ──────────────────────────────────────────────────────────

        // Update real reserves (net amount joins the pool, fees are extracted separately)
        realQuoteReserve += amountInNet;
        realTokenReserve -= tokensOut;

        // ─── Interactions ─────────────────────────────────────────────────────

        // Pull quote from caller (full amount incl. fee)
        IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), quoteAmountIn);

        // Forward fees to FeeManager
        IERC20(quoteToken).safeTransfer(feeManager, totalDeduction);
        IFeeManager(feeManager).accrueCreatorFee(token, creatorFeeAmt);
        IFeeManager(feeManager).accrueProtocolFee(token, protocolFeeAmt);

        // Send tokens to recipient
        IERC20(token).safeTransfer(recipient, tokensOut);

        // Compute post-trade values for events
        uint256 newMc = getMarketCap();
        uint256 newPrice = getCurrentPrice();

        if (snipeFeeAmt > 0) {
            emit SnipeTaxApplied(recipient, snipeTax, snipeFeeAmt);
        }

        emit TokenBought(token, recipient, quoteAmountIn, tokensOut, creatorFeeAmt, protocolFeeAmt, newMc, newPrice);
        emit FeesAccrued(token, creatorFeeAmt, protocolFeeAmt);

        // ─── Graduation Check ─────────────────────────────────────────────────

        if (newMc >= graduationMarketCap) {
            _graduate();
        }
    }

    /// @inheritdoc IBondingCurve
    function sell(uint256 tokenAmountIn, uint256 minQuoteOut, uint256 deadline)
        external
        override
        nonReentrant
        whenNotPaused
        onlyBonding
        checkDeadline(deadline)
        returns (uint256 quoteOut)
    {
        if (tokenAmountIn == 0) revert BondingCurve__ZeroAmount();

        // ─── Checks ───────────────────────────────────────────────────────────

        (uint256 eqr, uint256 etr) = _effectiveReserves();

        // Gross quote out (before fee)
        uint256 grossOut = BondingCurveMath.getSellQuoteOut(eqr, etr, tokenAmountIn);

        // Fee applied to quote output
        uint256 totalFee = (grossOut * totalFeeBps) / FEE_DENOMINATOR;
        uint256 creatorFeeAmt = (grossOut * creatorFeeBps) / FEE_DENOMINATOR;
        uint256 protocolFeeAmt = totalFee - creatorFeeAmt;
        quoteOut = grossOut - totalFee;

        // Slippage check
        if (quoteOut < minQuoteOut) {
            revert BondingCurve__SlippageExceeded(quoteOut, minQuoteOut);
        }
        // Reserve sanity check
        if (grossOut > realQuoteReserve) {
            revert BondingCurve__InsufficientQuoteReserve(realQuoteReserve, grossOut);
        }

        // ─── Effects ──────────────────────────────────────────────────────────

        // Tokens return to curve, quote leaves
        realTokenReserve += tokenAmountIn;
        realQuoteReserve -= grossOut;

        // ─── Interactions ─────────────────────────────────────────────────────

        // Pull tokens from seller (must be approved)
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmountIn);

        // Forward fees to FeeManager
        IERC20(quoteToken).safeTransfer(feeManager, totalFee);
        IFeeManager(feeManager).accrueCreatorFee(token, creatorFeeAmt);
        IFeeManager(feeManager).accrueProtocolFee(token, protocolFeeAmt);

        // Send net quote to seller
        IERC20(quoteToken).safeTransfer(msg.sender, quoteOut);

        uint256 newMc = getMarketCap();
        uint256 newPrice = getCurrentPrice();

        emit TokenSold(token, msg.sender, tokenAmountIn, quoteOut, creatorFeeAmt, protocolFeeAmt, newMc, newPrice);
        emit FeesAccrued(token, creatorFeeAmt, protocolFeeAmt);
    }

    /// @inheritdoc IBondingCurve
    /// @notice Can be called by anyone once market cap >= graduation target.
    function graduate() external override nonReentrant whenNotPaused onlyBonding {
        uint256 mc = getMarketCap();
        if (mc < graduationMarketCap) {
            revert BondingCurve__NotGraduated();
        }
        _graduate();
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function pause() external onlyFactory {
        _pause();
    }

    function unpause() external onlyFactory {
        _unpause();
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    /// @dev Computes effective reserves used in AMM formula.
    function _effectiveReserves() internal view returns (uint256 eqr, uint256 etr) {
        eqr = virtualQuoteReserve + realQuoteReserve;
        etr = virtualTokenReserve - (bondingCurveAllocation - realTokenReserve);
        // etr = virtualTokenReserve - tokensSold
        // tokensSold = bondingCurveAllocation - realTokenReserve
    }

    /// @dev Internal graduation logic. Called after buy() detects MC threshold,
    ///      or via public graduate(). Protected by nonReentrant + onlyBonding.
    function _graduate() internal {
        // Mark as graduated first (prevents re-entry via onlyBonding modifier in buy/sell)
        status = Status.GRADUATED;

        uint256 quoteToMigrate = realQuoteReserve;
        uint256 tokenRemainingInCurve = realTokenReserve;

        // Zero out reserves — tokens and quote are being sent out
        realQuoteReserve = 0;
        realTokenReserve = 0;

        uint256 finalMc = getMarketCap();
        emit Graduated(token, finalMc, quoteToMigrate);

        // Transfer quote collected to MigrationManager
        if (quoteToMigrate > 0) {
            IERC20(quoteToken).safeTransfer(migrationManager, quoteToMigrate);
        }

        // Transfer ONLY the unsold bonding curve tokens to MigrationManager.
        // MigrationManager already holds the 20% migration reserve (sent by factory at creation).
        // Those unsold tokens will be locked to 0xdead inside migrate() — NOT added to the pool.
        //
        // NOTE: Do NOT use balanceOf(address(this)) here because:
        //   - balanceOf would include any tokens accidentally sent to this contract
        //   - tokenRemainingInCurve is the authoritative accounting source
        if (tokenRemainingInCurve > 0) {
            IERC20(token).safeTransfer(migrationManager, tokenRemainingInCurve);
        }

        // Trigger migration — MigrationManager will:
        //   1. Lock unsold tokens to 0xdead
        //   2. Combine migration reserve (20%) + USDC → Uniswap V4 pool
        //   3. Burn LP NFT to 0xdead (permanently locked)
        IMigrationManager(migrationManager).migrate(token, quoteToMigrate, tokenRemainingInCurve);
    }
}
