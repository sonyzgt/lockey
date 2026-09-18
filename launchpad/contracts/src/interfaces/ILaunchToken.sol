// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILaunchToken
/// @notice Interface for the ERC-20 token created by the launchpad factory.
interface ILaunchToken {
    /// @notice Returns the address that created this token via the factory.
    function creator() external view returns (address);

    /// @notice Returns the IPFS CID of the token metadata JSON.
    function metadataURI() external view returns (string memory);
}
