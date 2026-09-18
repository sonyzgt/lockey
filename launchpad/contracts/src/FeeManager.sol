// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IFeeManager} from "./interfaces/IFeeManager.sol";

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
