// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// src/libraries/BondingCurveMath.sol

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

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/utils/Errors.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error InsufficientBalance(uint256 balance, uint256 needed);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedCall();

    /**
     * @dev The deployment failed.
     */
    error FailedDeployment();

    /**
     * @dev A necessary precompile is missing.
     */
    error MissingPrecompile(address);
}

// src/interfaces/IBondingCurve.sol

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

    /// @notice Returns a quote for buying `quoteAmountIn` of quote token.
    /// @param quoteAmountIn Amount of quote token to spend (including fee).
    function quoteBuy(uint256 quoteAmountIn) external view returns (BuyQuote memory);

    /// @notice Returns a quote for selling `tokenAmountIn` tokens.
    /// @param tokenAmountIn Amount of tokens to sell.
    function quoteSell(uint256 tokenAmountIn) external view returns (SellQuote memory);

    /// @notice Current status: BONDING or GRADUATED.
    function status() external view returns (Status);

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

// src/interfaces/IDexAdapter.sol

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

// lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// src/interfaces/IFeeManager.sol

/// @title IFeeManager
/// @notice Manages creator and protocol fee accumulation and claims.
interface IFeeManager {
    // ─── Read Functions ───────────────────────────────────────────────────────

    /// @notice Returns the claimable creator fee for a specific token.
    /// @param token   The launched token address.
    /// @param creator The creator's wallet address.
    function claimableCreatorFees(address token, address creator) external view returns (uint256);

    /// @notice Returns the accumulated protocol fees for a specific token.
    function claimableProtocolFees(address token) external view returns (uint256);

    // ─── Write Functions ──────────────────────────────────────────────────────

    /// @notice Accrues creator fee. Only callable by the registered bonding curve for that token.
    function accrueCreatorFee(address token, uint256 amount) external;

    /// @notice Accrues protocol fee. Only callable by the registered bonding curve for that token.
    function accrueProtocolFee(address token, uint256 amount) external;

    /// @notice Creator claims their accumulated fees for a specific token.
    /// @param token The token for which to claim fees.
    function claimCreatorFees(address token) external;

    /// @notice Protocol admin withdraws accumulated protocol fees.
    /// @param token     Token address.
    /// @param recipient Address to receive protocol fees.
    function withdrawProtocolFees(address token, address recipient) external;
}

// src/interfaces/ILaunchToken.sol

/// @title ILaunchToken
/// @notice Interface for the ERC-20 token created by the launchpad factory.
interface ILaunchToken {
    /// @notice Returns the address that created this token via the factory.
    function creator() external view returns (address);

    /// @notice Returns the IPFS CID of the token metadata JSON.
    function metadataURI() external view returns (string memory);
}

// src/interfaces/IMigrationManager.sol

/// @title IMigrationManager
/// @notice Handles post-graduation liquidity migration to DEX.
interface IMigrationManager {
    // ─── Read Functions ───────────────────────────────────────────────────────

    /// @notice Returns true if migration has already been executed for `token`.
    function isMigrated(address token) external view returns (bool);

    /// @notice Returns the DEX pool address created for `token` (0 if not migrated yet).
    function getPool(address token) external view returns (address);

    // ─── Write Functions ──────────────────────────────────────────────────────

    /// @notice Called by BondingCurve upon graduation.
    ///         Receives USDC + remaining tokens, then migrates to DEX.
    /// @param token The graduated token address.
    /// @param quoteAmount Amount of quote token (USDC) sent with this call.
    /// @param tokenReserveAmount Additional token amount sent from migration escrow.
    function migrate(address token, uint256 quoteAmount, uint256 tokenReserveAmount) external;
}

// lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol

// OpenZeppelin Contracts (last updated v5.1.0) (interfaces/draft-IERC6093.sol)

/**
 * @dev Standard ERC-20 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-20 tokens.
 */
interface IERC20Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC20InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC20InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC20InvalidSpender(address spender);
}

/**
 * @dev Standard ERC-721 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-721 tokens.
 */
