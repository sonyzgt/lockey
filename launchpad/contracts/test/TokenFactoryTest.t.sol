// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import "./LaunchpadTestBase.t.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {IBondingCurve} from "../src/interfaces/IBondingCurve.sol";

/// @title TokenFactoryTest
/// @notice Integration tests for token creation via LaunchpadFactory.
contract TokenFactoryTest is LaunchpadTestBase {

    // ─── Creation Tests ───────────────────────────────────────────────────────

    function test_CreateToken_Succeeds() public {
        (address token, address curve) = _createToken();

        assertNotEq(token, address(0), "Token should be deployed");
        assertNotEq(curve, address(0), "Curve should be deployed");
        assertEq(factory.totalTokens(), 1, "Factory should have 1 token");
    }

    function test_CreateToken_EmitsEvent() public {
        vm.expectEmit(false, false, true, false); // check only topic 3 (creator)
        emit LaunchpadFactory.TokenCreated(
            address(0), address(0), creator,
            "Test Token", "TEST", TOTAL_SUPPLY,
            address(usdc), "ipfs://QmTestHash123", block.timestamp
        );
        _createToken();
    }

    function test_CreateToken_SupplyDistribution() public {
        (address token, address curve) = _createToken();

        uint256 bondingAlloc = (TOTAL_SUPPLY * 8_000) / 10_000;  // 80%
        uint256 migrationRes  = (TOTAL_SUPPLY * 2_000) / 10_000; // 20%

        // 80% of total supply is held by the BondingCurve (for trading)
        assertEq(
            LaunchToken(token).balanceOf(curve),
            bondingAlloc,
            "80% of token supply must be in BondingCurve pool"
        );

        // 20% held by MigrationManager (the migration reserve for the DEX pool at graduation)
        assertEq(
            LaunchToken(token).balanceOf(address(migrationManager)),
            migrationRes,
            "MigrationManager holds 20% of supply as migration reserve from launch"
        );

        // Full supply accounted for
        assertEq(
            LaunchToken(token).balanceOf(curve) + LaunchToken(token).balanceOf(address(migrationManager)),
            TOTAL_SUPPLY,
            "curve + MM must hold 100% of supply"
        );
    }

    function test_CreateToken_CreatorStoredOnChain() public {
        (address token,) = _createToken();
        assertEq(LaunchToken(token).creator(), creator, "Creator must be stored on-chain");
    }

    function test_CreateToken_MetadataStored() public {
        (address token,) = _createToken();
        assertEq(LaunchToken(token).metadataURI(), "ipfs://QmTestHash123", "IPFS URI must be stored");
    }

    function test_CreateToken_RecordedInFactory() public {
        (address token, address curve) = _createToken();

        (address recToken, address recCurve, address recCreator, address recQuoteToken, uint256 recCreatedAt) = factory.tokenRecords(token);
        assertEq(recToken, token);
        assertEq(recCurve, curve);
        assertEq(recCreator, creator);
        assertEq(recQuoteToken, address(usdc));
        assertGt(recCreatedAt, 0);
    }

    function test_CreateToken_FailsEmptyName() public {
        vm.prank(creator);
        vm.expectRevert(LaunchpadFactory.Factory__EmptyName.selector);
        factory.createToken(LaunchpadFactory.TokenParams({
            name: "",
            symbol: "TEST",
            totalSupply: TOTAL_SUPPLY,
            metadataURI: "ipfs://test",
            quoteToken: address(usdc),
            poolFeeTier: 3000
        }));
    }

    function test_CreateToken_FailsInvalidSupply() public {
        vm.prank(creator);
        vm.expectRevert(LaunchpadFactory.Factory__InvalidSupply.selector);
        factory.createToken(LaunchpadFactory.TokenParams({
            name: "Test",
            symbol: "TST",
            totalSupply: 1e15, // below MIN_TOTAL_SUPPLY
            metadataURI: "ipfs://test",
            quoteToken: address(usdc),
            poolFeeTier: 3000
        }));
    }

    function test_CreateToken_FailsUnsupportedQuote() public {
        address fakeToken = makeAddr("fakeToken");
        vm.prank(creator);
        vm.expectRevert(LaunchpadFactory.Factory__QuoteTokenNotSupported.selector);
        factory.createToken(LaunchpadFactory.TokenParams({
            name: "Test",
            symbol: "TST",
            totalSupply: TOTAL_SUPPLY,
            metadataURI: "ipfs://test",
            quoteToken: fakeToken,
            poolFeeTier: 3000
        }));
    }

    function test_CreateToken_FailsEmptyMetadata() public {
        vm.prank(creator);
        vm.expectRevert(LaunchpadFactory.Factory__EmptyMetadataURI.selector);
        factory.createToken(LaunchpadFactory.TokenParams({
            name: "Test",
            symbol: "TST",
            totalSupply: TOTAL_SUPPLY,
            metadataURI: "",
            quoteToken: address(usdc),
            poolFeeTier: 3000
        }));
    }

    function test_CreateMultipleTokens() public {
        _createToken();

        vm.startPrank(trader1);
        factory.createToken(LaunchpadFactory.TokenParams({
            name: "Token2",
            symbol: "TK2",
            totalSupply: TOTAL_SUPPLY,
            metadataURI: "ipfs://hash2",
            quoteToken: address(usdc),
            poolFeeTier: 3000
        }));
        vm.stopPrank();

        assertEq(factory.totalTokens(), 2);
    }

    function test_GetTokensPagination() public {
        // Create 3 tokens
        _createToken();
        vm.prank(trader1);
        factory.createToken(LaunchpadFactory.TokenParams({
            name: "Token2", symbol: "TK2", totalSupply: TOTAL_SUPPLY,
            metadataURI: "ipfs://h2", quoteToken: address(usdc), poolFeeTier: 3000
        }));
        vm.prank(trader2);
        factory.createToken(LaunchpadFactory.TokenParams({
            name: "Token3", symbol: "TK3", totalSupply: TOTAL_SUPPLY,
            metadataURI: "ipfs://h3", quoteToken: address(usdc), poolFeeTier: 3000
        }));

        address[] memory page1 = factory.getTokens(0, 2);
        assertEq(page1.length, 2);

        address[] memory page2 = factory.getTokens(2, 2);
        assertEq(page2.length, 1);
    }

    function test_CreateTokenAndBuy_AtomicSuccess() public {
        uint256 buyAmount = 100 * 1e6; // $100 USDC dev buy

        vm.startPrank(creator);
        usdc.approve(address(factory), buyAmount);

        (address token, address curve, uint256 tokensOut) = factory.createTokenAndBuy(
            LaunchpadFactory.TokenParams({
                name: "Dev Buy Token",
                symbol: "DEV",
                totalSupply: TOTAL_SUPPLY,
                metadataURI: "ipfs://devhash",
                quoteToken: address(usdc),
                poolFeeTier: 3000
            }),
            buyAmount,
            0
        );
        vm.stopPrank();

        assertNotEq(token, address(0));
        assertNotEq(curve, address(0));
        assertGt(tokensOut, 0, "Creator must receive tokens from dev buy");
        assertEq(LaunchToken(token).balanceOf(creator), tokensOut, "Creator balance must equal tokensOut");

        // Curve should hold the net quote and remaining tokens
        IBondingCurve.Reserves memory r = BondingCurve(curve).getReserves();
        assertGt(r.realQuoteReserve, 0, "Curve should hold quote from dev buy");
        assertEq(r.realTokenReserve, (TOTAL_SUPPLY * 8000) / 10000 - tokensOut);
    }
}
