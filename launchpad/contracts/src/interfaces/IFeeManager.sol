// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
