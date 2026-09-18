// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ILaunchToken} from "./interfaces/ILaunchToken.sol";

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

    /// @notice Returns address(0) to signal to scanners (GMGN, GoPlus, etc.) that the contract is 100% renounced.
    function owner() external pure returns (address) {
        return address(0);
    }

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