interface IERC721Errors {
    /**
     * @dev Indicates that an address can't be an owner. For example, `address(0)` is a forbidden owner in ERC-20.
     * Used in balance queries.
     * @param owner Address of the current owner of a token.
     */
    error ERC721InvalidOwner(address owner);

    /**
     * @dev Indicates a `tokenId` whose `owner` is the zero address.
     * @param tokenId Identifier number of a token.
     */
    error ERC721NonexistentToken(uint256 tokenId);

    /**
     * @dev Indicates an error related to the ownership over a particular token. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param tokenId Identifier number of a token.
     * @param owner Address of the current owner of a token.
     */
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC721InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC721InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param tokenId Identifier number of a token.
     */
    error ERC721InsufficientApproval(address operator, uint256 tokenId);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC721InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC721InvalidOperator(address operator);
}

/**
 * @dev Standard ERC-1155 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-1155 tokens.
 */
interface IERC1155Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     * @param tokenId Identifier number of a token.
     */
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC1155InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC1155InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param owner Address of the current owner of a token.
     */
    error ERC1155MissingApprovalForAll(address operator, address owner);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC1155InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC1155InvalidOperator(address operator);

    /**
     * @dev Indicates an array length mismatch between ids and values in a safeBatchTransferFrom operation.
     * Used in batch transfers.
     * @param idsLength Length of the array of token identifiers
     * @param valuesLength Length of the array of token amounts
     */
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);
}

// lib/openzeppelin-contracts/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert Errors.FailedCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {Errors.FailedCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {Errors.FailedCall}) in case
     * of an unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {Errors.FailedCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {Errors.FailedCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            assembly ("memory-safe") {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert Errors.FailedCall();
        }
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/extensions/IERC20Metadata.sol)

/**
 * @dev Interface for the optional metadata functions from the ERC-20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// lib/openzeppelin-contracts/contracts/access/Ownable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// lib/openzeppelin-contracts/contracts/utils/Pausable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Pausable.sol)

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/ERC20.sol)

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * The default value of {decimals} is 18. To change this, you should override
 * this function so it returns a different value.
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC-20
 * applications.
 */
abstract contract ERC20 is Context, IERC20, IERC20Metadata, IERC20Errors {
    mapping(address account => uint256) private _balances;

    mapping(address account => mapping(address spender => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `value`.
     */
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Skips emitting an {Approval} event indicating an allowance update. This is not
     * required by the ERC. See {xref-ERC20-_approve-address-address-uint256-bool-}[_approve].
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `value`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `value`.
     */
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
     * Relies on the `_update` mechanism
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /**
     * @dev Destroys a `value` amount of tokens from `account`, lowering the total supply.
     * Relies on the `_update` mechanism.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead
     */
    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    /**
     * @dev Sets `value` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
     * `_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
     * `Approval` event during `transferFrom` operations.
     *
     * Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
     * true using the following override:
     *
     * ```solidity
     * function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
     *     super._approve(owner, spender, value, true);
     * }
     * ```
     *
     * Requirements are the same as {_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC1363.sol

// OpenZeppelin Contracts (last updated v5.1.0) (interfaces/IERC1363.sol)

/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * Defines an extension interface for ERC-20 tokens that supports executing code on a recipient contract
 * after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 is IERC20, IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0xb0202a11.
     * 0xb0202a11 ===
     *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
     *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
     */

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}

// src/LaunchToken.sol

/// @title LaunchToken
/// @notice ERC-20 token created by LaunchpadFactory.
///
/// DESIGN DECISIONS:
///   - Total supply is minted entirely to the factory at construction.
///   - No mint or burn functions after creation.
///   - Creator address is stored immutably on-chain.
///   - Metadata URI (IPFS CIDv1) is stored as a string — not changeable after launch.
///   - Standard ERC-20 with 18 decimals.
///   - No owner, no admin, no upgradability — maximally trustless.
contract LaunchToken is ERC20, ILaunchToken {
    // ─── Errors ───────────────────────────────────────────────────────────────

    error LaunchToken__ZeroAddress();
    error LaunchToken__ZeroSupply();
    error LaunchToken__MetadataEmpty();

    // ─── Immutable State ──────────────────────────────────────────────────────

    /// @inheritdoc ILaunchToken
    address public immutable override creator;

    /// @inheritdoc ILaunchToken
    string public override metadataURI;

    // ─── Constructor ──────────────────────────────────────────────────────────

    /// @param name_        ERC-20 name.
    /// @param symbol_      ERC-20 symbol (ticker).
    /// @param totalSupply_ Total fixed supply in wei (18 decimals).
    /// @param creator_     Address of the token creator.
    /// @param metadataURI_ IPFS URI for token metadata JSON, e.g. "ipfs://Qm..."
    /// @param recipient_   Address to receive entire minted supply (LaunchpadFactory).
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address creator_,
        string memory metadataURI_,
        address recipient_
    ) ERC20(name_, symbol_) {
        if (creator_ == address(0)) revert LaunchToken__ZeroAddress();
        if (recipient_ == address(0)) revert LaunchToken__ZeroAddress();
        if (totalSupply_ == 0) revert LaunchToken__ZeroSupply();
        if (bytes(metadataURI_).length == 0) revert LaunchToken__MetadataEmpty();

        creator = creator_;
        metadataURI = metadataURI_;

        // Mint all tokens to recipient (LaunchpadFactory), which will then
        // distribute them to BondingCurve and MigrationManager.
        _mint(recipient_, totalSupply_);
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     *
     * NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
     * only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
     * set here.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Performs an {ERC1363} transferAndCall, with a fallback to the simple {ERC20} transfer if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferFromAndCall, with a fallback to the simple {ERC20} transferFrom if the target
     * has no code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} approveAndCall, with a fallback to the simple {ERC20} approve if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * NOTE: When the recipient address (`to`) has no code (i.e. is an EOA), this function behaves as {forceApprove}.
     * Opposedly, when the recipient address (`to`) has code, this function only attempts to call {ERC1363-approveAndCall}
     * once without retrying, and relies on the returned value to be true.
     *
     * Reverts if the returned value is other than `true`.
     */
    function approveAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturnBool} that reverts if call fails to meet the requirements.
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize == 0 ? address(token).code.length == 0 : returnValue != 1) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silently catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? address(token).code.length > 0 : returnValue == 1);
    }
}

