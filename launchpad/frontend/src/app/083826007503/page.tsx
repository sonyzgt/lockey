"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import Link from "next/link";
import {
  useAccount,
  useConnect,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { formatUnits } from "viem";
import {
  ShieldAlert,
  ShieldCheck,
  ExternalLink,
  Lock,
  RefreshCw,
  Wallet,
  ArrowDownToLine,
  CheckCircle2,
} from "lucide-react";
import { CONTRACT_ADDRESSES, robinhoodChain } from "@/config/chain";
import {
  PONS_FACTORY_ABI,
  PONS_FEE_ESCROW_ABI,
} from "@/config/abis";
import { useToast } from "@/components/Toast";

// Strict Protocol Owner Address (Only this single address is permitted)
const STRICT_OWNER = "0xf3ad11919313422931572f2efcced6022d66f34c".toLowerCase();

export default function AdminDashboardPage() {
  const toast = useToast();
  const { address, isConnected } = useAccount();
  const { connectors, connect } = useConnect();

  // Strict authorization check: must match 0xf3ad11919313422931572f2efcced6022d66f34c
  const isOwner = isConnected && !!address && address.toLowerCase() === STRICT_OWNER;

  // Read Protocol Trading Fee Rate (BPS)
  const { data: protocolFeeBps, refetch: refetchProtocolBps } = useReadContract({
    address: CONTRACT_ADDRESSES.factory,
    abi: PONS_FACTORY_ABI,
    functionName: "protocolFeeBps",
  });

  // Read Token List
  const { data: tokenList, refetch: refetchTokens } = useReadContract({
    address: CONTRACT_ADDRESSES.factory,
    abi: PONS_FACTORY_ABI,
    functionName: "getTokens",
    args: [BigInt(0), BigInt(50)],
  });

  // Write contract hook for Claiming Fees
  const {
    writeContract,
    data: txHash,
    isPending: isSubmitting,
    error: writeError,
    reset: resetWrite,
  } = useWriteContract();

  const { isLoading: isWaitingTx, isSuccess: txSuccess } = useWaitForTransactionReceipt({
    hash: txHash,
  });

  const [activeAction, setActiveAction] = useState<string>("");
  const lastHandledTxRef = useRef<string | null>(null);

  const refetchAll = useCallback(() => {
    refetchProtocolBps();
    refetchTokens();
  }, [refetchProtocolBps, refetchTokens]);

  useEffect(() => {
    if (txSuccess && txHash && lastHandledTxRef.current !== txHash) {
      lastHandledTxRef.current = txHash;
      toast.success(
        "Protocol Fees Claimed!",
        `${activeAction || "Fee withdrawal"} successfully confirmed on Robinhood Chain. ETH transferred to your wallet.`,
        txHash
      );
      refetchAll();
      setActiveAction("");
      resetWrite();
    }
  }, [txSuccess, txHash, activeAction, toast, resetWrite, refetchAll]);

  useEffect(() => {
    if (writeError) {
      toast.error(
        "Claim Failed",
        writeError.message?.split("\n")[0] || "Transaction was rejected or reverted."
      );
      setActiveAction("");
    }
  }, [writeError, toast]);

  const isBusy = isSubmitting || isWaitingTx;

  // Handle Claim All Protocol Fees
  const handleClaimAllFees = () => {
    if (!address || !tokenList || tokenList.length === 0) return;
    setActiveAction("Claiming All Protocol Fees");
    writeContract({
      address: CONTRACT_ADDRESSES.factory,
      abi: PONS_FACTORY_ABI,
      functionName: "withdrawProtocolFeesMultiple",
      args: [tokenList as `0x${string}`[], address],
    });
  };

  // ─── Unauthorized / Connect Wallet View ──────────────────────────────────────────
  if (!isConnected) {
    return (
      <div className="max-w-2xl mx-auto py-24 px-4 text-center space-y-6">
        <div className="w-20 h-20 mx-auto rounded-3xl clay-card border border-sky-500/30 flex items-center justify-center text-sky-400 shadow-xl shadow-sky-900/30">
          <Lock className="w-10 h-10" />
        </div>
        <div className="space-y-2">
          <span className="px-3 py-1 clay-badge text-[11px] font-mono text-sky-300">
            CONFIDENTIAL PROTOCOL ROUTE • /083826007503
          </span>
          <h1 className="text-3xl font-black text-white">LOCKEY Protocol Fee Vault</h1>
          <p className="text-sm text-slate-400 max-w-md mx-auto">
            This dashboard is strictly reserved for the protocol owner to withdraw accumulated platform revenue.
          </p>
        </div>
        <div>
          <button
            onClick={() => {
              const c = connectors[0];
              if (c) connect({ connector: c });
            }}
            className="px-6 py-3.5 clay-btn-primary text-slate-950 font-black text-sm inline-flex items-center space-x-2"
          >
            <Wallet className="w-4 h-4" />
            <span>Connect Owner Wallet</span>
          </button>
        </div>
      </div>
    );
  }

  if (!isOwner) {
    return (
      <div className="max-w-2xl mx-auto py-24 px-4 text-center space-y-6">
        <div className="w-20 h-20 mx-auto rounded-3xl clay-card border border-rose-500/30 flex items-center justify-center text-rose-400 shadow-xl shadow-rose-950/30">
          <ShieldAlert className="w-10 h-10" />
        </div>
        <div className="space-y-2">
          <span className="px-3 py-1 rounded-full bg-rose-500/10 border border-rose-500/30 text-[11px] font-mono text-rose-400">
            403 UNAUTHORIZED ACCESS
          </span>
          <h1 className="text-3xl font-black text-white">Restricted Protocol Area</h1>
          <p className="text-sm text-slate-400 max-w-lg mx-auto leading-relaxed">
            Connected address <span className="font-mono text-rose-300 bg-rose-950/50 px-2 py-0.5 rounded border border-rose-800/40">{address ? `${address.slice(0, 6)}...${address.slice(-4)}` : "Unknown"}</span> is not the authorized owner.
            This vault is strictly reserved for <span className="font-mono text-sky-300 bg-sky-950/50 px-2 py-0.5 rounded border border-sky-800/40">0xf3ad...f34c</span>.
          </p>
        </div>
        <div>
          <Link
            href="/"
            className="px-6 py-3 clay-btn-secondary text-slate-200 font-bold text-xs inline-flex items-center space-x-2"
          >
            <span>Return to Explore</span>
          </Link>
        </div>
      </div>
    );
  }

  // ─── Authorized Owner View: Claim Protocol Fee Dashboard ──────────────────────
  return (
    <div className="max-w-5xl mx-auto space-y-8 pb-24">
      {/* Header Banner */}
      <div className="clay-card p-6 sm:p-8 relative overflow-hidden border border-sky-500/30">
        <div className="absolute -right-10 -bottom-10 w-64 h-64 rounded-full bg-sky-500/10 blur-3xl pointer-events-none" />
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6 relative z-10">
          <div className="space-y-2">
            <div className="flex items-center space-x-2.5">
              <span className="px-3 py-1 clay-badge text-[10px] font-mono text-sky-300 flex items-center space-x-1.5">
                <Lock className="w-3 h-3 text-sky-400" />
                <span>CONFIDENTIAL ROUTE • /083826007503</span>
              </span>
              <span className="px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-[10px] font-mono text-emerald-400 flex items-center space-x-1">
                <ShieldCheck className="w-3 h-3" />
                <span>AUTHORIZED OWNER: 0xf3ad...f34c</span>
              </span>
            </div>
            <h1 className="text-3xl sm:text-4xl font-black text-white tracking-tight">
              Protocol Fee Vault
            </h1>
            <p className="text-xs sm:text-sm text-slate-300 max-w-2xl leading-relaxed">
              Withdraw accumulated protocol trading royalties in USDC directly to your owner wallet. Creator royalties remain 100% isolated and untouched.
            </p>
          </div>

          <div className="flex items-center space-x-3 self-start md:self-auto">
            <button
              onClick={refetchAll}
              disabled={isBusy}
              className="p-2.5 clay-btn-secondary text-slate-300 hover:text-white transition disabled:opacity-50"
              title="Refresh Protocol Balances"
            >
              <RefreshCw className={`w-4 h-4 ${isBusy ? "animate-spin" : ""}`} />
            </button>
            <a
              href={`${robinhoodChain.blockExplorers.default.url}/address/${CONTRACT_ADDRESSES.feeEscrow}`}
              target="_blank"
              rel="noopener noreferrer"
              className="px-4 py-2.5 clay-btn-secondary text-xs font-mono text-emerald-300 flex items-center space-x-1.5"
            >
              <span>FeeEscrow</span>
              <ExternalLink className="w-3.5 h-3.5" />
            </a>
          </div>
        </div>
      </div>

      {/* Hero Vault Overview & Claim All Action */}
      <ProtocolFeeSummaryCard
        tokens={tokenList as `0x${string}`[] | undefined}
        protocolFeeBps={protocolFeeBps ? Number(protocolFeeBps) : 30}
        ownerAddress={address}
        isBusy={isBusy}
        onClaimAll={handleClaimAllFees}
      />
    </div>
  );
}

// ─── Hero Protocol Fee Summary Component ─────────────────────────────────────
function ProtocolFeeSummaryCard({
  tokens,
  protocolFeeBps,
  ownerAddress,
  isBusy,
  onClaimAll,
}: {
  tokens?: `0x${string}`[];
  protocolFeeBps: number;
  ownerAddress?: `0x${string}`;
  isBusy: boolean;
  onClaimAll: () => void;
}) {
  return (
    <div className="clay-card p-6 sm:p-8 border border-[#1a6336] space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* Total Protocol Fees */}
        <div className="md:col-span-2 space-y-4">
          <div className="space-y-1">
            <div className="flex items-center space-x-2">
              <span className="text-xs uppercase font-mono tracking-wider text-slate-400 font-semibold">
                Total Claimable Protocol Revenue
              </span>
              <span className="px-2 py-0.5 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 text-[10px] font-mono">
                Instant ETH Payout
              </span>
            </div>
            <div className="flex items-baseline space-x-3">
              <span className="text-4xl sm:text-5xl font-black font-mono text-transparent bg-clip-text bg-gradient-to-r from-emerald-400 to-green-300">
                <TotalProtocolFeeAmount tokens={tokens} />
              </span>
              <span className="text-base font-mono font-bold text-slate-400">ETH</span>
            </div>
            <p className="text-xs text-slate-400 leading-relaxed max-w-xl">
              Accrues automatically on every buy and sell swap. Withdrawing sends 100% of accumulated protocol royalties directly to your wallet in native ETH.
            </p>
          </div>

          <div>
            <button
              onClick={onClaimAll}
              disabled={isBusy || !tokens || tokens.length === 0}
              className="px-6 py-3.5 sketch-btn-primary text-slate-950 font-black text-sm inline-flex items-center space-x-2 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <ArrowDownToLine className="w-4 h-4" />
              <span>{isBusy ? "Processing Claim..." : "Claim All Protocol Fees"}</span>
            </button>
          </div>
        </div>

        {/* Security & Config Info */}
        <div className="clay-surface p-5 space-y-3 flex flex-col justify-between border border-[#1a6336]">
          <div className="space-y-2">
            <div className="text-xs font-mono uppercase text-slate-400 font-semibold">
              Protocol Specs
            </div>
            <div className="space-y-1 text-xs">
              <div className="flex justify-between py-1 border-b border-emerald-900/40">
                <span className="text-slate-400">Protocol Fee:</span>
                <span className="text-emerald-300 font-mono font-bold">
                  {(protocolFeeBps / 100).toFixed(2)}% (30 BPS)
                </span>
              </div>
              <div className="flex justify-between py-1 border-b border-emerald-900/40">
                <span className="text-slate-400">Creator Royalty:</span>
                <span className="text-emerald-300 font-mono font-bold">0.70% (Isolated)</span>
              </div>
              <div className="flex justify-between py-1">
                <span className="text-slate-400">Payout Recipient:</span>
                <span className="text-slate-200 font-mono">
                  {ownerAddress ? `${ownerAddress.slice(0, 6)}...${ownerAddress.slice(-4)}` : "..."}
                </span>
              </div>
            </div>
          </div>

          <div className="pt-2 text-[10px] text-slate-500 font-mono flex items-center space-x-1.5">
            <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400 flex-shrink-0" />
            <span>Non-custodial isolation guaranteed</span>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Calculate Total Fees across all tokens ──────────────────────────────────
function TotalProtocolFeeAmount({ tokens }: { tokens?: `0x${string}`[] }) {
  if (!tokens || tokens.length === 0) return <>0.0000</>;
  return <TotalProtocolFeeCalculator />;
}

function TotalProtocolFeeCalculator() {
  // Read protocol fees from FeeEscrow contract
  const { data: ethBalance } = useReadContract({
    address: CONTRACT_ADDRESSES.feeEscrow,
    abi: PONS_FEE_ESCROW_ABI,
    functionName: "claimableProtocolFees",
    args: ["0x0000000000000000000000000000000000000000"],
  });

  const total = ethBalance ? Number(formatUnits(ethBalance, 18)) : 0;
  return <>{total.toFixed(4)}</>;
}
