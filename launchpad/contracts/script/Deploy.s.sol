// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {MigrationManager} from "../src/MigrationManager.sol";
import {UniswapV4Adapter} from "../src/adapters/UniswapV4Adapter.sol";
import {LaunchpadFactory} from "../src/LaunchpadFactory.sol";

/// @title Deploy
/// @notice Automated deployment script for Arc Network.
contract Deploy is Script {
    // ─── Constants (Design Parameters) ──────────────────────────────────────────
    //
    // BONDING CURVE MATH:
    //   k = virtualQuote × virtualToken = constant
    //   initialPrice  = virtualQuote / virtualToken (normalized for decimals)
    //   initialMC     = initialPrice × totalSupply = $5,000
    //
    //   For 1B supply:  virtualQuote = 5_000 USDC (6-dec), virtualToken = 1B token (18-dec)
    //   initialMC = (5_000e6 × 1_000_000_000e18) / (1_000_000_000e18) = 5_000e6 = $5,000 ✓
    //
    //   To reach $20K graduation:
    //     realQuoteAccumulated ≈ $15,000 USDC (collected from curve buyers)
    //     tokensSold ≈ 750M (of 800M curve allocation)
    //
    uint256 constant VIRTUAL_TOKEN_PER_BILLION = 1_000_000_000 * 1e18; // exact 1B token
    uint256 constant VIRTUAL_QUOTE_PER_BILLION = 5_000 * 1e6;          // $5,000 USDC
    uint256 constant INITIAL_MC  = 5_000 * 1e6;   // $5,000
    uint256 constant DEFAULT_GRAD_MC = 20_000 * 1e6; // $20,000 USDC graduation target
    uint256 constant CREATOR_FEE_BPS  = 70;  // 0.7%
    uint256 constant PROTOCOL_FEE_BPS = 30;  // 0.3%

    // Official Arc Mainnet Addresses
    address constant ARC_USDC = 0x3600000000000000000000000000000000000000;
    address constant ARC_POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant ARC_POSITION_MANAGER = 0x6049c9a0e26405C0985f9E3685C87d0aE917f82B;
    address constant ARC_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function run() external {
        address quoteToken = vm.envOr("QUOTE_TOKEN_ADDRESS", ARC_USDC);
        address poolManager = vm.envOr("UNISWAP_V4_POOL_MANAGER", ARC_POOL_MANAGER);
        address positionManager = vm.envOr("UNISWAP_V4_POSITION_MANAGER", ARC_POSITION_MANAGER);
        address permit2 = vm.envOr("PERMIT2_ADDRESS", ARC_PERMIT2);
        uint256 gradMc = vm.envOr("GRADUATION_MARKET_CAP", DEFAULT_GRAD_MC);

        // Start broadcast
        vm.startBroadcast();

        // In Foundry scripts, tx.origin is always the actual broadcast sender!
        address deployer = tx.origin;
        address protocolTreasury = vm.envOr("PROTOCOL_FEE_RECIPIENT", deployer);

        console2.log("=== Arc Launchpad Deployment (Uniswap v4) ===");
        console2.log("Broadcaster / Owner:", deployer);
        console2.log("Quote Token (USDC):", quoteToken);
        console2.log("Pool Manager:", poolManager);
        console2.log("Position Manager:", positionManager);
        console2.log("Protocol Treasury:", protocolTreasury);

        // 1. Deploy UniswapV4Adapter first
        UniswapV4Adapter dexAdapter = new UniswapV4Adapter(
            poolManager,
            positionManager,
            permit2
        );
        console2.log("UniswapV4Adapter deployed at:", address(dexAdapter));

        // 2. Deploy MigrationManager directly with adapter
        MigrationManager migrationManager = new MigrationManager(
            deployer,
            address(dexAdapter)
        );
        console2.log("MigrationManager deployed at:", address(migrationManager));

        // 3. Deploy FeeManager
        FeeManager feeManager = new FeeManager(deployer);
        console2.log("FeeManager deployed at:", address(feeManager));

        // 4. Deploy LaunchpadFactory
        LaunchpadFactory factory = new LaunchpadFactory(
            deployer,
            address(feeManager),
            address(migrationManager),
            quoteToken,
            protocolTreasury,
            CREATOR_FEE_BPS,
            PROTOCOL_FEE_BPS,
            VIRTUAL_QUOTE_PER_BILLION,
            VIRTUAL_TOKEN_PER_BILLION,
            INITIAL_MC,
            gradMc
        );
        console2.log("LaunchpadFactory deployed at:", address(factory));

        // 5. Transfer ownership to factory
        feeManager.transferOwnership(address(factory));
        migrationManager.transferOwnership(address(factory));

        vm.stopBroadcast();

        console2.log("\n=== DEPLOYMENT SUCCESS ===");
        console2.log("NEXT_PUBLIC_FACTORY_ADDRESS=", address(factory));
        console2.log("NEXT_PUBLIC_FEE_MANAGER_ADDRESS=", address(feeManager));
        console2.log("NEXT_PUBLIC_MIGRATION_MANAGER_ADDRESS=", address(migrationManager));
        console2.log("NEXT_PUBLIC_UNISWAP_V4_ADAPTER_ADDRESS=", address(dexAdapter));
    }
}
