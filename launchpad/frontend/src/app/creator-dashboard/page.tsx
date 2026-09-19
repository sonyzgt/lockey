"use client";

import { useEffect, useRef } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatUnits } from "viem";
import { Coins, Sparkles, Loader2, ShieldCheck } from "lucide-react";
import { CONTRACT_ADDRESSES } from "@/config/chain";
import { PONS_FEE_ESCROW_ABI } from "@/config/abis";
import { useToast } from "@/components/Toast";

export default function CreatorDashboardPage() {
  const toast = useToast();
  const { address, isConnected } = useAccount();

  // Read native ETH claimable from Pons Fee Escrow
  const { data: claimableEth, refetch: refetchClaimable } = useReadContract({
    address: CONTRACT_ADDRESSES.feeEscrow,
    abi: PONS_FEE_ESCROW_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 5000 },
  });

  const { writeContract, data: txHash, isPending: isClaiming, error: claimError } = useWriteContract();
  const { isLoading: isWaitingClaim, isSuccess: claimSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const notifiedClaimTxRef = useRef<string | null>(null);

  useEffect(() => {
    if (claimSuccess && txHash && notifiedClaimTxRef.current !== txHash) {
      notifiedClaimTxRef.current = txHash;
      refetchClaimable();
      toast.success(
        "Creator Royalties Claimed!",
        "Accumulated ETH fees have been transferred directly to your wallet from Pons Fee Escrow.",
        txHash
      );
    }
  }, [claimSuccess, txHash, refetchClaimable, toast]);

  useEffect(() => {
    if (claimError) {
      toast.error(
        "Claim Failed",
        claimError.message?.split("\n")[0] || "Failed to claim creator royalties."
      );
    }
  }, [claimError, toast]);

  const formattedClaimable = claimableEth ? Number(formatUnits(claimableEth, 18)) : 0;

  const handleClaim = () => {
    writeContract({
      address: CONTRACT_ADDRESSES.feeEscrow,
      abi: PONS_FEE_ESCROW_ABI,
      functionName: "claim",
    });
  };

  return (
    <div className="max-w-4xl mx-auto space-y-8 pb-20">
      <div className="space-y-2">
        <div className="inline-flex items-center space-x-2 px-3 py-1 rounded-md bg-yellow-400/10 text-yellow-400 text-xs font-mono font-bold tracking-wide border border-yellow-400/30">
          <Sparkles className="w-4 h-4 text-yellow-400" />
          <span>Pons Protocol Payouts • Robinhood Chain</span>
        </div>
        <h1 className="text-3xl sm:text-4xl font-extrabold text-white tracking-tight flex items-center space-x-2">
          <span>Creator Royalty Fees</span>
          <span className="text-3xl">💰</span>
        </h1>
        <p className="text-sm text-zinc-400">
          Monitor trading royalties from tokens you have created and claim accumulated ETH directly from the Pons Fee Escrow contract.
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
        <div className="p-6 bg-[#121318] border border-zinc-800 rounded-2xl space-y-2 shadow-sm">
          <span className="text-xs font-semibold text-zinc-400 uppercase tracking-wider block">Royalty Payout Asset</span>
          <div className="text-3xl font-bold font-mono text-yellow-400">Native ETH</div>
          <p className="text-xs text-zinc-400 leading-relaxed font-sans">
            Royalties are automatically accrued in native ETH on every buy &amp; sell trade across both the bonding curve and Uniswap v4.
          </p>
        </div>

        <div className="p-6 bg-[#121318] border border-zinc-800 rounded-2xl space-y-2 shadow-sm">
          <span className="text-xs font-semibold text-zinc-400 uppercase tracking-wider block">Fee Escrow Contract</span>
          <div className="text-xs font-mono text-yellow-400 truncate">
            {CONTRACT_ADDRESSES.feeEscrow}
          </div>
          <p className="text-xs text-zinc-400 leading-relaxed font-sans">
            Royalty funds are stored securely in an independent escrow contract and can be withdrawn anytime (pull-based withdrawal).
          </p>
        </div>
      </div>

      {/* Claim Voucher Card */}
      <div className="p-6 sm:p-8 space-y-6 bg-[#121318] border border-zinc-800 rounded-2xl shadow-sm">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-5 pb-6 border-b border-zinc-800">
          <div className="space-y-1">
            <span className="text-xs font-semibold text-zinc-400 uppercase tracking-wider block">
              Claimable Royalty Balance
            </span>
            <div className="text-4xl sm:text-5xl font-bold font-mono text-white flex items-center space-x-3">
              <Coins className="w-9 h-9 text-yellow-400" />
              <span>{formattedClaimable.toFixed(6)} ETH</span>
            </div>
            <p className="text-xs text-zinc-400 font-sans">
              Available for withdrawal to your wallet anytime with zero vesting or lockup.
            </p>
          </div>

          <button
            onClick={handleClaim}
            disabled={!isConnected || formattedClaimable === 0 || isClaiming || isWaitingClaim}
            className="py-3 px-7 rounded-lg bg-yellow-400 hover:bg-yellow-300 text-black font-bold text-base flex items-center justify-center space-x-2 disabled:opacity-40 disabled:cursor-not-allowed shrink-0 transition-colors shadow-sm"
          >
            {isClaiming || isWaitingClaim ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin text-black" />
                <span>Claiming ETH...</span>
              </>
            ) : (
              <span>Claim {formattedClaimable > 0 ? `${formattedClaimable.toFixed(4)} ETH` : "Royalties"}</span>
            )}
          </button>
        </div>

        <div className="p-4 sketch-surface rounded-sketch space-y-2 text-xs font-hand text-slate-300">
          <div className="font-bold text-white text-sm flex items-center space-x-2">
            <ShieldCheck className="w-4 h-4 text-emerald-400" />
            <span>How Do Creator Royalties Work?</span>
          </div>
          <p className="leading-relaxed text-slate-400 text-xs">
            Every time a trade executes on your token&apos;s bonding curve, the creator royalty percentage configured at launch is automatically accrued. Funds accumulate in the Pons Fee Escrow contract and can be claimed directly into your wallet without additional platform fees.
          </p>
        </div>
      </div>
    </div>
  );
}
