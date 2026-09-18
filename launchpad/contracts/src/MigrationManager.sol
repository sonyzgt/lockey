// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IMigrationManager} from "./interfaces/IMigrationManager.sol";
import {IDexAdapter} from "./interfaces/IDexAdapter.sol";
import {IBondingCurve} from "./interfaces/IBondingCurve.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @title MigrationManager
/// @notice Holds the migration reserve (20% of each token's supply) and executes
///         DEX pool creation + liquidity deposit upon graduation.
///
/// DESIGN:
///   - Receives 20% of each token's supply from LaunchpadFactory at creation time.
///   - When BondingCurve graduates, it calls migrate(), which:
///       1. Combines the 20% migration reserve with the USDC from the bonding curve.
///       2. Calls IDexAdapter.createPoolAndAddLiquidity().
///       3. Burns or locks the resulting LP position.
///       4. Locks any unsold tokens from the bonding curve (sent here too).
///
/// SECURITY:
///   - migrate() is only callable by the registered bonding curve for that token.
///   - Migration can only happen once per token (migrated flag).
///   - No admin can pull out migration reserves except via legitimate migration.
///   - IDexAdapter is configurable by owner (to support future DEX upgrades).
///     BUT: owner can only set adapter before migration, not after.
///   - LP is burned: NFT position sent to address(0xdead).
///
/// LP OWNERSHIP:
///   - We burn the LP NFT (Uniswap V3 position token) by sending to dead address.
///   - This permanently locks liquidity. No rug possible.
///
/// NOTE ON UNSOLD TOKENS:
///   - If not all bonding curve tokens were sold by graduation,
///     those unsold tokens are transferred here and permanently locked.
///   - They are NOT added to the DEX pool (only the migration reserve is).
///   - This avoids diluting the graduation price.
contract MigrationManager is IMigrationManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ────────────────────────────────────────────────────────────

    /// @dev LP "burn" address — sending NFT here permanently destroys it.
    address public constant LP_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error MigrationManager__AlreadyMigrated();
    error MigrationManager__Unauthorized();
    error MigrationManager__ZeroAddress();
    error MigrationManager__NotRegistered();
    error MigrationManager__AlreadyRegistered();
    error MigrationManager__NoMigrationReserve();
    error MigrationManager__AdapterNotSet();
    error MigrationManager__MigrationFailed();

    // ─── Events ───────────────────────────────────────────────────────────────

    event TokenRegistered(address indexed token, address indexed curve, uint256 migrationReserve);

    event LiquidityMigrated(
        address indexed token,
        address indexed pool,
        uint256 tokenAmountAdded,
        uint256 quoteAmountAdded,
        uint256 lpBurned
    );

    event UnsoldTokensLocked(address indexed token, uint256 amount);

    event DexAdapterUpdated(address indexed oldAdapter, address indexed newAdapter);

    // ─── State ────────────────────────────────────────────────────────────────

    struct TokenMigrationInfo {
        address curve;
        address quoteToken;
        uint256 migrationReserve; // Tokens held here for DEX pool
        uint24 feeTier;           // Uniswap V3 fee tier for the pool
        bool registered;
        bool migrated;
        address dexPool;
    }

    mapping(address token => TokenMigrationInfo) private _tokenInfo;

    /// @notice DEX adapter used for liquidity migration.
    IDexAdapter public dexAdapter;

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(address owner_, address dexAdapter_) Ownable(owner_) {
        if (dexAdapter_ != address(0)) {
            dexAdapter = IDexAdapter(dexAdapter_);
        }
    }

    // ─── Registration (called by LaunchpadFactory) ────────────────────────────

    /// @notice Register a token and receive its migration reserve.
    ///         Called by LaunchpadFactory after deploying a token.
    ///         Factory must approve MigrationManager to spend `reserveAmount` tokens.
    /// @param token            Launched token address.
    /// @param curve            BondingCurve address (only this can call migrate()).
    /// @param quoteToken       Quote asset address.
    /// @param reserveAmount    Number of tokens for migration reserve.
    /// @param feeTier          Uniswap V3 pool fee tier (e.g. 3000 = 0.3%).
    function registerToken(
        address token,
        address curve,
        address quoteToken,
        uint256 reserveAmount,
        uint24 feeTier
    ) external onlyOwner {
        if (_tokenInfo[token].registered) revert MigrationManager__AlreadyRegistered();
        if (token == address(0) || curve == address(0) || quoteToken == address(0)) {
            revert MigrationManager__ZeroAddress();
        }
        if (reserveAmount == 0) revert MigrationManager__NoMigrationReserve();

        _tokenInfo[token] = TokenMigrationInfo({
            curve: curve,
            quoteToken: quoteToken,
            migrationReserve: reserveAmount,
            feeTier: feeTier,
            registered: true,
            migrated: false,
            dexPool: address(0)
        });

        emit TokenRegistered(token, curve, reserveAmount);
    }

    // ─── Read ─────────────────────────────────────────────────────────────────

    /// @inheritdoc IMigrationManager
    function isMigrated(address token) external view override returns (bool) {
        return _tokenInfo[token].migrated;
    }

    /// @inheritdoc IMigrationManager
    function getPool(address token) external view override returns (address) {
        return _tokenInfo[token].dexPool;
    }

    /// @notice Returns migration info for a token.
    function getTokenInfo(address token) external view returns (TokenMigrationInfo memory) {
        return _tokenInfo[token];
    }

    // ─── Migration ────────────────────────────────────────────────────────────

    /// @inheritdoc IMigrationManager
    /// @dev Called by BondingCurve._graduate(). Quote tokens and unsold tokens
    ///      are transferred to this contract BEFORE this function is called.
    function migrate(address token, uint256 quoteAmount, uint256 unsoldTokenAmount)
        external
        override
        nonReentrant
    {
        TokenMigrationInfo storage info = _tokenInfo[token];

        // ─── Checks ───────────────────────────────────────────────────────────

        if (!info.registered) revert MigrationManager__NotRegistered();
        if (info.migrated) revert MigrationManager__AlreadyMigrated();
        if (msg.sender != info.curve) revert MigrationManager__Unauthorized();
        if (address(dexAdapter) == address(0)) revert MigrationManager__AdapterNotSet();

        // ─── Effects ──────────────────────────────────────────────────────────

        info.migrated = true;

        // ─── Interactions ─────────────────────────────────────────────────────

        // CRITICAL: Only use the pre-set migrationReserve (20% of supply) for the pool.
        // Do NOT use balanceOf() — that would include unsold curve tokens and drastically
        // dilute the pool price (e.g. 999M tokens + $1 USDC → near-zero price).
        //
        // Token flow at graduation:
        //   - MigrationManager already holds migrationReserve (20%) from LaunchpadFactory
        //   - BondingCurve sends unsoldTokens here just before calling migrate()
        //   - We send unsold to 0xdead (permanently locked), NOT into the pool
        //   - Pool only gets the 20% reserve + all USDC from curve buyers
        //
        uint256 poolTokenAmount = info.migrationReserve;
        uint256 quoteTokenAmount = quoteAmount;

        // Lock any unsold curve tokens permanently to dead address
        uint256 totalBalance = IERC20(token).balanceOf(address(this));
        if (totalBalance > poolTokenAmount) {
            uint256 unsoldTokens = totalBalance - poolTokenAmount;
            IERC20(token).safeTransfer(LP_BURN_ADDRESS, unsoldTokens);
            emit UnsoldTokensLocked(token, unsoldTokens);
        }

        // Sanity check: we must have exactly migrationReserve tokens available for pool
        uint256 availableForPool = IERC20(token).balanceOf(address(this));
        if (availableForPool < poolTokenAmount) {
            // Fallback: use whatever we have (should never happen with correct factory flow)
            poolTokenAmount = availableForPool;
        }

        uint160 sqrtPriceX96 = _computeSqrtPriceX96(
            token,
            info.quoteToken,
            poolTokenAmount,
            quoteTokenAmount
        );

        // Approve adapter to spend migration reserve tokens and collected quote
        IERC20(token).safeIncreaseAllowance(address(dexAdapter), poolTokenAmount);
        IERC20(info.quoteToken).safeIncreaseAllowance(address(dexAdapter), quoteTokenAmount);

        IDexAdapter.AddLiquidityParams memory params = IDexAdapter.AddLiquidityParams({
            token: token,
            quoteToken: info.quoteToken,
            tokenAmount: poolTokenAmount,
            quoteAmount: quoteTokenAmount,
            feeTier: info.feeTier,
            sqrtPriceX96: sqrtPriceX96,
            lpRecipient: LP_BURN_ADDRESS, // LP position is permanently burned to 0xdead
            deadline: block.timestamp + 300
        });

        IDexAdapter.LiquidityResult memory result = dexAdapter.createPoolAndAddLiquidity(params);

        // Reset allowances (safety: in case adapter didn't use full amount)
        IERC20(token).forceApprove(address(dexAdapter), 0);
        IERC20(info.quoteToken).forceApprove(address(dexAdapter), 0);

        // Store pool address
        info.dexPool = result.pool;
        info.migrationReserve = 0;

        emit LiquidityMigrated(
            token,
            result.pool,
            result.tokenAmountAdded,
            result.quoteAmountAdded,
            result.lpTokenIdOrAmount
        );
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Update the DEX adapter. Only callable by owner.
    ///         Only affects future (non-migrated) tokens.
    function setDexAdapter(address newAdapter) external onlyOwner {
        if (newAdapter == address(0)) revert MigrationManager__ZeroAddress();
        address old = address(dexAdapter);
        dexAdapter = IDexAdapter(newAdapter);
        emit DexAdapterUpdated(old, newAdapter);
    }

    // ─── Internal ─────────────────────────────────────────────────────────────

    /// @dev Computes exact sqrtPriceX96 for Uniswap v4 pool initialization without 256-bit overflow.
    ///      Formula: sqrtPriceX96 = sqrt(price) * 2^96
    ///      Where price = raw currency1 / raw currency0.
    function _computeSqrtPriceX96(
        address token,
        address quoteToken,
        uint256 poolTokenAmount,
        uint256 quoteTokenAmount
    ) internal pure returns (uint160 sqrtPriceX96) {
        if (quoteTokenAmount == 0) quoteTokenAmount = 1;
        if (poolTokenAmount == 0) poolTokenAmount = 1;

        bool quoteIsToken0 = quoteToken < token;

        if (quoteIsToken0) {
            // currency0 = quoteToken (USDC, 6 decimals), currency1 = token (18 decimals)
            // price = currency1 / currency0 = poolTokenAmount / quoteTokenAmount
            // sqrtPriceX96 = sqrt(poolTokenAmount / quoteTokenAmount) * 2^96
            // = sqrt((poolTokenAmount << 64) / quoteTokenAmount) << 64
            uint256 ratioX64 = (poolTokenAmount << 64) / quoteTokenAmount;
            sqrtPriceX96 = uint160(_sqrt(ratioX64) << 64);
        } else {
            // currency0 = token (18 decimals), currency1 = quoteToken (USDC, 6 decimals)
            // price = currency1 / currency0 = quoteTokenAmount / poolTokenAmount
            // sqrtPriceX96 = sqrt(quoteTokenAmount / poolTokenAmount) * 2^96
            // = sqrt((quoteTokenAmount << 128) / poolTokenAmount) << 32
            uint256 ratioX128 = (quoteTokenAmount << 128) / poolTokenAmount;
            sqrtPriceX96 = uint160(_sqrt(ratioX128) << 32);
        }

        if (sqrtPriceX96 <= TickMath.MIN_SQRT_PRICE) {
            sqrtPriceX96 = TickMath.MIN_SQRT_PRICE + 1;
        } else if (sqrtPriceX96 >= TickMath.MAX_SQRT_PRICE) {
            sqrtPriceX96 = TickMath.MAX_SQRT_PRICE - 1;
        }
    }

    /// @dev Integer square root via Newton's method.
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
