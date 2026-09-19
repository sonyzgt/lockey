"use client";

import { useState, useEffect, useRef, useMemo } from "react";
import { useParams } from "next/navigation";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, useBalance } from "wagmi";
import { formatUnits, parseUnits } from "viem";
import { TrendingUp, ArrowDownUp, ShieldCheck, Flame, ExternalLink, AlertCircle, Globe, MessageSquare, Send, Loader2, RefreshCw } from "lucide-react";
import { CONTRACT_ADDRESSES } from "@/config/chain";
import { PONS_FACTORY_ABI, PONS_CURVE_ABI, PONS_TOKEN_ABI, ERC20_ABI } from "@/config/abis";
import { useToast } from "@/components/Toast";
import { RealTradingChart } from "@/components/RealTradingChart";
import { useEthPrice, formatUsd } from "@/hooks/useEthPrice";

export default function TokenDetailPage() {
  const toast = useToast();
  const params = useParams();
  const tokenAddress = params.address as `0x${string}`;
  const { address, isConnected } = useAccount();

  const [activeTab, setActiveTab] = useState<"buy" | "sell">("buy");
  const [amountInput, setAmountInput] = useState("");
  const [tradeCount, setTradeCount] = useState(0);
  const [liveVolumeEth, setLiveVolumeEth] = useState<number>(0);
  const ethPriceUsd = useEthPrice();

  // 1. Read Launch Record from Pons Factory
  const { data: launchRecord, refetch: refetchLaunchRecord, isLoading: isLoadingLaunch } = useReadContract({
    address: CONTRACT_ADDRESSES.factory,
    abi: PONS_FACTORY_ABI,
    functionName: "getLaunchedToken",
    args: [tokenAddress],
  });

  const curveAddress = launchRecord?.curve && launchRecord.curve !== "0x0000000000000000000000000000000000000000"
    ? launchRecord.curve
    : undefined;

  // 2. Token ERC20 Info & Metadata from Token contract
  const { data: tokenName } = useReadContract({ address: tokenAddress, abi: PONS_TOKEN_ABI, functionName: "name" });
  const { data: tokenSymbol } = useReadContract({ address: tokenAddress, abi: PONS_TOKEN_ABI, functionName: "symbol" });
  const { data: tokenInfo } = useReadContract({ address: tokenAddress, abi: PONS_TOKEN_ABI, functionName: "getTokenInfo" });
  
  const { data: userTokenBalance, refetch: refetchTokenBalance } = useReadContract({
    address: tokenAddress,
    abi: PONS_TOKEN_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
  });

  const { data: userEthBalance, refetch: refetchEthBalance } = useBalance({
    address: address,
  });

  // 3. Curve State & Pricing
  const { data: reserves, refetch: refetchReserves } = useReadContract({
    address: curveAddress,
    abi: PONS_CURVE_ABI,
    functionName: "getReserves",
    query: { enabled: !!curveAddress, refetchInterval: 3000 },
  });

  const { data: realQuote, refetch: refetchRealQuote } = useReadContract({
    address: curveAddress,
    abi: PONS_CURVE_ABI,
    functionName: "realQuoteReserve",
    query: { enabled: !!curveAddress, refetchInterval: 3000 },
  });

  const { data: sellableTokens, refetch: refetchSellable } = useReadContract({
    address: curveAddress,
    abi: PONS_CURVE_ABI,
    functionName: "sellableTokens",
    query: { enabled: !!curveAddress, refetchInterval: 3000 },
  });

  const { data: readyToGraduate, refetch: refetchReadyGraduate } = useReadContract({
    address: curveAddress,
    abi: PONS_CURVE_ABI,
    functionName: "readyToGraduate",
    query: { enabled: !!curveAddress },
  });

  const { data: graduated, refetch: refetchGraduated } = useReadContract({
    address: curveAddress,
    abi: PONS_CURVE_ABI,
    functionName: "graduated",
    query: { enabled: !!curveAddress },
  });

  const { data: curveFeeBps } = useReadContract({
    address: curveAddress,
    abi: PONS_CURVE_ABI,
    functionName: "feeBps",
    query: { enabled: !!curveAddress },
  });

  const { data: creatorTaxBps } = useReadContract({
    address: curveAddress,
    abi: PONS_CURVE_ABI,
    functionName: "creatorTaxBps",
    query: { enabled: !!curveAddress },
  });

  const { data: snipeTaxBps } = useReadContract({
    address: curveAddress,
    abi: PONS_CURVE_ABI,
    functionName: "currentSnipeTaxBps",
    args: address ? [address] : undefined,
    query: { enabled: !!curveAddress && !!address, refetchInterval: 1000 },
  });

  // Phase: 0 NotGraduated, 1 Swept, 2 PoolCreated, 3 Rescued
  const phase = launchRecord?.phase ?? 0;
  const isTradingOnV4 = phase === 2 || graduated;
  const isSweptWaitingPool = phase === 1 || (readyToGraduate && !isTradingOnV4);

  // 4. Token Allowance for Curve (needed when selling tokens)
  const { data: tokenAllowance, refetch: refetchTokenAllowance } = useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: address && curveAddress ? [address, curveAddress] : undefined,
  });

  // Parse input
  const parsedBuyInput = amountInput && Number(amountInput) > 0 && activeTab === "buy"
    ? parseUnits(amountInput, 18)
    : 0n;

  const parsedSellInput = amountInput && Number(amountInput) > 0 && activeTab === "sell"
    ? parseUnits(amountInput, 18)
    : 0n;

  // 5. Accurate Deterministic Quoting from Pons v2 documentation
  const quoteResult = useMemo(() => {
    if (!reserves || !curveFeeBps) return { output: 0n, fee: 0n, tax: 0n, snipeTax: 0n };
    const [quoteReserve, tokenReserve] = reserves;
    const BPS = 10000n;
    const feeRate = curveFeeBps;
    const taxRate = creatorTaxBps || 0n;

    if (activeTab === "buy") {
      if (parsedBuyInput <= 0n) return { output: 0n, fee: 0n, tax: 0n, snipeTax: 0n };
      const rawSnipe = snipeTaxBps || 0n;
      let snipeRate = rawSnipe;
      if (snipeRate > 0n) {
        const maxSnipe = BPS - feeRate - taxRate - 100n;
        if (snipeRate > maxSnipe) snipeRate = maxSnipe;
      }

      const spent = parsedBuyInput;
      const fee = (spent * feeRate) / BPS;
      const tax = (spent * taxRate) / BPS;
      const snipeTax = (spent * snipeRate) / BPS;
      const netSpend = spent > fee + tax + snipeTax ? spent - fee - tax - snipeTax : 0n;
      let tokensOut = (quoteReserve + netSpend > 0n)
        ? (netSpend * tokenReserve) / (quoteReserve + netSpend)
        : 0n;

      if (sellableTokens !== undefined && tokensOut > sellableTokens) {
        tokensOut = sellableTokens;
      }
      return { output: tokensOut, fee, tax, snipeTax };
    } else {
      if (parsedSellInput <= 0n) return { output: 0n, fee: 0n, tax: 0n, snipeTax: 0n };
      const tokensIn = parsedSellInput;
      const gross = (tokenReserve + tokensIn > 0n)
        ? (tokensIn * quoteReserve) / (tokenReserve + tokensIn)
        : 0n;
      const fee = (gross * feeRate) / BPS;
      const tax = (gross * taxRate) / BPS;
      const quoteOut = gross > fee + tax ? gross - fee - tax : 0n;
      return { output: quoteOut, fee, tax, snipeTax: 0n };
    }
  }, [reserves, curveFeeBps, creatorTaxBps, snipeTaxBps, sellableTokens, activeTab, parsedBuyInput, parsedSellInput]);

  // Price and market cap calculation - synchronized with Pons v2 onchain economics
  const currentPriceEth = useMemo(() => {
    if (isTradingOnV4 || graduated) {
      return 0.00000002058; // Final graduation price (~20.58 ETH MC)
    }
    if (reserves && reserves[1] > 0n) {
      const quote = Number(formatUnits(reserves[0], 18));
      const tokens = Number(formatUnits(reserves[1], 18));
      if (tokens > 0) return quote / tokens;
    }
    return 0.00000000168; // Initial curve price (1.68 ETH phantom / 1B supply)
  }, [reserves, isTradingOnV4, graduated]);

  const currentMarketCapEth = useMemo(() => {
    if (isTradingOnV4 || graduated) {
      return 20.58; // Final graduation market cap
    }
    return currentPriceEth * 1_000_000_000;
  }, [currentPriceEth, isTradingOnV4, graduated]);

  const thresholdEth = launchRecord?.graduationThreshold
    ? Number(formatUnits(launchRecord.graduationThreshold, 18))
    : 4.2;

  const progressPercent = useMemo(() => {
    if (!realQuote || !launchRecord?.graduationThreshold || launchRecord.graduationThreshold === 0n) return 0;
    const raised = Number(formatUnits(realQuote, 18));
    return Math.min(100, Math.max(0, (raised / thresholdEth) * 100));
  }, [realQuote, launchRecord, thresholdEth]);

  // Transactions: Approve & Trade
  const { writeContract: writeApprove, data: approveTxHash, isPending: isApproving } = useWriteContract();
  const { isLoading: isWaitingApproveTx, isSuccess: approveSuccess } = useWaitForTransactionReceipt({ hash: approveTxHash });

  const { writeContract: writeTrade, data: tradeTxHash, isPending: isTrading, error: tradeError } = useWriteContract();
  const { isLoading: isWaitingTradeTx, isSuccess: tradeSuccess } = useWaitForTransactionReceipt({ hash: tradeTxHash });

  const { writeContract: writeGraduate, data: graduateTxHash, isPending: isGraduating } = useWriteContract();
  const { isLoading: isWaitingGraduateTx, isSuccess: graduateSuccess } = useWaitForTransactionReceipt({ hash: graduateTxHash });

  const notifiedApproveTxRef = useRef<string | null>(null);
  const notifiedTradeTxRef = useRef<string | null>(null);

  useEffect(() => {
    if (approveSuccess && approveTxHash && notifiedApproveTxRef.current !== approveTxHash) {
      notifiedApproveTxRef.current = approveTxHash;
      refetchTokenAllowance();
      toast.success(
        "Token Approved!",
        `Curve contract approved to spend ${tokenSymbol || "tokens"}. You can now execute your sell trade.`,
        approveTxHash
      );
    }
  }, [approveSuccess, approveTxHash, refetchTokenAllowance, tokenSymbol, toast]);

  useEffect(() => {
    if (tradeSuccess && tradeTxHash && notifiedTradeTxRef.current !== tradeTxHash) {
      notifiedTradeTxRef.current = tradeTxHash;
      refetchTokenBalance();
      refetchEthBalance();
      refetchTokenAllowance();
      refetchReserves();
      refetchRealQuote();
      refetchSellable();
      refetchReadyGraduate();
      refetchGraduated();
      refetchLaunchRecord();
      setTradeCount((c) => c + 1);
      const actionName = activeTab === "buy" ? "Buy" : "Sell";
      toast.success(
        `${actionName} Confirmed!`,
        `${activeTab === "buy" ? "Successfully purchased" : "Successfully sold"} ${tokenSymbol || "tokens"} on Robinhood Chain.`,
        tradeTxHash
      );
      setAmountInput("");
    }
  }, [tradeSuccess, tradeTxHash, activeTab, tokenSymbol, refetchTokenBalance, refetchEthBalance, refetchTokenAllowance, refetchReserves, refetchRealQuote, refetchSellable, refetchReadyGraduate, refetchGraduated, refetchLaunchRecord, toast]);

  useEffect(() => {
    if (graduateSuccess && graduateTxHash) {
      refetchLaunchRecord();
      refetchGraduated();
      toast.success("Pool Created!", "Graduation into Uniswap v4 has been finalized successfully.", graduateTxHash);
    }
  }, [graduateSuccess, graduateTxHash, refetchLaunchRecord, refetchGraduated, toast]);

  const isNeedsTokenApproval =
    activeTab === "sell" &&
    parsedSellInput > 0n &&
    (!tokenAllowance || tokenAllowance < parsedSellInput);

  const handleApproveToken = () => {
    if (!curveAddress || parsedSellInput <= 0n) return;
    writeApprove({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [curveAddress, parsedSellInput],
    });
  };

  const handleTrade = () => {
    if (!curveAddress || !address) return;

    if (activeTab === "buy") {
      if (parsedBuyInput <= 0n) return;
      // Slippage bounds: 1% tolerance
      const minOut = (quoteResult.output * 99n) / 100n;
      writeTrade({
        address: curveAddress,
        abi: PONS_CURVE_ABI,
        functionName: "buy",
        args: [parsedBuyInput, minOut, address],
        value: parsedBuyInput,
      });
    } else {
      if (parsedSellInput <= 0n) return;
      const minQuote = (quoteResult.output * 99n) / 100n;
      writeTrade({
        address: curveAddress,
        abi: PONS_CURVE_ABI,
        functionName: "sell",
        args: [parsedSellInput, minQuote, address],
      });
    }
  };

  const handlePushGraduation = () => {
    writeGraduate({
      address: CONTRACT_ADDRESSES.factory,
      abi: PONS_FACTORY_ABI,
      functionName: "createGraduatedPool",
      args: [tokenAddress],
    });
  };

  const logoUrl = tokenInfo?.[1] || "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";
  const resolvedLogo = logoUrl.startsWith("ipfs://")
    ? `https://gateway.pinata.cloud/ipfs/${logoUrl.replace("ipfs://", "")}`
    : logoUrl;
  const description = tokenInfo?.[2] || "A community launch token on Robinhood Chain powered by Pons v2.";
  const socials = tokenInfo?.[3];

  if (!isLoadingLaunch && launchRecord && !launchRecord.exists) {
    return (
      <div className="max-w-2xl mx-auto py-20 text-center space-y-4 sketch-card p-8">
        <AlertCircle className="w-12 h-12 text-yellow-400 mx-auto" />
        <h2 className="text-3xl font-kalam font-bold text-white">Token Not Found</h2>
        <p className="text-sm font-hand text-slate-400">
          Address <span className="font-mono text-sky-400">{tokenAddress}</span> is not a valid token launched via Pons v2 on Robinhood Chain.
        </p>
      </div>
    );
  }

  return (
    <div className="max-w-6xl mx-auto space-y-8 pb-20">
      {/* Header Info - Flat Card */}
      <div className="sketch-card p-6 sm:p-8 flex flex-col md:flex-row items-start md:items-center justify-between gap-6 relative bg-[#121318] border border-zinc-800 rounded-2xl">
        <div className="flex items-center space-x-5">
          <div className="w-20 h-20 rounded-xl overflow-hidden bg-zinc-900 border border-yellow-500/40 shrink-0 flex items-center justify-center shadow-sm p-1">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={resolvedLogo} alt={tokenName || "Token"} className="w-full h-full object-cover rounded-lg" />
          </div>
          <div className="space-y-1">
            <div className="flex items-center space-x-3 flex-wrap gap-y-1">
              <h1 className="text-3xl sm:text-4xl font-extrabold text-white tracking-tight">{tokenName || "Loading..."}</h1>
              <span className="px-2.5 py-0.5 rounded-md bg-yellow-400/10 text-yellow-400 font-mono text-xs font-bold uppercase border border-yellow-400/30">${tokenSymbol || "..."}</span>
              {isTradingOnV4 ? (
                <span className="px-2.5 py-1 rounded-sketch text-xs font-hand font-bold bg-purple-500/20 text-purple-300 border-2 border-purple-500/40 shadow-sketch-sm flex items-center space-x-1">
                  <ShieldCheck className="w-3.5 h-3.5" />
                  <span>Uniswap v4 Pool Live</span>
                </span>
              ) : isSweptWaitingPool ? (
                <span className="px-2.5 py-1 rounded-sketch text-xs font-hand font-bold bg-amber-500/20 text-amber-300 border-2 border-amber-500/40 shadow-sketch-sm flex items-center space-x-1">
                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                  <span>Graduation Pending</span>
                </span>
              ) : (
                <span className="px-2.5 py-1 rounded-sketch text-xs font-hand font-bold bg-sky-500/20 text-sky-300 border-2 border-sky-400/40 shadow-sketch-sm flex items-center space-x-1">
                  <Flame className="w-3.5 h-3.5 text-sky-400" />
                  <span>Active Bonding Curve</span>
                </span>
              )}
            </div>
            <p className="text-sm font-hand text-slate-300 max-w-xl line-clamp-2 leading-relaxed">{description}</p>
            {socials && (
              <div className="flex items-center space-x-3 pt-1 text-slate-400 text-sm font-hand font-bold">
                {socials.website && (
                  <a href={socials.website} target="_blank" rel="noopener noreferrer" className="hover:text-sky-300 transition flex items-center space-x-1">
                    <Globe className="w-4 h-4" />
                    <span>Web</span>
                  </a>
                )}
                {socials.twitter && (
                  <a href={socials.twitter.startsWith("http") ? socials.twitter : `https://x.com/${socials.twitter}`} target="_blank" rel="noopener noreferrer" className="hover:text-sky-300 transition">
                    𝕏 Twitter
                  </a>
                )}
                {socials.telegram && (
                  <a href={socials.telegram.startsWith("http") ? socials.telegram : `https://t.me/${socials.telegram}`} target="_blank" rel="noopener noreferrer" className="hover:text-sky-300 transition flex items-center space-x-1">
                    <Send className="w-4 h-4" />
                    <span>Telegram</span>
                  </a>
                )}
                {socials.discord && (
                  <a href={socials.discord} target="_blank" rel="noopener noreferrer" className="hover:text-sky-300 transition flex items-center space-x-1">
                    <MessageSquare className="w-4 h-4" />
                    <span>Discord</span>
                  </a>
                )}
                <a
                  href={`https://robinhoodchain.blockscout.com/address/${tokenAddress}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-sky-300 transition flex items-center space-x-1"
                >
                  <ExternalLink className="w-3.5 h-3.5" />
                  <span>Explorer</span>
                </a>
              </div>
            )}
          </div>
        </div>

        {/* Quick Stats in Hand-Drawn Ticket Format */}
        <div className="flex flex-wrap items-center gap-3 shrink-0">
          <div className="p-3 sketch-surface rounded-sketch text-right">
            <span className="text-[11px] font-hand text-slate-400 uppercase tracking-wider block">Price</span>
            <span className="font-mono text-sm sm:text-base font-bold text-white block">
              {currentPriceEth ? formatUsd(currentPriceEth * ethPriceUsd) : "$0.00"}
            </span>
            <span className="text-[10px] font-mono text-slate-400 block">
              {currentPriceEth ? `${currentPriceEth < 0.0001 ? currentPriceEth.toFixed(9) : currentPriceEth.toFixed(6)} ETH` : "0.00 ETH"}
            </span>
          </div>
          <div className="p-3 sketch-surface rounded-sketch text-right">
            <span className="text-[11px] font-hand text-slate-400 uppercase tracking-wider block">Market Cap</span>
            <span className="font-mono text-sm sm:text-base font-bold text-emerald-400 block">
              {currentMarketCapEth ? formatUsd(currentMarketCapEth * ethPriceUsd) : "$0.00"}
            </span>
            <span className="text-[10px] font-mono text-emerald-300/80 block">
              {currentMarketCapEth ? `${currentMarketCapEth.toFixed(3)} ETH` : "0.00 ETH"}
            </span>
          </div>
          <div className="p-3 sketch-surface rounded-sketch text-right">
            <span className="text-[11px] font-hand text-slate-400 uppercase tracking-wider block">Total Volume</span>
            <span className="font-mono text-sm sm:text-base font-bold text-emerald-300 block">
              {liveVolumeEth > 0 ? formatUsd(liveVolumeEth * ethPriceUsd) : "$0.00"}
            </span>
            <span className="text-[10px] font-mono text-slate-400 block">
              {liveVolumeEth > 0 ? `${liveVolumeEth.toFixed(3)} ETH` : "0.000 ETH"}
            </span>
          </div>
        </div>
      </div>

      {/* Graduation Progress Bar - Hatched Meter */}
      <div className="sketch-card p-6 space-y-3 bg-[#121318] border border-zinc-800 rounded-2xl">
        <div className="flex justify-between items-center text-sm font-semibold">
          <span className="text-zinc-200 uppercase tracking-wider flex items-center space-x-2">
            <TrendingUp className="w-5 h-5 text-yellow-400" />
            <span>Curve Graduation Target ({progressPercent.toFixed(1)}%)</span>
          </span>
          <span className="font-mono text-yellow-400 font-bold">
            {realQuote ? `${Number(formatUnits(realQuote, 18)).toFixed(3)} ETH` : "0.000 ETH"} / {thresholdEth} ETH Target ({formatUsd(thresholdEth * ethPriceUsd)})
          </span>
        </div>
        <div className="w-full h-3 bg-zinc-950 rounded-full border border-zinc-800 overflow-hidden p-0.5">
          <div
            className="h-full bg-yellow-400 rounded-full transition-all duration-500 shadow-sm"
            style={{ width: `${progressPercent}%` }}
          />
        </div>
        <div className="flex justify-between text-xs text-zinc-400 font-sans">
          <span>When the curve accumulates {thresholdEth} ETH ({formatUsd(thresholdEth * ethPriceUsd)}), 100% of liquidity will automatically migrate &amp; lock into Uniswap v4.</span>
          {isSweptWaitingPool && (
            <button
              type="button"
              onClick={handlePushGraduation}
              disabled={isGraduating || isWaitingGraduateTx}
              className="text-yellow-400 hover:text-yellow-300 underline font-bold"
            >
              {isGraduating || isWaitingGraduateTx ? "Migrating liquidity pool..." : "Click to push Uniswap v4 pool"}
            </button>
          )}
        </div>
      </div>

      {/* Trading & Chart Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Real Chart */}
        <div className="lg:col-span-2">
          <RealTradingChart
            tokenAddress={tokenAddress}
            curveAddress={curveAddress}
            tokenSymbol={tokenSymbol}
            currentPriceEth={currentPriceEth}
            currentMarketCapEth={currentMarketCapEth}
            ethPriceUsd={ethPriceUsd}
            isGraduated={isTradingOnV4}
            refreshTrigger={tradeCount}
            onStatsChange={(stats) => {
              setLiveVolumeEth(stats.volumeEth);
            }}
          />
        </div>

        {/* Swap Card in Flat Style */}
        <div className="sketch-card p-6 sm:p-7 space-y-6 self-start shadow-sm bg-[#121318] border border-zinc-800 rounded-2xl">
          <div className="flex items-center justify-between pb-2 border-b border-zinc-800">
            <div className="grid grid-cols-2 gap-2 p-1 bg-zinc-950 rounded-lg w-full border border-zinc-800">
              <button
                type="button"
                onClick={() => setActiveTab("buy")}
                className={`py-2 text-sm font-semibold rounded-md transition ${
                  activeTab === "buy" ? "bg-yellow-400 text-black font-bold shadow-sm" : "text-zinc-400 hover:text-white"
                }`}
              >
                Buy {tokenSymbol || "Token"}
              </button>
              <button
                type="button"
                onClick={() => setActiveTab("sell")}
                className={`py-2 text-sm font-semibold rounded-md transition ${
                  activeTab === "sell" ? "bg-yellow-400 text-black font-bold shadow-sm" : "text-zinc-400 hover:text-white"
                }`}
              >
                Sell {tokenSymbol || "Token"}
              </button>
            </div>
          </div>

          {/* Balance info */}
          <div className="flex items-center justify-between text-xs font-hand text-slate-400">
            <span>Your Balance:</span>
            <span className="font-mono text-slate-200 font-bold">
              {activeTab === "buy"
                ? `${userEthBalance ? Number(formatUnits(userEthBalance.value, 18)).toFixed(4) : "0.00"} ETH`
                : `${userTokenBalance ? Number(formatUnits(userTokenBalance, 18)).toLocaleString() : "0"} ${tokenSymbol || ""}`}
            </span>
          </div>

          {/* Amount Input */}
          <div className="space-y-2">
            <div className="relative">
              <input
                type="number"
                step="any"
                min="0"
                placeholder="0.0"
                value={amountInput}
                onChange={(e) => setAmountInput(e.target.value)}
                className="w-full px-4 py-3 sketch-inset text-base font-mono text-white placeholder:text-slate-500 focus:outline-none"
              />
              <span className="absolute right-3.5 top-3 text-xs font-mono font-bold text-emerald-300">
                {activeTab === "buy" ? "ETH" : tokenSymbol || "TOKEN"}
              </span>
            </div>
            {activeTab === "buy" ? (
              <div className="flex items-center space-x-1.5 pt-1">
                {[0.01, 0.05, 0.1, 0.25].map((val) => (
                  <button
                    key={val}
                    type="button"
                    onClick={() => setAmountInput(val.toString())}
                    className="flex-1 py-1 text-xs font-hand font-bold sketch-btn-secondary text-slate-300 hover:text-white"
                  >
                    +{val} ETH
                  </button>
                ))}
              </div>
            ) : (
              <div className="flex items-center space-x-1.5 pt-1">
                {[25, 50, 75, 100].map((pct) => (
                  <button
                    key={pct}
                    type="button"
                    onClick={() => {
                      if (userTokenBalance && userTokenBalance > 0n) {
                        const amt = (userTokenBalance * BigInt(pct)) / 100n;
                        setAmountInput(formatUnits(amt, 18));
                      }
                    }}
                    className="flex-1 py-1 text-xs font-hand font-bold sketch-btn-secondary text-slate-300 hover:text-white"
                  >
                    {pct}%
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Quote breakdown in Hand-Drawn Receipt Note */}
          <div className="p-4 sketch-surface space-y-2 text-xs font-hand rounded-sketch">
            <div className="flex justify-between items-center text-slate-300">
              <span>Estimated Output:</span>
              <span className="font-mono font-bold text-emerald-400 text-sm">
                {activeTab === "buy"
                  ? `${Number(formatUnits(quoteResult.output, 18)).toLocaleString()} ${tokenSymbol || "TOKEN"}`
                  : `${Number(formatUnits(quoteResult.output, 18)).toFixed(5)} ETH`}
              </span>
            </div>
            <div className="flex justify-between items-center text-slate-400">
              <span>Curve Fee (1%):</span>
              <span className="font-mono text-slate-300">
                {Number(formatUnits(quoteResult.fee, 18)).toFixed(6)} ETH
              </span>
            </div>
            {creatorTaxBps !== undefined && creatorTaxBps > 0n && (
              <div className="flex justify-between items-center text-slate-400">
                <span>Creator Royalty ({(Number(creatorTaxBps) / 100).toFixed(1)}%):</span>
                <span className="font-mono text-emerald-300">
                  {Number(formatUnits(quoteResult.tax, 18)).toFixed(6)} ETH
                </span>
              </div>
            )}
            {quoteResult.snipeTax > 0n && (
              <div className="flex justify-between items-center text-rose-400 font-semibold">
                <span>Anti-Snipe Tax:</span>
                <span className="font-mono">
                  {Number(formatUnits(quoteResult.snipeTax, 18)).toFixed(6)} ETH
                </span>
              </div>
            )}
          </div>

          {/* Action Button */}
          {isNeedsTokenApproval ? (
            <button
              type="button"
              onClick={handleApproveToken}
              disabled={isApproving || isWaitingApproveTx}
              className="w-full py-3.5 sketch-btn-primary text-slate-950 font-bold text-lg flex items-center justify-center space-x-2 disabled:opacity-50"
            >
              {isApproving || isWaitingApproveTx ? (
                <>
                  <Loader2 className="w-5 h-5 animate-spin" />
                  <span>Approving {tokenSymbol}...</span>
                </>
              ) : (
                <span>Approve {tokenSymbol} to Sell</span>
              )}
            </button>
          ) : (
            <button
              type="button"
              onClick={handleTrade}
              disabled={
                isTrading ||
                isWaitingTradeTx ||
                !isConnected ||
                !curveAddress ||
                isTradingOnV4 ||
                (activeTab === "buy" ? parsedBuyInput <= 0n : parsedSellInput <= 0n)
              }
              className={`w-full py-3.5 font-bold text-lg flex items-center justify-center space-x-2 disabled:opacity-50 ${
                activeTab === "buy" ? "sketch-btn-primary text-slate-950 font-bold" : "sketch-btn-secondary bg-rose-600/30 border-rose-500 text-rose-200"
              }`}
            >
              {isTrading || isWaitingTradeTx ? (
                <>
                  <Loader2 className="w-5 h-5 animate-spin" />
                  <span>Processing {activeTab === "buy" ? "Purchase" : "Sale"}...</span>
                </>
              ) : !isConnected ? (
                <span>Connect Wallet</span>
              ) : isTradingOnV4 ? (
                <span>Graduated to Uniswap v4</span>
              ) : (
                <>
                  <ArrowDownUp className="w-5 h-5" />
                  <span>{activeTab === "buy" ? "Buy with ETH" : `Sell ${tokenSymbol || "Token"}`}</span>
                </>
              )}
            </button>
          )}

          {tradeError && (
            <p className="text-xs font-hand text-rose-400 flex items-start space-x-1.5 leading-relaxed">
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{tradeError.message?.split("\n")[0] || "Transaction failed."}</span>
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
