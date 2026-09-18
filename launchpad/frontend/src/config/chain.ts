import { defineChain } from "viem";

/**
 * Robinhood Chain configuration for Wagmi / Viem.
 * Chain ID: 4663
 * Native Gas Currency: ETH (18 Decimals)
 */
export const robinhoodChain = defineChain({
  id: Number(process.env.NEXT_PUBLIC_CHAIN_ID || 4663),
  name: process.env.NEXT_PUBLIC_CHAIN_NAME || "Robinhood Chain",
  nativeCurrency: {
    name: "Ether",
    symbol: "ETH",
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: [process.env.NEXT_PUBLIC_RPC_URL || "https://rpc.mainnet.chain.robinhood.com"],
    },
  },
  blockExplorers: {
    default: {
      name: "Blockscout",
      url: process.env.NEXT_PUBLIC_BLOCK_EXPLORER_URL || "https://robinhoodchain.blockscout.com",
    },
  },
  testnet: false,
});

/**
 * Official Pons v2 Protocol Contracts on Robinhood Chain (Chain ID: 4663)
 * Reference: https://docs.ponsfamily.com/v2#contracts
 */
export const CONTRACT_ADDRESSES = {
  factory: (process.env.NEXT_PUBLIC_FACTORY_ADDRESS || "0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e") as `0x${string}`,
  launchAndBuy: (process.env.NEXT_PUBLIC_LAUNCH_AND_BUY_ADDRESS || "0xe33E9E479dF8802cb0866d5d05258bEc4cF62948") as `0x${string}`,
  feeEscrow: (process.env.NEXT_PUBLIC_FEE_ESCROW_ADDRESS || "0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e") as `0x${string}`,
  buybackVault: (process.env.NEXT_PUBLIC_BUYBACK_VAULT_ADDRESS || "0x42df2a798f82289E177311362e8f5ccC45c1219c") as `0x${string}`,
  launchLocker: (process.env.NEXT_PUBLIC_LAUNCH_LOCKER_ADDRESS || "0x267444D099b10fB5Ed7c3Cc7B7c767AdcA574952") as `0x${string}`,
  memeHook: (process.env.NEXT_PUBLIC_MEME_HOOK_ADDRESS || "0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044") as `0x${string}`,
  launchDeployer: (process.env.NEXT_PUBLIC_LAUNCH_DEPLOYER_ADDRESS || "0x3711ceA4feaDE896C913C68F01Eda97Cb06D1A42") as `0x${string}`,
  graduationExecutor: (process.env.NEXT_PUBLIC_GRADUATION_EXECUTOR_ADDRESS || "0xC7819B64A1dAECD7eC19856d026cb14EfBd89046") as `0x${string}`,
  graduationGuard: (process.env.NEXT_PUBLIC_GRADUATION_GUARD_ADDRESS || "0xf5695117b99B6f6401e67d4195BD653628176C6C") as `0x${string}`,
  // Legacy aliases for backward compatibility
  feeManager: (process.env.NEXT_PUBLIC_FEE_ESCROW_ADDRESS || "0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e") as `0x${string}`,
  migrationManager: "0x0000000000000000000000000000000000000000" as `0x${string}`,
  uniswapV4Adapter: (process.env.NEXT_PUBLIC_MEME_HOOK_ADDRESS || "0xE5e702641Ea86F4ae6cC3cDaeD2B886f976Be044") as `0x${string}`,
  usdc: "0x0000000000000000000000000000000000000000" as `0x${string}`,
};
