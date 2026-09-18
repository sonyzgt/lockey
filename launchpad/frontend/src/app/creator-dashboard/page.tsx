"use client";

import { useEffect, useRef } from "react";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatUnits } from "viem";
import { Coins, Sparkles, Loader2, ShieldCheck, Award } from "lucide-react";
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
        <div className="inline-flex items-center space-x-2 px-3 py-1 sketch-badge bg-[#0c2d1b] text-emerald-300 text-xs font-hand font-bold tracking-wide">
          <Sparkles className="w-4 h-4 text-emerald-400" />
          <span>Pons Protocol Payouts • Robinhood Chain</span>
        </div>
        <h1 className="text-4xl sm:text-5xl font-kalam font-bold text-white tracking-wide flex items-center space-x-2">
          <span>Royalty Fee Kreator</span>
          <span className="text-3xl">💰</span>
        </h1>
        <p className="text-base font-hand text-slate-300">
          Pantau royalti trading dari token yang Anda buat dan klaim akumulasi ETH langsung dari kontrak Pons Fee Escrow.
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
        <div className="p-6 sketch-card space-y-2 relative">
          <div className="sketch-tape -top-2.5 left-8 w-24 h-4 rotate-1"></div>
          <span className="text-xs font-hand font-bold text-slate-400 uppercase tracking-wider block">Aset Pembayaran Royalti</span>
          <div className="text-3xl font-bold font-mono text-emerald-300">Native ETH</div>
          <p className="text-xs font-hand text-slate-400 leading-relaxed">
            Royalti otomatis diakumulasikan dalam mata uang native ETH pada setiap transaksi buy & sell di bonding curve maupun Uniswap v4.
          </p>
        </div>

        <div className="p-6 sketch-card space-y-2 relative">
          <div className="sketch-tape -top-2.5 right-8 w-24 h-4 -rotate-1"></div>
          <span className="text-xs font-hand font-bold text-slate-400 uppercase tracking-wider block">Kontrak Fee Escrow</span>
          <div className="text-xs font-mono text-emerald-400 truncate">
            {CONTRACT_ADDRESSES.feeEscrow}
          </div>
          <p className="text-xs font-hand text-slate-400 leading-relaxed">
            Dana royalti disimpan dengan aman di kontrak escrow independen dan dapat ditarik kapan saja (pull-based withdrawal).
          </p>
        </div>
      </div>

      {/* Claim Voucher Card */}
      <div className="sketch-card p-6 sm:p-8 space-y-6 relative bg-[#082113]">
        {/* Top Tape */}
        <div className="sketch-tape -top-3 left-1/2 -translate-x-1/2 w-36 h-5 rotate-1"></div>

        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-5 pb-6 border-b-2 border-dashed border-[#1a6336]">
          <div className="space-y-1">
            <span className="text-xs font-hand font-bold text-slate-400 uppercase tracking-wider block">
              Saldo Royalti Yang Siap Diklaim
            </span>
            <div className="text-4xl sm:text-5xl font-bold font-mono text-white flex items-center space-x-3">
              <Coins className="w-9 h-9 text-emerald-400" />
              <span>{formattedClaimable.toFixed(6)} ETH</span>
            </div>
            <p className="text-xs font-hand text-slate-400">
              Dapat ditarik ke wallet Anda kapan saja tanpa masa vesting atau batas waktu.
            </p>
          </div>

          <button
            onClick={handleClaim}
            disabled={!isConnected || formattedClaimable === 0 || isClaiming || isWaitingClaim}
            className="py-3 px-7 sketch-btn-primary text-slate-950 font-bold text-lg flex items-center justify-center space-x-2 disabled:opacity-40 disabled:cursor-not-allowed shrink-0"
          >
            {isClaiming || isWaitingClaim ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" />
                <span>Mengklaim ETH...</span>
              </>
            ) : (
              <span>Klaim {formattedClaimable > 0 ? `${formattedClaimable.toFixed(4)} ETH` : "Royalti"}</span>
            )}
          </button>
        </div>

        <div className="p-4 sketch-surface rounded-sketch space-y-2 text-xs font-hand text-slate-300">
          <div className="font-bold text-white text-sm flex items-center space-x-2">
            <ShieldCheck className="w-4 h-4 text-emerald-400" />
            <span>Bagaimana Cara Kerja Royalti Kreator?</span>
          </div>
          <p className="leading-relaxed text-slate-400 text-xs">
            Setiap ada transaksi trading di token curve Anda, persentase pajak royalti kreator yang Anda tentukan saat launch otomatis tercatat. Dana tersebut masuk ke Fee Escrow Pons dan dapat Anda klaim langsung ke wallet tanpa potongan biaya tambahan.
          </p>
        </div>
      </div>
    </div>
  );
}
