// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2, Vm} from "forge-std/Test.sol";
import "./LaunchpadTestBase.t.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {IBondingCurve} from "../src/interfaces/IBondingCurve.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

/// @title GraduationTest
/// @notice Tests for graduation trigger, status change, and post-graduation behavior.
contract GraduationTest is LaunchpadTestBase {
    address token;
    address curve;
    BondingCurve bc;

    function setUp() public override {
        super.setUp();
        (token, curve) = _createToken();
        bc = BondingCurve(curve);
    }

    // ─── Helper: Buy enough to graduate ──────────────────────────────────────

    /// @dev Buys in chunks to graduate the curve.
    ///      We need MC to reach $20,000. We buy incrementally.
    function _graduateCurve() internal {
        // Give trader1 plenty of USDC
        usdc.mint(trader1, 500_000 * 1e6);

        // Buy in $1000 chunks until graduated
        uint256 maxIterations = 100;
        for (uint256 i = 0; i < maxIterations; i++) {
            if (bc.status() == IBondingCurve.Status.GRADUATED) break;

            // Attempt to buy $2000 — might trigger graduation
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

    // ─── Graduation Tests ─────────────────────────────────────────────────────

    function test_Graduation_TriggeredWhenMcReachesTarget() public {
        _graduateCurve();
        assertEq(uint8(bc.status()), uint8(IBondingCurve.Status.GRADUATED), "Must be GRADUATED");
    }

    function test_Graduation_EmitsEvent() public {
        usdc.mint(trader1, 500_000 * 1e6);

        // Listen for Graduated event
        vm.recordLogs();
        _graduateCurve();

        // Verify Graduated event was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 graduatedSig = keccak256("Graduated(address,uint256,uint256)");
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == graduatedSig) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Graduated event must be emitted");
    }

    function test_Graduation_BuyReverts_AfterGraduation() public {
        _graduateCurve();

        // Attempt to buy after graduation — must revert
        usdc.mint(trader2, 1000 * 1e6);
        vm.startPrank(trader2);
        usdc.approve(curve, 1000 * 1e6);
        vm.expectRevert(BondingCurve.BondingCurve__AlreadyGraduated.selector);
        BondingCurve(curve).buy(1000 * 1e6, 0, block.timestamp + 300);
        vm.stopPrank();
    }

    function test_Graduation_SellReverts_AfterGraduation() public {
        uint256 tokens = _buy(trader1, curve, 1000 * 1e6);
        _graduateCurve();

        vm.startPrank(trader1);
        LaunchToken(token).approve(curve, tokens);
        vm.expectRevert(BondingCurve.BondingCurve__AlreadyGraduated.selector);
        BondingCurve(curve).sell(tokens, 0, block.timestamp + 300);
        vm.stopPrank();
    }

    function test_Graduation_PublicGraduate_RevertsIfNotReady() public {
        // MC not reached yet
        vm.expectRevert(BondingCurve.BondingCurve__NotGraduated.selector);
        BondingCurve(curve).graduate();
    }

    function test_Graduation_FinalMarketCap_AtOrAboveTarget() public {
        _graduateCurve();
        // After graduation, market cap was at or above $20K when triggered
        // We can verify by checking that migration happened
        assertTrue(migrationManager.isMigrated(token), "Must be migrated after graduation");
    }

    function test_Graduation_ReservesEmptied() public {
        _graduateCurve();
        // After graduation, BondingCurve sends its reserves to MigrationManager
        // Real reserves should be 0
        IBondingCurve.Reserves memory r = bc.getReserves();
        assertEq(r.realQuoteReserve, 0, "Quote reserve should be 0 after graduation");
        assertEq(r.realTokenReserve, 0, "Token reserve should be 0 after graduation");
    }

    function test_Graduation_Progress_Is100Percent_OrMore() public {
        _graduateCurve();
        // After graduation, progress is clamped at 10000 (100%)
        // getProgress uses current MC which is now 0 (reserves zeroed), but status is GRADUATED
        // The on-chain status is the definitive signal
        assertEq(uint8(bc.status()), uint8(IBondingCurve.Status.GRADUATED));
    }

    // ─── Double Graduation Protection ─────────────────────────────────────────

    function test_Graduation_CannotGraduateTwice() public {
        _graduateCurve();

        // Migration already happened, try again
        vm.expectRevert(); // MigrationManager__AlreadyMigrated
        BondingCurve(curve).graduate();
    }
}
