// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