// src/FeeManager.sol

/// @title FeeManager
/// @notice Accumulates and distributes creator and protocol fees.
///
/// DESIGN:
///   - BondingCurve transfers quote tokens (USDC) to this contract before calling
///     accrueCreatorFee() and accrueProtocolFee(). This is the only way fees arrive.
///   - Creator can claim their fees for any token they created.
///   - Protocol admin can withdraw protocol fees.
///   - No admin can touch creator fees (isolated by token + creator mapping).
///
/// SECURITY:
///   - accrueCreatorFee / accrueProtocolFee: only callable by registered bonding curves.
///   - claimCreatorFees: only callable by the registered creator of that token.
///   - withdrawProtocolFees: only callable by Ownable owner (protocol treasury).
///   - ReentrancyGuard on all external state-changing functions.
///   - All transfers via SafeERC20.
contract FeeManager is IFeeManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Errors ───────────────────────────────────────────────────────────────

    error FeeManager__Unauthorized();
    error FeeManager__ZeroClaimable();
    error FeeManager__ZeroAddress();
    error FeeManager__AlreadyRegistered();
    error FeeManager__NotRegistered();
    error FeeManager__TokenMismatch();

    // ─── Events ───────────────────────────────────────────────────────────────

    event TokenRegistered(address indexed token, address indexed curve, address indexed creator, address quoteToken);

    event FeesClaimed(address indexed token, address indexed creator, uint256 amount);

    event ProtocolFeesWithdrawn(address indexed token, address indexed recipient, uint256 amount);

    // ─── State ────────────────────────────────────────────────────────────────

    struct TokenInfo {
        address curve;
        address creator;
        address quoteToken;
        bool registered;
    }

    /// @notice Registry: token address → info.
    mapping(address token => TokenInfo) public tokenRegistry;

    /// @notice Claimable creator fees: token → creator → amount.
    mapping(address token => mapping(address creator => uint256)) private _creatorFees;

    /// @notice Accumulated protocol fees per token.
    mapping(address token => uint256) private _protocolFees;

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(address owner_) Ownable(owner_) {}

    // ─── Registration ─────────────────────────────────────────────────────────

    /// @notice Register a token + bonding curve. Only callable by contract owner (factory).
    /// @dev Called by LaunchpadFactory during token creation.
    function registerToken(address token, address curve, address creator, address quoteToken)
        external
        onlyOwner
    {
        if (token == address(0) || curve == address(0) || creator == address(0)) {
            revert FeeManager__ZeroAddress();
        }
        if (tokenRegistry[token].registered) revert FeeManager__AlreadyRegistered();

        tokenRegistry[token] = TokenInfo({
            curve: curve,
            creator: creator,
            quoteToken: quoteToken,
            registered: true
        });

        emit TokenRegistered(token, curve, creator, quoteToken);
    }

    // ─── Accrue (called by BondingCurve only) ─────────────────────────────────

    /// @inheritdoc IFeeManager
    function accrueCreatorFee(address token, uint256 amount) external override {
        TokenInfo storage info = tokenRegistry[token];
        if (!info.registered) revert FeeManager__NotRegistered();
        if (msg.sender != info.curve) revert FeeManager__Unauthorized();

        // Note: The actual USDC has already been transferred to this contract
        // by BondingCurve before calling this function.
        _creatorFees[token][info.creator] += amount;
    }

    /// @inheritdoc IFeeManager
    function accrueProtocolFee(address token, uint256 amount) external override {
        TokenInfo storage info = tokenRegistry[token];
        if (!info.registered) revert FeeManager__NotRegistered();
        if (msg.sender != info.curve) revert FeeManager__Unauthorized();

        _protocolFees[token] += amount;
    }

    // ─── Read ─────────────────────────────────────────────────────────────────

    /// @inheritdoc IFeeManager
    function claimableCreatorFees(address token, address creator)
        external
        view
        override
        returns (uint256)
    {
        return _creatorFees[token][creator];
    }

    /// @inheritdoc IFeeManager
    function claimableProtocolFees(address token) external view override returns (uint256) {
        return _protocolFees[token];
    }

    // ─── Claims ───────────────────────────────────────────────────────────────

    /// @inheritdoc IFeeManager
    function claimCreatorFees(address token) external override nonReentrant {
        TokenInfo storage info = tokenRegistry[token];
        if (!info.registered) revert FeeManager__NotRegistered();
        if (msg.sender != info.creator) revert FeeManager__Unauthorized();

        uint256 amount = _creatorFees[token][msg.sender];
        if (amount == 0) revert FeeManager__ZeroClaimable();

        // ─── Effects ──────────────────────────────────────────────────────────
        _creatorFees[token][msg.sender] = 0;

        // ─── Interactions ─────────────────────────────────────────────────────
        IERC20(info.quoteToken).safeTransfer(msg.sender, amount);

        emit FeesClaimed(token, msg.sender, amount);
    }

    /// @inheritdoc IFeeManager
    function withdrawProtocolFees(address token, address recipient) external override onlyOwner nonReentrant {
        if (recipient == address(0)) revert FeeManager__ZeroAddress();

        TokenInfo storage info = tokenRegistry[token];
        if (!info.registered) revert FeeManager__NotRegistered();

        uint256 amount = _protocolFees[token];
        if (amount == 0) revert FeeManager__ZeroClaimable();

        // ─── Effects ──────────────────────────────────────────────────────────
        _protocolFees[token] = 0;

        // ─── Interactions ─────────────────────────────────────────────────────
        IERC20(info.quoteToken).safeTransfer(recipient, amount);

        emit ProtocolFeesWithdrawn(token, recipient, amount);
    }

    // ─── Convenience: Claim All ───────────────────────────────────────────────

    /// @notice Claim fees for multiple tokens in one call.
    function claimCreatorFeesMultiple(address[] calldata tokens) external nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenAddr = tokens[i];
            TokenInfo storage info = tokenRegistry[tokenAddr];
            if (!info.registered) continue;
            if (msg.sender != info.creator) continue;

            uint256 amount = _creatorFees[tokenAddr][msg.sender];
            if (amount == 0) continue;

            _creatorFees[tokenAddr][msg.sender] = 0;
            IERC20(info.quoteToken).safeTransfer(msg.sender, amount);

            emit FeesClaimed(tokenAddr, msg.sender, amount);
        }
    }
}

