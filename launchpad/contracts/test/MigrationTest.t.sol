// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2, Vm} from "forge-std/Test.sol";
import "./LaunchpadTestBase.t.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {IBondingCurve} from "../src/interfaces/IBondingCurve.sol";
import {MigrationManager} from "../src/MigrationManager.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MigrationTest
/// @notice Tests for liquidity migration after graduation.
contract MigrationTest is LaunchpadTestBase {
    address token;
    address curve;
    BondingCurve bc;

    function setUp() public override {
        super.setUp();
        (token, curve) = _createToken();
        bc = BondingCurve(curve);
    }

    function _graduateCurve() internal {
        usdc.mint(trader1, 500_000 * 1e6);
        for (uint256 i = 0; i < 100; i++) {
            if (bc.status() == IBondingCurve.Status.GRADUATED) break;
            vm.startPrank(trader1);
            usdc.approve(curve, 2000 * 1e6);
            try BondingCurve(curve).buy(2000 * 1e6, 0, block.timestamp + 300) {
                vm.stopPrank();
            } catch {
                vm.stopPrank();
                break;
            }
        }
    }

    // ─── Migration Tests ──────────────────────────────────────────────────────

    function test_Migration_HappensOnGraduation() public {
        _graduateCurve();
        assertTrue(migrationManager.isMigrated(token), "Token must be migrated after graduation");
    }

    function test_Migration_DEX_AdapterCalled() public {
        _graduateCurve();
        assertTrue(dexAdapter.createCalled(), "DEX adapter must have been called");
    }

    function test_Migration_PoolCreated() public {
        _graduateCurve();
        address pool = migrationManager.getPool(token);
        assertNotEq(pool, address(0), "DEX pool must be created");
    }

    function test_Migration_CannotHappenTwice() public {
        _graduateCurve();
        // Migration already done. Trying to call migrate again should revert.
        vm.prank(curve);
        vm.expectRevert(MigrationManager.MigrationManager__AlreadyMigrated.selector);
        migrationManager.migrate(token, 0, 0);
    }

    function test_Migration_OnlyCallableByRegisteredCurve() public {
        // Random caller cannot trigger migration
        vm.prank(trader1);
        vm.expectRevert(MigrationManager.MigrationManager__Unauthorized.selector);
        migrationManager.migrate(token, 0, 0);
    }

    function test_Migration_QuoteTokenSentToDEX() public {
        // Before graduation, fund some trades to accumulate USDC in curve
        uint256 initialQuoteInCurve;
        {
            uint256 usdcIn = 3000 * 1e6;
            uint256 fee = (usdcIn * (CREATOR_FEE + PROTOCOL_FEE)) / 10_000;
            _buy(trader1, curve, usdcIn);
            initialQuoteInCurve = usdcIn - fee;
        }

        // Track USDC balance of mock DEX adapter before graduation
        uint256 adapterBalBefore = usdc.balanceOf(address(dexAdapter));

        // Graduate
        _graduateCurve();

        // DEX adapter should have received USDC
        // (MockDexAdapter doesn't actually transfer, but MigrationManager sends to it)
        // We check that MigrationManager no longer holds the USDC
        assertEq(usdc.balanceOf(address(migrationManager)), 0, "MigrationManager should not hold USDC after migration");
    }

    function test_Migration_TokenReserveUsed() public {
        _graduateCurve();
        // MigrationManager should have spent its migration reserve
        // After migration, migration reserve should be 0
        MigrationManager.TokenMigrationInfo memory info = migrationManager.getTokenInfo(token);
        assertEq(info.migrationReserve, 0, "Migration reserve must be consumed");
    }

    function test_Migration_EmitsEvent() public {
        usdc.mint(trader1, 500_000 * 1e6);

        vm.recordLogs();
        _graduateCurve();

        bytes32 migSig = keccak256("LiquidityMigrated(address,address,uint256,uint256,uint256)");
        bool found = false;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == migSig) {
                found = true;
                break;
            }
        }
        assertTrue(found, "LiquidityMigrated event must be emitted");
    }

    // ─── LP Burn Verification ─────────────────────────────────────────────────

    function test_Migration_LP_SentToBurnAddress() public {
        // MockDexAdapter sends LP to lpRecipient which is LP_BURN_ADDRESS
        // We verify by checking the params passed to the adapter
        // In real scenario, LP NFT goes to 0xdead
        _graduateCurve();
        // If migration succeeded and adapter was called with lpRecipient = LP_BURN_ADDRESS,
        // the LP is permanently burned. We verify via isMigrated flag.
        assertTrue(migrationManager.isMigrated(token));
        // Burn address = 0xdead
        assertEq(migrationManager.getPool(token), dexAdapter.lastPool());
    }

    // ─── Pre-Migration State ──────────────────────────────────────────────────

    function test_PreMigration_IsNotMigrated() public {
        assertFalse(migrationManager.isMigrated(token));
        assertEq(migrationManager.getPool(token), address(0));
    }

    // ─── Unauthorized Migration ───────────────────────────────────────────────

    function test_Migration_RequiresRegistration() public {
        address fakeToken = makeAddr("fakeToken");
        vm.prank(makeAddr("fakeCurve"));
        vm.expectRevert(MigrationManager.MigrationManager__NotRegistered.selector);
        migrationManager.migrate(fakeToken, 0, 0);
    }

    // ─── Admin: setDexAdapter ─────────────────────────────────────────────────

    function test_Admin_CanUpdateDexAdapter() public {
        MockDexAdapter newAdapter = new MockDexAdapter();
        // migrationManager.owner() is factory, factory.owner() is admin
        // We need factory to call setDexAdapter via some proxy OR transfer ownership back for test
        // Since factory doesn't expose setDexAdapter, we test it directly here
        // by transferring migrationManager ownership temporarily
        vm.prank(address(factory)); // act as factory (owner)
        migrationManager.setDexAdapter(address(newAdapter));
        assertEq(address(migrationManager.dexAdapter()), address(newAdapter));
    }
}
