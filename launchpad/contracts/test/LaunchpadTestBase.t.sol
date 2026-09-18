// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {LaunchpadFactory} from "../src/LaunchpadFactory.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {MigrationManager} from "../src/MigrationManager.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {IDexAdapter} from "../src/interfaces/IDexAdapter.sol";
import {IBondingCurve} from "../src/interfaces/IBondingCurve.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ─── Mock Contracts ───────────────────────────────────────────────────────────

/// @dev Simple ERC20 mock for USDC (6 decimals)
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev Mock DEX adapter that records calls and actually pulls tokens to simulate real behavior
contract MockDexAdapter is IDexAdapter {
    bool public _createCalled;
    address public lastPool;
    uint256 public lastTokenId;

    function createCalled() external view returns (bool) { return _createCalled; }

    function createPoolAndAddLiquidity(AddLiquidityParams calldata params)
        external
        override
        returns (LiquidityResult memory result)
    {
        _createCalled = true;
        // Pull tokens from caller (MigrationManager) to simulate DEX consumption
        IERC20(params.token).transferFrom(msg.sender, address(this), params.tokenAmount);
        IERC20(params.quoteToken).transferFrom(msg.sender, address(this), params.quoteAmount);

        lastPool = address(uint160(uint256(keccak256(abi.encode(params.token, params.quoteToken)))));
        lastTokenId = 1;

        result.pool = lastPool;
        result.tokenAmountAdded = params.tokenAmount;
        result.quoteAmountAdded = params.quoteAmount;
        result.lpTokenIdOrAmount = 1;
    }

    function getPool(address tokenA, address tokenB, uint24)
        external
        view
        override
        returns (address pool)
    {
        pool = address(uint160(uint256(keccak256(abi.encode(tokenA, tokenB)))));
    }
}

// ─── Base Test Setup ──────────────────────────────────────────────────────────

contract LaunchpadTestBase is Test {
    // ─── Actors ───────────────────────────────────────────────────────────────
    address admin      = makeAddr("admin");
    address creator    = makeAddr("creator");
    address trader1    = makeAddr("trader1");
    address trader2    = makeAddr("trader2");
    address treasury   = makeAddr("treasury");

    // ─── Contracts ────────────────────────────────────────────────────────────
    MockUSDC usdc;
    MockDexAdapter dexAdapter;
    FeeManager feeManager;
    MigrationManager migrationManager;
    LaunchpadFactory factory;

    // ─── Token Params ─────────────────────────────────────────────────────────
    uint256 constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;
    // Virtual reserves: virtualQuote=5000 USDC, virtualToken=1B token
    // initialMC = (5_000e6 × 1B_1e18) / (1B_1e18) = 5_000e6 = $5,000 ✓
    // k = 5_000e6 × 1B_1e18 = 5e36
    // To graduation $20K: realQuote accumulated = $15,000, tokensSold ≈ 750M
    uint256 constant VIRT_QUOTE_PER_BILLION = 5_000 * 1e6;       // $5,000 USDC
    uint256 constant VIRT_TOKEN_PER_BILLION = 1_000_000_000 * 1e18; // 1B token
    uint256 constant INITIAL_MC  = 5_000 * 1e6;   // $5,000
    uint256 constant GRAD_MC     = 20_000 * 1e6;  // $20,000
    uint256 constant CREATOR_FEE = 70;  // 0.7%
    uint256 constant PROTOCOL_FEE = 30; // 0.3%

    function setUp() public virtual {
        vm.startPrank(admin);

        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy mock DEX adapter
        dexAdapter = new MockDexAdapter();

        // Deploy FeeManager
        feeManager = new FeeManager(admin);

        // Deploy MigrationManager
        migrationManager = new MigrationManager(admin, address(dexAdapter));

        // Deploy Factory
        factory = new LaunchpadFactory(
            admin,
            address(feeManager),
            address(migrationManager),
            address(usdc),
            treasury,    // creation fee recipient
            CREATOR_FEE,
            PROTOCOL_FEE,
            VIRT_QUOTE_PER_BILLION,
            VIRT_TOKEN_PER_BILLION,
            INITIAL_MC,
            GRAD_MC
        );

        // Transfer ownership to factory
        feeManager.transferOwnership(address(factory));
        migrationManager.transferOwnership(address(factory));

        vm.stopPrank();

        // Fund traders with USDC
        usdc.mint(trader1, 100_000 * 1e6);
        usdc.mint(trader2, 100_000 * 1e6);
        usdc.mint(creator, 10_000 * 1e6);
    }

    /// @dev Creates a token and returns (token, curve) addresses (warps past 5s snipe window for normal tests)
    function _createToken() internal returns (address token, address curve) {
        (token, curve) = _createTokenAtLaunch();
        // Warp past the 5-second snipe window so standard tests trade with normal 1% fee
        vm.warp(block.timestamp + 10);
    }

    /// @dev Creates a token and returns (token, curve) addresses at the exact launch timestamp
    function _createTokenAtLaunch() internal returns (address token, address curve) {
        vm.startPrank(creator);
        (token, curve) = factory.createToken(LaunchpadFactory.TokenParams({
            name: "Test Token",
            symbol: "TEST",
            totalSupply: TOTAL_SUPPLY,
            metadataURI: "ipfs://QmTestHash123",
            quoteToken: address(usdc),
            poolFeeTier: 3000
        }));
        vm.stopPrank();
    }

    /// @dev Buys tokens for a trader. Returns tokensOut.
    function _buy(address trader, address curve, uint256 usdcAmount) internal returns (uint256 tokensOut) {
        vm.startPrank(trader);
        usdc.approve(curve, usdcAmount);
        tokensOut = BondingCurve(curve).buy(usdcAmount, 0, block.timestamp + 300);
        vm.stopPrank();
    }

    /// @dev Sells tokens for a trader. Returns quoteOut.
    function _sell(address trader, address tokenAddr, address curve, uint256 tokenAmount) internal returns (uint256 quoteOut) {
        vm.startPrank(trader);
        LaunchToken(tokenAddr).approve(curve, tokenAmount);
        quoteOut = BondingCurve(curve).sell(tokenAmount, 0, block.timestamp + 300);
        vm.stopPrank();
    }
}
