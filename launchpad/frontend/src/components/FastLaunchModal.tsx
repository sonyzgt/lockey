"use client";

import { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract, useBalance } from "wagmi";
import { parseUnits, parseEventLogs, toHex } from "viem";
import { Rocket, X, Loader2, CheckCircle2, AlertCircle, Coins, Sparkles, ExternalLink } from "lucide-react";
import { CONTRACT_ADDRESSES } from "@/config/chain";
import { PONS_FACTORY_ABI, PONS_ROUTER_ABI } from "@/config/abis";
import { ParsedTweet } from "@/app/api/x-feed/route";

interface FastLaunchModalProps {
  tweet: ParsedTweet | null;
  isOpen: boolean;
  onClose: () => void;
}

export function FastLaunchModal({ tweet, isOpen, onClose }: FastLaunchModalProps) {
  const router = useRouter();
  const { address, isConnected } = useAccount();

  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [logoUrl, setLogoUrl] = useState("");
  const [description, setDescription] = useState("");
  const [devBuyEth, setDevBuyEth] = useState("");
  const [creatorFeePercent, setCreatorFeePercent] = useState<number>(1);
  const [statusError, setStatusError] = useState<string | null>(null);

  // Initialize or reset from tweet
  useEffect(() => {
    if (tweet) {
      setName(tweet.suggestedToken?.name || "Vana Narrative");
      setSymbol(tweet.suggestedToken?.symbol || "VNARR");
      
      const mediaImage = tweet.media?.[0]?.url;
      setLogoUrl(mediaImage || tweet.author.profileImageUrl || "/vana-logo.png");

      const tweetSource = tweet.tweetUrl ? `\n\nInspired by @${tweet.author.username}: ${tweet.tweetUrl}` : "";
      setDescription(`"${tweet.text}"${tweetSource}`);
      setDevBuyEth("");
      setStatusError(null);
    }
  }, [tweet]);

  // Read Protocol Settings
  const { data: launchFee } = useReadContract({
    address: CONTRACT_ADDRESSES.factory,
    abi: PONS_FACTORY_ABI,
    functionName: "launchFee",
  });

  const { data: expectedEconomics } = useReadContract({
    address: CONTRACT_ADDRESSES.factory,
    abi: PONS_FACTORY_ABI,
    functionName: "previewLaunchEconomics",
    args: [0n, "0x0000000000000000000000000000000000000000"],
  });

  const { data: userEthBalance } = useBalance({
    address: address,
  });

  const { writeContract, data: txHash, isPending: isSubmitting } = useWriteContract();
  const { data: txReceipt, isLoading: isWaitingTx, isSuccess: isCreated } = useWaitForTransactionReceipt({ hash: txHash });

  const redirectedRef = useRef(false);

  useEffect(() => {
    if (isCreated && txReceipt && !redirectedRef.current) {
      let tokenAddr: string | null = null;
      let curveAddr: string | null = null;
      try {
        const parsedLogs = parseEventLogs({
          abi: PONS_FACTORY_ABI,
          eventName: "TokenLaunched",
          logs: txReceipt.logs,
        });

        if (parsedLogs.length > 0) {
          const args = parsedLogs[0].args as { token?: string; curve?: string };
          tokenAddr = args.token || null;
          curveAddr = args.curve || null;
        }
      } catch (err) {
        console.warn("Could not parse TokenLaunched event from receipt:", err);
      }

      if (tokenAddr) {
        redirectedRef.current = true;
        // Register token in backend
        fetch("/api/tokens", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            token: tokenAddr,
            curve: curveAddr,
            deployer: address,
            name,
            symbol,
            logo: logoUrl,
            description,
            createdAt: new Date().toISOString(),
          }),
        }).catch((e) => console.warn("Could not save to /api/tokens:", e));

        setTimeout(() => {
          onClose();
          router.push(`/token/${tokenAddr}`);
        }, 1200);
      }
    }
  }, [isCreated, txReceipt, address, name, symbol, logoUrl, description, router, onClose]);

  if (!isOpen || !tweet) return null;

  const currentLaunchFee = launchFee ?? parseUnits("0.0005", 18);
  const parsedDevBuy = devBuyEth && Number(devBuyEth) > 0 ? parseUnits(devBuyEth, 18) : 0n;
  const totalRequiredEth = currentLaunchFee + parsedDevBuy;

  const isInsufficientEth = userEthBalance && userEthBalance.value < totalRequiredEth;

  const handleFastLaunch = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatusError(null);

    if (!isConnected || !address) {
      setStatusError("Please connect your Web3 wallet first.");
      return;
    }

    if (!name.trim() || !symbol.trim()) {
      setStatusError("Name and symbol are required.");
      return;
    }

    try {
      const salt = toHex(crypto.getRandomValues(new Uint8Array(32)));
      const fallbackEconomics = expectedEconomics || "0x0000000000000000000000000000000000000000000000000000000000000000";

      const tokenParams = {
        name: name.trim(),
        symbol: symbol.trim().toUpperCase(),
        logo: logoUrl.trim() || "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi",
        description: description.trim(),
        socials: {
          twitter: tweet.tweetUrl || `https://x.com/${tweet.author.username}`,
          telegram: "",
          discord: "",
          website: "",
          farcaster: "",
        },
        creatorFeeRecipient: address,
        creatorTaxBps: Math.min(Math.max(Math.round(creatorFeePercent * 100), 0), 1000),
        buybackEnabled: true,
        expectedEconomics: fallbackEconomics,
        salt,
      };

      if (parsedDevBuy > 0n) {
        writeContract({
          address: CONTRACT_ADDRESSES.launchAndBuy,
          abi: PONS_ROUTER_ABI,
          functionName: "launchAndBuy",
          args: [
            tokenParams,
            0n,
            "0x0000000000000000000000000000000000000000",
            parsedDevBuy,
            0n,
            address,
            [],
          ],
          value: totalRequiredEth,
        });
      } else {
        writeContract({
          address: CONTRACT_ADDRESSES.factory,
          abi: PONS_FACTORY_ABI,
          functionName: "launchToken",
          args: [
            tokenParams,
            0n,
            "0x0000000000000000000000000000000000000000",
          ],
          value: currentLaunchFee,
        });
      }
    } catch (err: unknown) {
      console.error("Fast launch error:", err);
      const msg = err instanceof Error ? err.message : "Failed to initiate token launch";
      setStatusError(msg);
    }
  };

  const handleOpenInFullStudio = () => {
    onClose();
    const params = new URLSearchParams({
      name: name.trim(),
      symbol: symbol.trim().toUpperCase(),
      logo: logoUrl.trim(),
      desc: description.trim(),
      twitter: tweet.tweetUrl || "",
    });
    router.push(`/create?${params.toString()}`);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fade-in">
      <div className="relative w-full max-w-xl sketch-card bg-[#06180d] p-6 sm:p-8 space-y-6 shadow-sketch-lg border-2 border-emerald-500 max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between pb-4 border-b border-dashed border-emerald-800/80">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded-sketch bg-[#0c2e1b] border-2 border-emerald-400 flex items-center justify-center text-emerald-300">
              <Rocket className="w-5 h-5 text-emerald-400" />
            </div>
            <div>
              <h2 className="text-2xl font-kalam font-bold text-white tracking-wide">
                Instant Meme Launch
              </h2>
              <p className="text-xs font-hand text-emerald-300/80">
                Deploying narrative token on Robinhood Chain Pons v2
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 sketch-btn-secondary text-slate-400 hover:text-white"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Origin Tweet Summary */}
        <div className="p-3.5 rounded-sketch bg-[#0c2e1b]/70 border border-emerald-700/50 flex items-start space-x-3 text-xs">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={tweet.author.profileImageUrl}
            alt={tweet.author.name}
            className="w-8 h-8 rounded-full border border-emerald-500/50 object-cover shrink-0"
          />
          <div className="flex-1 min-w-0">
            <div className="flex items-center space-x-1.5 font-hand font-bold text-white">
              <span className="truncate">{tweet.author.name}</span>
              <span className="text-emerald-400 font-mono text-[11px]">@{tweet.author.username}</span>
            </div>
            <p className="text-emerald-200/90 font-hand text-xs line-clamp-2 mt-0.5">
              &ldquo;{tweet.text}&rdquo;
            </p>
          </div>
        </div>

        {/* Launch Form */}
        <form onSubmit={handleFastLaunch} className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-hand font-bold text-slate-200 mb-1">
                Token Name *
              </label>
              <input
                type="text"
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full px-3 py-2 sketch-inset text-sm font-hand text-white focus:outline-none"
              />
            </div>
            <div>
              <label className="block text-xs font-hand font-bold text-slate-200 mb-1">
                Ticker / Symbol *
              </label>
              <input
                type="text"
                required
                maxLength={10}
                value={symbol}
                onChange={(e) => setSymbol(e.target.value.toUpperCase())}
                className="w-full px-3 py-2 sketch-inset text-sm font-hand uppercase text-emerald-300 font-bold focus:outline-none"
              />
            </div>
          </div>

          {/* Logo Preview & URL */}
          <div>
            <label className="block text-xs font-hand font-bold text-slate-200 mb-1">
              Logo URL (Auto-filled from Tweet / Avatar)
            </label>
            <div className="flex items-center space-x-3">
              <div className="w-11 h-11 rounded-sketch border-2 border-emerald-400 bg-[#0c2e1b] overflow-hidden shrink-0 flex items-center justify-center">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={logoUrl || "/vana-logo.png"}
                  alt="Preview"
                  className="w-full h-full object-cover"
                  onError={(e) => {
                    (e.target as HTMLImageElement).src = "/vana-logo.png";
                  }}
                />
              </div>
              <input
                type="text"
                value={logoUrl}
                onChange={(e) => setLogoUrl(e.target.value)}
                placeholder="https://... or ipfs://..."
                className="flex-1 px-3 py-2 sketch-inset text-xs font-mono text-emerald-200 focus:outline-none"
              />
            </div>
          </div>

          {/* Initial Dev Buy */}
          <div className="p-3 sketch-surface flex items-center justify-between">
            <div>
              <span className="text-xs font-hand font-bold text-white block">
                Initial Dev Buy (Optional)
              </span>
              <span className="text-[11px] font-hand text-slate-400 block">
                Snipe first batch on the curve in ETH
              </span>
            </div>
            <div className="w-32 relative">
              <input
                type="number"
                step="0.0001"
                min="0"
                placeholder="0.0 ETH"
                value={devBuyEth}
                onChange={(e) => setDevBuyEth(e.target.value)}
                className="w-full px-3 py-1.5 sketch-inset text-xs font-mono text-white text-right focus:outline-none"
              />
            </div>
          </div>

          {/* Royalty Rate */}
          <div className="space-y-1.5">
            <div className="flex items-center justify-between text-xs font-hand">
              <span className="font-bold text-slate-200">Creator Trading Royalty:</span>
              <span className="font-bold text-emerald-400">{creatorFeePercent}%</span>
            </div>
            <div className="grid grid-cols-4 gap-2">
              {[0, 1, 2, 5].map((fee) => (
                <button
                  key={fee}
                  type="button"
                  onClick={() => setCreatorFeePercent(fee)}
                  className={`py-1.5 rounded-sketch text-xs font-hand font-bold transition ${
                    creatorFeePercent === fee
                      ? "sketch-btn-primary text-slate-950"
                      : "sketch-btn-secondary text-slate-300"
                  }`}
                >
                  {fee}%
                </button>
              ))}
            </div>
          </div>

          {/* Error Message */}
          {statusError && (
            <p className="text-xs font-hand text-rose-400 flex items-center space-x-1.5">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{statusError}</span>
            </p>
          )}

          {/* Insufficient balance warning */}
          {isInsufficientEth && (
            <p className="text-xs font-hand text-amber-300 flex items-center space-x-1.5">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>Insufficient ETH balance for launch fee + initial dev buy.</span>
            </p>
          )}

          {/* Success state */}
          {isCreated && (
            <div className="p-3 rounded-sketch bg-emerald-950/80 border border-emerald-500 text-emerald-300 text-xs font-hand font-bold flex items-center space-x-2">
              <CheckCircle2 className="w-4 h-4 text-emerald-400 animate-bounce" />
              <span>Token deployed on Robinhood Chain! Redirecting to curve...</span>
            </div>
          )}

          {/* Actions */}
          <div className="pt-2 flex flex-col sm:flex-row items-center gap-3">
            <button
              type="submit"
              disabled={isSubmitting || isWaitingTx || isCreated || isInsufficientEth}
              className="w-full sm:flex-1 py-3 sketch-btn-primary text-slate-950 font-hand font-bold text-base flex items-center justify-center space-x-2 disabled:opacity-50"
            >
              {isSubmitting || isWaitingTx ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin text-slate-950" />
                  <span>{isSubmitting ? "Confirm in Wallet..." : "Deploying on Curve..."}</span>
                </>
              ) : (
                <>
                  <Rocket className="w-4 h-4" />
                  <span>🚀 1-Click Launch Token</span>
                </>
              )}
            </button>

            <button
              type="button"
              onClick={handleOpenInFullStudio}
              className="w-full sm:w-auto px-4 py-3 sketch-btn-secondary text-xs font-hand font-bold text-emerald-200 flex items-center justify-center space-x-1 hover:text-white"
            >
              <span>Customize in Studio</span>
              <ExternalLink className="w-3.5 h-3.5 ml-1" />
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
