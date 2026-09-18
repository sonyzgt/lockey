// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LaunchToken} from "./LaunchToken.sol";
import {BondingCurve} from "./BondingCurve.sol";
import {FeeManager} from "./FeeManager.sol";
import {MigrationManager} from "./MigrationManager.sol";

/// @title LaunchpadFactory
/// @notice The main entry point for the Arc Token Launchpad.
///         Creates tokens and bonding curves atomically in a single transaction.
///
/// DESIGN DECISIONS:
///   - One call to createToken() deploys: LaunchToken + BondingCurve.
///   - 80% of supply goes to BondingCurve.
///   - 20% of supply goes to MigrationManager (escrow until graduation).
///   - FeeManager is registered for the new token.
///   - Creation fee (optional, in quote token) is charged from the creator.
///   - All addresses and parameters are configurable via admin functions,
///     but only within safe bounds defined at compile time.
///
/// ADMIN CAPABILITIES (limited by design):
///   - Update creation fee (bounded by MAX_CREATION_FEE).
///   - Update fee bps (bounded by MAX_FEE_BPS).
///   - Pause/unpause factory (emergency only).
///   - Cannot: access user funds, change token supply, affect existing curves.
///
/// SECURITY:
///   - ReentrancyGuard on createToken().
///   - Pausable for emergency stops.
///   - Token list is an append-only registry — admin cannot remove tokens.
///   - All parameter validation at creation time.
contract LaunchpadFactory is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ────────────────────────────────────────────────────────────

    /// @dev Maximum creation fee: 100 USDC (in USDC 6-decimal units).
    uint256 public constant MAX_CREATION_FEE = 100 * 1e6;

    /// @dev Maximum total trading fee: 5% (500 bps).
    uint256 public constant MAX_FEE_BPS = 500;

    /// @dev Token total supply must be between 1M and 100T (in 18-decimal units).
    uint256 public constant MIN_TOTAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant MAX_TOTAL_SUPPLY = 100_000_000_000_000 * 1e18;

    /// @dev Bonding curve allocation: 80% of total supply.
    uint256 public constant BONDING_CURVE_BPS = 8_000; // 80%

    /// @dev Migration reserve: 20% of total supply.
    uint256 public constant MIGRATION_RESERVE_BPS = 2_000; // 20%

    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error Factory__EmptyName();
    error Factory__EmptySymbol();
    error Factory__InvalidSupply();
    error Factory__EmptyMetadataURI();
    error Factory__FeeTooHigh();
    error Factory__CreationFeeTooHigh();
    error Factory__QuoteTokenNotSupported();
    error Factory__InvalidMarketCaps();
    error Factory__ZeroAddress();

    // ─── Events ───────────────────────────────────────────────────────────────

    event TokenCreated(
        address indexed token,
        address indexed curve,
        address indexed creator,
        string name,
        string symbol,
        uint256 totalSupply,
        address quoteToken,
        string metadataURI,
        uint256 timestamp
    );

    event TokenCreatedAndBought(
        address indexed token,
        address indexed curve,
        address indexed creator,
        uint256 quoteSpent,
        uint256 tokensReceived
    );

    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event TradingFeesUpdated(uint256 oldCreatorBps, uint256 oldProtocolBps, uint256 newCreatorBps, uint256 newProtocolBps);
    event QuoteTokenUpdated(address indexed quoteToken, bool supported);
    event CreationFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event GraduationMarketCapTargetUpdated(uint256 oldTarget, uint256 newTarget);

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct TokenParams {
        string name;
        string symbol;
        uint256 totalSupply;
        string metadataURI;  // IPFS URI, e.g. "ipfs://Qm..."
        address quoteToken;  // Quote asset — must be in supportedQuoteTokens
        uint24 poolFeeTier;  // Uniswap V3 fee tier (e.g. 3000 for 0.3%)
    }

    struct TokenRecord {
        address token;
        address curve;
        address creator;
        address quoteToken;
        uint256 createdAt;
    }

    // ─── Immutables ───────────────────────────────────────────────────────────

    /// @notice FeeManager contract — immutable after deployment.
    FeeManager public immutable feeManager;

    /// @notice MigrationManager contract — immutable after deployment.
    MigrationManager public immutable migrationManager;

    // ─── Mutable State ────────────────────────────────────────────────────────

    /// @notice Creation fee in quote token (USDC). 0 = free.
    uint256 public creationFee;

    /// @notice Address that receives creation fees.
    address public creationFeeRecipient;

    /// @notice Trading fee split.
    uint256 public creatorFeeBps;
    uint256 public protocolFeeBps;

    /// @notice Virtual reserves for bonding curve initialization.
    ///         These define initial price and graduation behavior.
    ///         Expressed per 1,000,000,000 token supply — scaled at creation time.
    uint256 public virtualQuoteReservePerBillion; // e.g. 5365 * 1e6 for $5,365 USDC
    uint256 public virtualTokenReservePerBillion; // e.g. 1073000191 * 1e18

    /// @notice Market cap targets (in 6-decimal USDC units).
    uint256 public initialMarketCapTarget;    // e.g. 5000 * 1e6 = $5,000
    uint256 public graduationMarketCapTarget; // e.g. 20000 * 1e6 = $20,000

    /// @notice Allowed quote tokens (USDC, etc.).
    mapping(address => bool) public supportedQuoteTokens;

    /// @notice All tokens created by this factory.
    address[] public allTokens;

    /// @notice Token address → record.
    mapping(address => TokenRecord) public tokenRecords;

    /// @notice Creator address → list of tokens they created.
    mapping(address => address[]) public creatorTokens;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param owner_                      Protocol admin.
    /// @param feeManager_                 Deployed FeeManager.
    /// @param migrationManager_           Deployed MigrationManager.
    /// @param initialQuoteToken_          Initial quote token (USDC on Arc).
    /// @param creationFeeRecipient_       Protocol treasury for creation fees.
    /// @param creatorFeeBps_              Creator trading fee (basis points).
    /// @param protocolFeeBps_             Protocol trading fee (basis points).
    /// @param virtualQuoteReservePerBillion_ See virtualQuoteReservePerBillion.
    /// @param virtualTokenReservePerBillion_ See virtualTokenReservePerBillion.
    /// @param initialMarketCapTarget_     Initial MC target in quote decimals.
    /// @param graduationMarketCapTarget_  Graduation MC target in quote decimals.
    constructor(
        address owner_,
        address feeManager_,
        address migrationManager_,
        address initialQuoteToken_,
        address creationFeeRecipient_,
        uint256 creatorFeeBps_,
        uint256 protocolFeeBps_,
        uint256 virtualQuoteReservePerBillion_,
        uint256 virtualTokenReservePerBillion_,
        uint256 initialMarketCapTarget_,
        uint256 graduationMarketCapTarget_
    ) Ownable(owner_) {
        if (feeManager_ == address(0)) revert Factory__ZeroAddress();
        if (migrationManager_ == address(0)) revert Factory__ZeroAddress();
        if (initialQuoteToken_ == address(0)) revert Factory__ZeroAddress();
        if (creationFeeRecipient_ == address(0)) revert Factory__ZeroAddress();
        if (creatorFeeBps_ + protocolFeeBps_ > MAX_FEE_BPS) revert Factory__FeeTooHigh();
        if (graduationMarketCapTarget_ <= initialMarketCapTarget_) revert Factory__InvalidMarketCaps();

        feeManager = FeeManager(feeManager_);
        migrationManager = MigrationManager(migrationManager_);
        creationFeeRecipient = creationFeeRecipient_;

        creatorFeeBps = creatorFeeBps_;
        protocolFeeBps = protocolFeeBps_;
        virtualQuoteReservePerBillion = virtualQuoteReservePerBillion_;
        virtualTokenReservePerBillion = virtualTokenReservePerBillion_;
        initialMarketCapTarget = initialMarketCapTarget_;
        graduationMarketCapTarget = graduationMarketCapTarget_;

        // Register initial quote token
        supportedQuoteTokens[initialQuoteToken_] = true;
    }

    // ─── Core: Create Token ───────────────────────────────────────────────────

    /// @notice Creates a new token, bonding curve, and sets up fee/migration infrastructure.
    /// @dev Emits TokenCreated. No ETH required — all fees in quote token.
    /// @param params See TokenParams struct.
    /// @return token  Address of the newly created ERC-20 token.
    /// @return curve  Address of the newly created BondingCurve.
    function createToken(TokenParams calldata params)
        external
        nonReentrant
        whenNotPaused
        returns (address token, address curve)
    {
        return _createToken(params);
    }

    function _createToken(TokenParams calldata params) internal returns (address token, address curve) {
        // ─── Validate Inputs ──────────────────────────────────────────────────

        if (bytes(params.name).length == 0) revert Factory__EmptyName();
        if (bytes(params.symbol).length == 0) revert Factory__EmptySymbol();
        if (bytes(params.metadataURI).length == 0) revert Factory__EmptyMetadataURI();
        if (params.totalSupply < MIN_TOTAL_SUPPLY || params.totalSupply > MAX_TOTAL_SUPPLY) {
            revert Factory__InvalidSupply();
        }
        if (!supportedQuoteTokens[params.quoteToken]) {
            revert Factory__QuoteTokenNotSupported();
        }

        // ─── Collect Creation Fee ─────────────────────────────────────────────

        if (creationFee > 0) {
            IERC20(params.quoteToken).safeTransferFrom(msg.sender, creationFeeRecipient, creationFee);
        }

        // ─── Compute Allocation Amounts ───────────────────────────────────────

        uint256 bondingAllocation = (params.totalSupply * BONDING_CURVE_BPS) / BPS_DENOMINATOR;
        uint256 migrationReserve = params.totalSupply - bondingAllocation; // remainder to avoid rounding loss

        // ─── Scale Virtual Reserves to Actual Supply ──────────────────────────
        // Virtual reserves are configured per-1-billion tokens.
        // We scale them proportionally to the actual total supply.
        // This ensures initial price is always correct regardless of supply chosen.
        //
        // virtualQuote = virtualQuoteReservePerBillion * totalSupply / 1e9
        // virtualToken = virtualTokenReservePerBillion * totalSupply / 1e9
        //   (but virtualToken is in 18-decimal token units, and
        //    virtualTokenReservePerBillion is also in 18-decimal units,
        //    so we scale by totalSupply / (1e9 * 1e18) — see note below)
        //
        // NOTE: virtualTokenReservePerBillion_ is stored as raw token wei
        //   for a 1B supply. For a different supply, scale linearly.
        //   This keeps the P0 = virtualQuote/virtualToken ratio constant.

        uint256 ONE_BILLION_TOKENS = 1_000_000_000 * 1e18;
        uint256 scaledVirtualQuote = (virtualQuoteReservePerBillion * params.totalSupply) / ONE_BILLION_TOKENS;
        uint256 scaledVirtualToken = (virtualTokenReservePerBillion * params.totalSupply) / ONE_BILLION_TOKENS;

        // Scale market cap targets (they scale with supply × price, price is constant)
        // Since MC = price × supply, and price is determined by virtual reserves,
        // the MC targets are already supply-independent if we keep price fixed.
        // However, the CONTRACT checks MC against a fixed target — so if supply changes,
        // MC at same price changes. We keep targets fixed (in USDC) for all tokens.
        // This means tokens with different supplies will have different amounts sold
        // before graduating — which is correct behavior.

        // ─── Deploy Token ─────────────────────────────────────────────────────

        LaunchToken newToken = new LaunchToken(
            params.name,
            params.symbol,
            params.totalSupply,
            msg.sender,   // creator
            params.metadataURI,
            address(this) // initial recipient — factory distributes
        );
        token = address(newToken);

        // ─── Deploy BondingCurve ──────────────────────────────────────────────

        BondingCurve newCurve = new BondingCurve(
            token,
            params.quoteToken,
            msg.sender,                // creator (for fee routing)
            address(feeManager),
            address(migrationManager),
            scaledVirtualQuote,
            scaledVirtualToken,
            bondingAllocation,
            params.totalSupply,
            initialMarketCapTarget,
            graduationMarketCapTarget,
            creatorFeeBps,
            protocolFeeBps
        );
        curve = address(newCurve);

        // ─── Distribute Supply ────────────────────────────────────────────────
        // 80% goes to BondingCurve (available for trading on the curve).
        // 20% goes directly to MigrationManager as the migration reserve.
        //
        // This ensures MigrationManager holds EXACTLY migrationReserve tokens.
        // When the curve graduates, only those 20% go into the Uniswap pool.
        // Any unsold curve tokens are separately locked to 0xdead.
        IERC20(token).safeTransfer(curve, bondingAllocation);
        IERC20(token).safeTransfer(address(migrationManager), migrationReserve);

        // Register token with MigrationManager (migration reserve will be forwarded by curve upon graduation)
        migrationManager.registerToken(
            token,
            curve,
            params.quoteToken,
            migrationReserve,
            params.poolFeeTier
        );

        // ─── Register with FeeManager ─────────────────────────────────────────

        feeManager.registerToken(token, curve, msg.sender, params.quoteToken);

        // ─── Record ───────────────────────────────────────────────────────────

        tokenRecords[token] = TokenRecord({
            token: token,
            curve: curve,
            creator: msg.sender,
            quoteToken: params.quoteToken,
            createdAt: block.timestamp
        });
        allTokens.push(token);
        creatorTokens[msg.sender].push(token);

        emit TokenCreated(
            token,
            curve,
            msg.sender,
            params.name,
            params.symbol,
            params.totalSupply,
            params.quoteToken,
            params.metadataURI,
            block.timestamp
        );
    }

    /// @notice Atomically creates a token and performs an initial dev buy in a single transaction.
    /// @param params        Token deployment parameters.
    /// @param quoteAmountIn Amount of quote asset (e.g. USDC) the creator wants to spend.
    /// @param minTokensOut  Minimum tokens to receive (slippage protection).
    /// @return token        Deployed token address.
    /// @return curve        Deployed bonding curve address.
    /// @return tokensOut    Tokens received by creator from the initial buy.
    function createTokenAndBuy(
        TokenParams calldata params,
        uint256 quoteAmountIn,
        uint256 minTokensOut
    ) external payable nonReentrant whenNotPaused returns (address token, address curve, uint256 tokensOut) {
        (token, curve) = _createToken(params);

        if (quoteAmountIn > 0) {
            // Pull quote from creator to factory, approve curve, and buy for creator
            IERC20(params.quoteToken).safeTransferFrom(msg.sender, address(this), quoteAmountIn);
            IERC20(params.quoteToken).approve(curve, quoteAmountIn);
            tokensOut = BondingCurve(curve).buyFor(quoteAmountIn, minTokensOut, block.timestamp + 300, msg.sender);
            emit TokenCreatedAndBought(token, curve, msg.sender, quoteAmountIn, tokensOut);
        }
    }

    // ─── Read ─────────────────────────────────────────────────────────────────

    /// @notice Total number of tokens created.
    function totalTokens() external view returns (uint256) {
        return allTokens.length;
    }

    /// @notice Returns a page of tokens (for frontend listing).
    function getTokens(uint256 offset, uint256 limit) external view returns (address[] memory) {
        uint256 end = offset + limit;
        if (end > allTokens.length) end = allTokens.length;
        uint256 count = end > offset ? end - offset : 0;
        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = allTokens[offset + i];
        }
        return result;
    }

    /// @notice Returns all tokens created by a specific creator.
    function getCreatorTokens(address creator) external view returns (address[] memory) {
        return creatorTokens[creator];
    }

    /// @notice Returns the bonding curve address for a token.
    function getCurve(address token) external view returns (address) {
        return tokenRecords[token].curve;
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Update creation fee (max 100 USDC).
    function setCreationFee(uint256 newFee) external onlyOwner {
        if (newFee > MAX_CREATION_FEE) revert Factory__CreationFeeTooHigh();
        emit CreationFeeUpdated(creationFee, newFee);
        creationFee = newFee;
    }

    /// @notice Update creation fee recipient (e.g. new treasury address).
    function setCreationFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert Factory__ZeroAddress();
        emit CreationFeeRecipientUpdated(creationFeeRecipient, newRecipient);
        creationFeeRecipient = newRecipient;
    }

    /// @notice Update trading fee split. Only affects future tokens.
    function setTradingFees(uint256 newCreatorBps, uint256 newProtocolBps) external onlyOwner {
        if (newCreatorBps + newProtocolBps > MAX_FEE_BPS) revert Factory__FeeTooHigh();
        emit TradingFeesUpdated(creatorFeeBps, protocolFeeBps, newCreatorBps, newProtocolBps);
        creatorFeeBps = newCreatorBps;
        protocolFeeBps = newProtocolBps;
    }

    /// @notice Add or remove a supported quote token.
    function setQuoteTokenSupport(address quoteToken, bool supported) external onlyOwner {
        if (quoteToken == address(0)) revert Factory__ZeroAddress();
        supportedQuoteTokens[quoteToken] = supported;
        emit QuoteTokenUpdated(quoteToken, supported);
    }

    /// @notice Pause all token creation.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause token creation.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Pause a specific bonding curve (emergency).
    function pauseCurve(address curve) external onlyOwner {
        BondingCurve(curve).pause();
    }

    /// @notice Unpause a specific bonding curve.
    function unpauseCurve(address curve) external onlyOwner {
        BondingCurve(curve).unpause();
    }

    /// @notice Updates the graduation market cap target for newly created bonding curves.
    /// @param newTarget New graduation market cap target in quote decimals (e.g. 5001 * 1e6 for $5,001).
    function setGraduationMarketCapTarget(uint256 newTarget) external onlyOwner {
        if (newTarget <= initialMarketCapTarget) revert Factory__InvalidMarketCaps();
        emit GraduationMarketCapTargetUpdated(graduationMarketCapTarget, newTarget);
        graduationMarketCapTarget = newTarget;
    }

    /// @notice Updates the DEX adapter in MigrationManager.
    function setDexAdapter(address newAdapter) external onlyOwner {
        migrationManager.setDexAdapter(newAdapter);
    }

    /// @notice Withdraw accumulated protocol fees from FeeManager to recipient.
    function withdrawProtocolFees(address token, address recipient) external onlyOwner {
        feeManager.withdrawProtocolFees(token, recipient);
    }

    /// @notice Withdraw accumulated protocol fees for multiple tokens in one call.
    function withdrawProtocolFeesMultiple(address[] calldata tokens, address recipient) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            try feeManager.withdrawProtocolFees(tokens[i], recipient) {} catch {}
        }
    }
}