// src/MigrationManager.sol

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

        // Pull migration reserve tokens from caller (factory must have approved)
        IERC20(token).safeTransferFrom(msg.sender, address(this), reserveAmount);

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

        // Lock unsold bonding curve tokens (just emitting, they stay in this contract)
        if (unsoldTokenAmount > 0) {
            emit UnsoldTokensLocked(token, unsoldTokenAmount);
            // Tokens are locked forever — no function to retrieve them.
        }

        // ─── Interactions ─────────────────────────────────────────────────────

        uint256 migrationTokenAmount = info.migrationReserve;
        uint256 quoteTokenAmount = quoteAmount;

        // Compute sqrtPriceX96 for Uniswap V3 pool initialization.
        // sqrtPriceX96 represents the initial price of token1 in terms of token0.
        // We set it based on the final bonding curve price:
        //   price = quoteAmount / migrationTokenAmount
        // Note: Uniswap V3 requires tokens sorted by address.
        // The adapter handles token sorting internally.
        uint160 sqrtPriceX96 = _computeSqrtPriceX96(
            token,
            info.quoteToken,
            migrationTokenAmount,
            quoteTokenAmount
        );

        // Approve adapter to spend both tokens
        IERC20(token).safeIncreaseAllowance(address(dexAdapter), migrationTokenAmount);
        IERC20(info.quoteToken).safeIncreaseAllowance(address(dexAdapter), quoteTokenAmount);

        IDexAdapter.AddLiquidityParams memory params = IDexAdapter.AddLiquidityParams({
            token: token,
            quoteToken: info.quoteToken,
            tokenAmount: migrationTokenAmount,
            quoteAmount: quoteTokenAmount,
            feeTier: info.feeTier,
            sqrtPriceX96: sqrtPriceX96,
            lpRecipient: LP_BURN_ADDRESS, // LP is burned immediately
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

    /// @dev Computes sqrtPriceX96 for Uniswap V3 pool initialization.
    ///      Formula: sqrtPriceX96 = sqrt(price) * 2^96
    ///      Where price = amount1 / amount0 (both in their native decimals).
    ///      Uniswap V3 defines price as token1/token0 where token0 < token1 by address.
    ///
    ///      We use integer approximation: sqrt via Newton's method or bit shift.
    ///      For production, consider using FullMath / TickMath from Uniswap V3 libraries.
    function _computeSqrtPriceX96(
        address tokenA,
        address tokenB,
        uint256 tokenAAmount,
        uint256 tokenBAmount
    ) internal pure returns (uint160 sqrtPriceX96) {
        // Determine token0 / token1 ordering (by address, lower address = token0)
        bool tokenIsToken0 = tokenA < tokenB;

        // price = amount of token1 per token0 (in raw units)
        // We need to account for decimal differences:
        //   token (18 decimals), quote/USDC (6 decimals)
        //   If token is token0: price = quoteAmount(1e6) / tokenAmount(1e18) * 1e12 (normalize)
        //   If token is token1: price = tokenAmount(1e18) / quoteAmount(1e6) / 1e12 (normalize)

        uint256 numerator;
        uint256 denominator;

        if (tokenIsToken0) {
            // token0 = launch token (18 dec), token1 = quote (6 dec)
            // price (token1/token0) = quoteAmount * 1e12 / tokenAmount
            numerator = tokenBAmount * 1e12; // scale quote to 18 decimals
            denominator = tokenAAmount;
        } else {
            // token0 = quote (6 dec), token1 = launch token (18 dec)
            // price (token1/token0) = tokenAmount / (quoteAmount * 1e12)
            numerator = tokenAAmount;
            denominator = tokenBAmount * 1e12;
        }

        // sqrtPriceX96 = sqrt(numerator / denominator) * 2^96
        // = sqrt(numerator) * 2^96 / sqrt(denominator)
        // = sqrt(numerator * 2^192 / denominator)   [to keep precision]
        // We use uint256 sqrt:
        uint256 ratioX192 = (numerator << 192) / denominator;
        sqrtPriceX96 = uint160(_sqrt(ratioX192));
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

// src/BondingCurve.sol

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
    function quoteBuy(uint256 quoteAmountIn) public view override returns (BuyQuote memory q) {
        if (quoteAmountIn == 0) revert BondingCurve__ZeroAmount();

        uint256 feeAmount = (quoteAmountIn * totalFeeBps) / FEE_DENOMINATOR;
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
        nonReentrant
        whenNotPaused
        onlyBonding
        checkDeadline(deadline)
        returns (uint256 tokensOut)
    {
        if (quoteAmountIn == 0) revert BondingCurve__ZeroAmount();

        // ─── Checks ───────────────────────────────────────────────────────────

        // Compute fee split
        uint256 totalFee = (quoteAmountIn * totalFeeBps) / FEE_DENOMINATOR;
        uint256 creatorFeeAmt = (quoteAmountIn * creatorFeeBps) / FEE_DENOMINATOR;
        uint256 protocolFeeAmt = totalFee - creatorFeeAmt;
        uint256 amountInNet = quoteAmountIn - totalFee;

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

        // Pull quote from buyer (full amount incl. fee)
        IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), quoteAmountIn);

        // Forward fees to FeeManager
        IERC20(quoteToken).safeTransfer(feeManager, totalFee);
        IFeeManager(feeManager).accrueCreatorFee(token, creatorFeeAmt);
        IFeeManager(feeManager).accrueProtocolFee(token, protocolFeeAmt);

        // Send tokens to buyer
        IERC20(token).safeTransfer(msg.sender, tokensOut);

        // Compute post-trade values for events
        uint256 newMc = getMarketCap();
        uint256 newPrice = getCurrentPrice();

        emit TokenBought(token, msg.sender, quoteAmountIn, tokensOut, creatorFeeAmt, protocolFeeAmt, newMc, newPrice);
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

        // Approve MigrationManager to pull quote tokens and curve's remaining tokens
        // (remaining tokens will be burned or locked via MigrationManager logic)
        if (quoteToMigrate > 0) {
            IERC20(quoteToken).safeTransfer(migrationManager, quoteToMigrate);
        }
        if (tokenRemainingInCurve > 0) {
            // Remaining unsold tokens in curve — send to migration manager
            // (it will lock them, not add them to the pool)
            IERC20(token).safeTransfer(migrationManager, tokenRemainingInCurve);
        }

        // Trigger migration — MigrationManager will handle the DEX pool creation
        IMigrationManager(migrationManager).migrate(token, quoteToMigrate, tokenRemainingInCurve);
    }
}

// src/LaunchpadFactory.sol

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

    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event TradingFeesUpdated(uint256 oldCreatorBps, uint256 oldProtocolBps, uint256 newCreatorBps, uint256 newProtocolBps);
    event QuoteTokenUpdated(address indexed quoteToken, bool supported);
    event CreationFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

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

        // 80% → BondingCurve
        IERC20(token).safeTransfer(curve, bondingAllocation);

        // 20% → MigrationManager (as migration reserve)
        // First approve, then MigrationManager pulls via registerToken
        IERC20(token).safeIncreaseAllowance(address(migrationManager), migrationReserve);
        migrationManager.registerToken(
            token,
            curve,
            params.quoteToken,
            migrationReserve,
            params.poolFeeTier
        );
        IERC20(token).forceApprove(address(migrationManager), 0);

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
}
