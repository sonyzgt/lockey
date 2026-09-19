"use client";

import Link from "next/link";
import { useState, useEffect, useCallback, useMemo } from "react";
import { usePublicClient, useReadContract } from "wagmi";
import { formatUnits, isAddress } from "viem";
import {
  Search,
  PlusCircle,
  ArrowRight,
  Flame,
  GraduationCap,
  Sparkles,
  Clock,
  ShieldCheck,
  RefreshCw,
  Loader2,
  BookmarkPlus,
  X,
  CheckCircle2,
  AlertCircle,
  Radar,
} from "lucide-react";
import { CONTRACT_ADDRESSES } from "@/config/chain";
import { PONS_CURVE_ABI, PONS_FACTORY_ABI, PONS_TOKEN_ABI } from "@/config/abis";
import { useEthPrice, formatUsd } from "@/hooks/useEthPrice";

type FilterTab = "all" | "bonding" | "graduated" | "newest";

export interface LaunchedTokenItem {
  token: `0x${string}`;
  curve: `0x${string}`;
  deployer: `0x${string}`;
  blockNumber?: bigint;
  name?: string;
  symbol?: string;
  logo?: string;
  description?: string;
  createdAt?: string;
}

interface RawTokenItem {
  token?: string;
  curve?: string;
  deployer?: string;
  blockNumber?: string | number | bigint;
  name?: string;
  symbol?: string;
  logo?: string;
  description?: string;
  createdAt?: string;
}

export default function HomePage() {
  const publicClient = usePublicClient();
  const [searchTerm, setSearchTerm] = useState("");
  const [activeTab, setActiveTab] = useState<FilterTab>("all");
  const [launchedTokens, setLaunchedTokens] = useState<LaunchedTokenItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Import / Track Token Modal State
  const [isImportModalOpen, setIsImportModalOpen] = useState(false);
  const [importAddress, setImportAddress] = useState("");
  const [isImporting, setIsImporting] = useState(false);
  const [importStatus, setImportStatus] = useState<{
    type: "success" | "error";
    message: string;
  } | null>(null);

  // Fetch only tokens launched on this platform (backend registry + local storage)
  const fetchLaunches = useCallback(async () => {
    try {
      setIsLoading(true);

      // 1. Fetch tokens registered on this platform's backend
      let serverTokens: RawTokenItem[] = [];
      let fetchSuccess = false;
      try {
        const res = await fetch("/api/tokens", { cache: "no-store" });
        const data = await res.json();
        if (data && data.success && Array.isArray(data.tokens)) {
          serverTokens = data.tokens;
          fetchSuccess = true;
          // Synchronize local storage with authoritative server state
          try {
            localStorage.setItem("vana_platform_tokens", JSON.stringify(data.tokens));
          } catch {
            // ignore localStorage quota/disabled errors
          }
        }
      } catch (err) {
        console.warn("Could not fetch from /api/tokens:", err);
      }

      // 2. Fetch local storage cached platform tokens ONLY if server fetch failed
      let localTokens: RawTokenItem[] = [];
      if (!fetchSuccess) {
        try {
          const local = localStorage.getItem("vana_platform_tokens");
          if (local) {
            localTokens = JSON.parse(local);
          }
        } catch (err) {
          console.warn("Could not parse local tokens:", err);
        }
      }

      // 3. Merge & deduplicate
      const uniqueTokensMap = new Map<string, LaunchedTokenItem>();

      for (const item of [...serverTokens, ...localTokens]) {
        if (item.token && typeof item.token === "string" && item.token.startsWith("0x")) {
          const tAddr = item.token.toLowerCase() as `0x${string}`;
          if (!uniqueTokensMap.has(tAddr)) {
            uniqueTokensMap.set(tAddr, {
              token: tAddr,
              curve: (item.curve || "0x0000000000000000000000000000000000000000") as `0x${string}`,
              deployer: (item.deployer || "0x0000000000000000000000000000000000000000") as `0x${string}`,
              blockNumber: item.blockNumber ? BigInt(item.blockNumber) : 0n,
              name: item.name,
              symbol: item.symbol,
              logo: item.logo,
              description: item.description,
              createdAt: item.createdAt,
            });
          }
        }
      }

      // 4. Resolve curve address for any token where curve is missing / empty
      if (publicClient && uniqueTokensMap.size > 0) {
        for (const [tAddr, item] of Array.from(uniqueTokensMap.entries())) {
          if (!item.curve || item.curve === "0x0000000000000000000000000000000000000000") {
            try {
              const launchedData = (await publicClient.readContract({
                address: CONTRACT_ADDRESSES.factory,
                abi: PONS_FACTORY_ABI,
                functionName: "getLaunchedToken",
                args: [item.token],
              })) as { curve?: `0x${string}` } | undefined;

              if (
                launchedData &&
                launchedData.curve &&
                launchedData.curve !== "0x0000000000000000000000000000000000000000"
              ) {
                item.curve = launchedData.curve;
                uniqueTokensMap.set(tAddr, { ...item });
              }
            } catch (e) {
              console.warn(`Could not resolve curve for ${tAddr}:`, e);
            }
          }
        }
      }

      setLaunchedTokens(Array.from(uniqueTokensMap.values()));
    } catch (err) {
      console.warn("Failed to fetch platform tokens:", err);
    } finally {
      setIsLoading(false);
    }
  }, [publicClient]);

  useEffect(() => {
    fetchLaunches();
  }, [fetchLaunches]);

  // Handle importing / adding existing token to this platform
  const handleImportToken = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!importAddress.trim()) return;

    if (!isAddress(importAddress.trim())) {
      setImportStatus({
        type: "error",
        message: "Invalid token address (must be a 42-character 0x... address).",
      });
      return;
    }

    if (!publicClient) {
      setImportStatus({
        type: "error",
        message: "RPC Client is not ready. Please reload the page.",
      });
      return;
    }

    try {
      setIsImporting(true);
      setImportStatus(null);
      const targetAddr = importAddress.trim() as `0x${string}`;

      // Verify token exists on Pons factory
      const launchedData = (await publicClient.readContract({
        address: CONTRACT_ADDRESSES.factory,
        abi: PONS_FACTORY_ABI,
        functionName: "getLaunchedToken",
        args: [targetAddr],
      })) as { exists?: boolean; curve?: `0x${string}`; deployer?: `0x${string}` } | undefined;

      if (!launchedData || !launchedData.exists) {
        setImportStatus({
          type: "error",
          message: "This token was not found on Pons Factory on Robinhood Chain.",
        });
        return;
      }

      const curveAddr = (launchedData.curve || "0x0000000000000000000000000000000000000000") as `0x${string}`;
      const deployerAddr = (launchedData.deployer || "0x0000000000000000000000000000000000000000") as `0x${string}`;

      // Read token details
      let name = "";
      let symbol = "";
      try {
        name = (await publicClient.readContract({
          address: targetAddr,
          abi: PONS_TOKEN_ABI,
          functionName: "name",
        })) as string;
        symbol = (await publicClient.readContract({
          address: targetAddr,
          abi: PONS_TOKEN_ABI,
          functionName: "symbol",
        })) as string;
      } catch (err) {
        console.warn("Could not read token name/symbol:", err);
      }

      // Save to backend
      await fetch("/api/tokens", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          token: targetAddr,
          curve: curveAddr,
          deployer: deployerAddr,
          name,
          symbol,
          createdAt: new Date().toISOString(),
        }),
      });

      // Save to localStorage
      try {
        const local = JSON.parse(localStorage.getItem("vana_platform_tokens") || "[]");
        if (!local.some((t: { token?: string }) => t.token?.toLowerCase() === targetAddr.toLowerCase())) {
          local.unshift({
            token: targetAddr,
            curve: curveAddr,
            deployer: deployerAddr,
            name,
            symbol,
            createdAt: new Date().toISOString(),
          });
          localStorage.setItem("vana_platform_tokens", JSON.stringify(local));
        }
      } catch (err) {
        console.warn("Could not save to local storage:", err);
      }

      setImportStatus({
        type: "success",
        message: `Token ${name || symbol || targetAddr.slice(0, 6)} successfully added to explorer!`,
      });

      setImportAddress("");
      await fetchLaunches();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Failed to verify token on Robinhood Chain.";
      setImportStatus({
        type: "error",
        message: msg,
      });
    } finally {
      setIsImporting(false);
    }
  };

  const filteredTokens = useMemo(() => {
    const list = [...launchedTokens];
    if (activeTab === "newest") {
      list.reverse();
    }
    return list;
  }, [launchedTokens, activeTab]);

  return (
    <div className="space-y-10 pb-16">
      {/* Explorer Section */}
      <section id="explore" className="space-y-6">
        {/* Top Header Card in Emerald Hand-Drawn Memo Style */}
        <div className="sketch-card p-6 sm:p-8 flex flex-col md:flex-row md:items-center justify-between gap-6 relative bg-[#092214]">
          {/* Mint Green Tape Accent */}
          <div className="hidden sm:block absolute -top-3 left-12 w-28 h-6 bg-emerald-400/35 border border-dashed border-emerald-400 -rotate-2 pointer-events-none"></div>

          <div className="flex items-start sm:items-center space-x-4">
            <div className="w-14 h-14 rounded-sketch border-2 border-emerald-400 bg-[#0c2e1b] shadow-sketch p-1 shrink-0">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/vana-logo.png" alt="VANA" className="w-full h-full object-cover rounded-sketch" />
            </div>
            <div>
              <div className="flex items-center space-x-3">
                <h1 className="text-3xl sm:text-4xl font-kalam font-bold text-white tracking-wide flex items-center space-x-2">
                  <span>Vana Token Explorer</span>
                  <span className="text-xl">🌿</span>
                </h1>
                <span className="text-sm px-3 py-0.5 sketch-badge bg-[#0c2e1b] text-emerald-300 font-hand font-bold border border-emerald-500/40">
                  {launchedTokens.length} Tokens
                </span>
              </div>
              <p className="text-sm font-hand text-emerald-200/90 mt-1">
                Official meme tokens launched via Vana Launchpad • Pons v2 on Robinhood Chain
              </p>
            </div>
          </div>

          {/* Search, Track, and Create controls */}
          <div className="flex items-center flex-wrap sm:flex-nowrap gap-3">
            <div className="relative w-full sm:w-64">
              <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-emerald-400" />
              <input
                type="text"
                placeholder="Search token, ticker, address..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full pl-10 pr-4 py-2.5 sketch-inset text-sm font-hand text-slate-100 placeholder:text-emerald-400/50 focus:outline-none"
              />
            </div>

            <button
              onClick={() => setIsImportModalOpen(true)}
              title="Track Existing Token"
              className="px-4 py-2 sketch-btn-secondary text-sm font-hand font-bold flex items-center space-x-1.5 shrink-0"
            >
              <BookmarkPlus className="w-4 h-4 text-emerald-400" />
              <span>Track Token</span>
            </button>

            <button
              onClick={fetchLaunches}
              disabled={isLoading}
              title="Refresh list"
              className="p-2.5 sketch-btn-secondary text-emerald-200 hover:text-white rounded-xl"
            >
              <RefreshCw className={`w-4 h-4 ${isLoading ? "animate-spin text-emerald-400" : ""}`} />
            </button>

            <Link
              href="/radar"
              className="inline-flex items-center space-x-2 px-4 py-2.5 sketch-btn-secondary text-emerald-300 hover:text-white font-bold text-sm shrink-0 border border-emerald-500/60"
            >
              <Radar className="w-4 h-4 text-emerald-400 animate-pulse" />
              <span>X Radar (j7tracker)</span>
            </Link>

            <Link
              href="/create"
              className="inline-flex items-center space-x-2 px-5 py-2.5 sketch-btn-primary text-slate-950 font-bold text-base shrink-0"
            >
              <PlusCircle className="w-4 h-4" />
              <span>Launch Token</span>
            </Link>
          </div>
        </div>

        {/* Filter Tabs Bar (Hand-Drawn Emerald Sketch Tabs) */}
        <div className="flex items-center space-x-3 overflow-x-auto pb-2 scrollbar-none font-hand text-base font-bold">
          <button
            onClick={() => setActiveTab("all")}
            className={`px-4 py-1.5 transition flex items-center space-x-2 shrink-0 ${
              activeTab === "all"
                ? "sketch-btn-primary text-slate-950 font-bold"
                : "sketch-btn-secondary text-emerald-200"
            }`}
          >
            <Sparkles className="w-4 h-4 text-emerald-300" />
            <span>All Tokens ({launchedTokens.length})</span>
          </button>

          <button
            onClick={() => setActiveTab("bonding")}
            className={`px-4 py-1.5 transition flex items-center space-x-2 shrink-0 ${
              activeTab === "bonding"
                ? "sketch-btn-primary text-slate-950 font-bold"
                : "sketch-btn-secondary text-emerald-200"
            }`}
          >
            <Flame className="w-4 h-4 text-amber-400" />
            <span>Active Bonding Curves</span>
          </button>

          <button
            onClick={() => setActiveTab("graduated")}
            className={`px-4 py-1.5 transition flex items-center space-x-2 shrink-0 ${
              activeTab === "graduated"
                ? "sketch-btn-primary text-slate-950 font-bold"
                : "sketch-btn-secondary text-emerald-200"
            }`}
          >
            <GraduationCap className="w-4 h-4 text-purple-400" />
            <span>Graduated Uniswap v4</span>
          </button>

          <button
            onClick={() => setActiveTab("newest")}
            className={`px-4 py-1.5 transition flex items-center space-x-2 shrink-0 ${
              activeTab === "newest"
                ? "sketch-btn-primary text-slate-950 font-bold"
                : "sketch-btn-secondary text-emerald-200"
            }`}
          >
            <Clock className="w-4 h-4 text-emerald-400" />
            <span>Newest</span>
          </button>
        </div>

        {/* Tokens Grid */}
        {isLoading ? (
          <div className="py-20 text-center space-y-3">
            <Loader2 className="w-8 h-8 text-emerald-400 animate-spin mx-auto" />
            <p className="text-base font-hand text-emerald-300">Loading tokens from Robinhood Chain...</p>
          </div>
        ) : filteredTokens.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {filteredTokens.map((item) => (
              <TokenCard
                key={item.token}
                item={item}
                searchTerm={searchTerm}
                activeFilter={activeTab}
              />
            ))}
          </div>
        ) : (
          <div className="sketch-card p-12 text-center space-y-5 relative bg-[#092214]">
            <div className="w-20 h-20 mx-auto rounded-sketch border-2 border-dashed border-emerald-400/80 bg-[#0c2e1b] shadow-sketch p-2 flex items-center justify-center">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/vana-logo.png" alt="VANA" className="w-full h-full object-cover rounded-sketch" />
            </div>
            <div>
              <div className="text-white font-kalam font-bold text-2xl">No Tokens in Vana Explorer Yet</div>
              <p className="text-sm font-hand text-emerald-200/80 max-w-md mx-auto leading-relaxed mt-2">
                This explorer exclusively showcases tokens launched via this platform. Be the first creator to deploy your meme token on Pons v2!
              </p>
            </div>
            <div className="pt-2 flex flex-col sm:flex-row items-center justify-center gap-4">
              <Link
                href="/create"
                className="inline-flex items-center space-x-2 px-6 py-3 sketch-btn-primary text-slate-950 font-bold text-lg"
              >
                <span>Launch First Token</span>
                <ArrowRight className="w-5 h-5" />
              </Link>
              <button
                onClick={() => setIsImportModalOpen(true)}
                className="inline-flex items-center space-x-2 px-5 py-3 sketch-btn-secondary text-emerald-200 font-bold text-base"
              >
                <BookmarkPlus className="w-4 h-4 text-emerald-400" />
                <span>Track Existing Token</span>
              </button>
            </div>
          </div>
        )}
      </section>

      {/* Modal: Track / Import Existing Token in Hand-Drawn Blueprint Style */}
      {isImportModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm">
          <div className="sketch-card p-7 max-w-md w-full space-y-5 relative bg-[#092214]">
            {/* Top Mint Tape */}
            <div className="absolute -top-3 left-1/2 -translate-x-1/2 w-28 h-5 bg-emerald-400/40 border border-dashed border-emerald-400 rotate-1"></div>

            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-2">
                <BookmarkPlus className="w-5 h-5 text-emerald-400" />
                <h3 className="text-xl font-kalam font-bold text-white">Track Existing Token</h3>
              </div>
              <button
                onClick={() => {
                  setIsImportModalOpen(false);
                  setImportStatus(null);
                  setImportAddress("");
                }}
                className="p-1.5 sketch-btn-secondary text-slate-400 hover:text-white"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <p className="text-sm font-hand text-emerald-200 leading-relaxed">
              Launched a token on Robinhood Chain via Pons Factory and want to track it on this explorer? Enter the token contract address below.
            </p>

            <form onSubmit={handleImportToken} className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-sm font-hand font-bold text-emerald-200">
                  Token Contract Address (0x...)
                </label>
                <input
                  type="text"
                  placeholder="0x..."
                  value={importAddress}
                  onChange={(e) => setImportAddress(e.target.value)}
                  className="w-full px-3.5 py-2.5 sketch-inset text-xs font-mono text-white placeholder:text-emerald-500/50 focus:outline-none"
                />
              </div>

              {importStatus && (
                <div
                  className={`p-3 rounded-sketch text-xs font-hand font-bold flex items-start space-x-2 border-2 ${
                    importStatus.type === "success"
                      ? "bg-emerald-500/15 border-emerald-500/40 text-emerald-300"
                      : "bg-rose-500/15 border-rose-500/40 text-rose-300"
                  }`}
                >
                  {importStatus.type === "success" ? (
                    <CheckCircle2 className="w-4 h-4 shrink-0 mt-0.5" />
                  ) : (
                    <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                  )}
                  <span>{importStatus.message}</span>
                </div>
              )}

              <div className="flex items-center justify-end space-x-3 pt-2">
                <button
                  type="button"
                  onClick={() => setIsImportModalOpen(false)}
                  className="px-4 py-2 sketch-btn-secondary text-sm font-hand font-bold"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={isImporting || !importAddress.trim()}
                  className="px-5 py-2 sketch-btn-primary text-sm font-hand font-bold text-slate-950 flex items-center space-x-2 disabled:opacity-50"
                >
                  {isImporting ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin" />
                      <span>Verifying...</span>
                    </>
                  ) : (
                    <span>Add to Explorer</span>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

function TokenCard({
  item,
  searchTerm,
  activeFilter,
}: {
  item: LaunchedTokenItem;
  searchTerm: string;
  activeFilter: FilterTab;
}) {
  const { token, curve } = item;
  const ethPriceUsd = useEthPrice();

  const { data: tokenName } = useReadContract({
    address: token,
    abi: PONS_TOKEN_ABI,
    functionName: "name",
  });

  const { data: tokenSymbol } = useReadContract({
    address: token,
    abi: PONS_TOKEN_ABI,
    functionName: "symbol",
  });

  const { data: tokenInfo } = useReadContract({
    address: token,
    abi: PONS_TOKEN_ABI,
    functionName: "getTokenInfo",
  });

  const { data: reserves } = useReadContract({
    address: curve,
    abi: PONS_CURVE_ABI,
    functionName: "getReserves",
  });

  const { data: realQuote } = useReadContract({
    address: curve,
    abi: PONS_CURVE_ABI,
    functionName: "realQuoteReserve",
  });

  const { data: graduated } = useReadContract({
    address: curve,
    abi: PONS_CURVE_ABI,
    functionName: "graduated",
  });

  const { data: readyToGraduate } = useReadContract({
    address: curve,
    abi: PONS_CURVE_ABI,
    functionName: "readyToGraduate",
  });

  const isGraduated = !!graduated;

  // Filter conditions
  if (activeFilter === "bonding" && isGraduated) return null;
  if (activeFilter === "graduated" && !isGraduated) return null;

  const displayName = (tokenName as string) || item.name || "Token";
  const displaySymbol = (tokenSymbol as string) || item.symbol || "...";

  if (searchTerm.trim()) {
    const term = searchTerm.toLowerCase();
    const matchName = displayName.toLowerCase().includes(term);
    const matchSymbol = displaySymbol.toLowerCase().includes(term);
    const matchAddress = token.toLowerCase().includes(term);
    if (!matchName && !matchSymbol && !matchAddress) return null;
  }

  const logoUrl =
    tokenInfo?.[1] ||
    item.logo ||
    "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";
  const resolvedLogo = logoUrl.startsWith("ipfs://")
    ? `https://gateway.pinata.cloud/ipfs/${logoUrl.replace("ipfs://", "")}`
    : logoUrl;

  const description = tokenInfo?.[2] || item.description || "";

  const priceEth =
    isGraduated
      ? 0.00000002058
      : reserves && reserves[1] > 0n
        ? Number(formatUnits(reserves[0], 18)) / Number(formatUnits(reserves[1], 18))
        : 0.00000000168;

  const marketCapEth = isGraduated ? 20.58 : priceEth * 1_000_000_000;

  const raisedEth = realQuote ? Number(formatUnits(realQuote, 18)) : 0;
  const progressPercent = isGraduated ? 100 : Math.min(100, Math.max(0, (raisedEth / 4.2) * 100));

  return (
    <Link
      href={`/token/${token}`}
      className="sketch-card p-5 block transition group relative space-y-4 hover:-rotate-1 bg-[#092214]"
    >
      {/* Top Mint Green Tape Stamp */}
      <div className="absolute -top-2.5 left-8 w-16 h-4 bg-emerald-400/40 border border-dashed border-emerald-400 rotate-2 pointer-events-none"></div>

      <div className="flex items-start justify-between gap-3 pt-1">
        <div className="flex items-center space-x-3 min-w-0">
          <div className="w-13 h-13 rounded-sketch overflow-hidden bg-[#041208] border-2 border-emerald-500/80 shrink-0 flex items-center justify-center p-0.5 shadow-sketch-sm group-hover:border-emerald-400">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={resolvedLogo}
              alt={displayName}
              className="w-12 h-12 object-cover rounded-sketch"
              onError={(e) => {
                (e.target as HTMLElement).style.display = "none";
              }}
            />
          </div>
          <div className="min-w-0">
            <h3 className="text-lg font-kalam font-bold text-white truncate group-hover:text-emerald-300 transition">
              {displayName}
            </h3>
            <span className="text-xs px-2 py-0.5 sketch-badge bg-emerald-500/20 text-emerald-300 font-mono font-bold uppercase border border-emerald-500/40">
              ${displaySymbol}
            </span>
          </div>
        </div>

        {isGraduated ? (
          <span className="px-2.5 py-1 rounded-sketch text-xs font-hand font-bold bg-purple-500/20 text-purple-300 border-2 border-purple-500/40 shadow-sketch-sm flex items-center space-x-1 shrink-0">
            <ShieldCheck className="w-3.5 h-3.5" />
            <span>Uniswap v4</span>
          </span>
        ) : readyToGraduate ? (
          <span className="px-2.5 py-1 rounded-sketch text-xs font-hand font-bold bg-amber-500/20 text-amber-300 border-2 border-amber-500/40 shadow-sketch-sm flex items-center space-x-1 shrink-0">
            <RefreshCw className="w-3.5 h-3.5 animate-spin" />
            <span>Swept</span>
          </span>
        ) : (
          <span className="px-2.5 py-1 rounded-sketch text-xs font-hand font-bold bg-emerald-500/20 text-emerald-300 border-2 border-emerald-500/40 shadow-sketch-sm flex items-center space-x-1 shrink-0">
            <Flame className="w-3.5 h-3.5 text-emerald-400" />
            <span>Active Curve</span>
          </span>
        )}
      </div>

      {description && (
        <p className="text-sm font-hand text-emerald-100/80 line-clamp-2 leading-relaxed">
          {description}
        </p>
      )}

      {/* Stats - Hand-drawn Ledger Note Box in Emerald */}
      <div className="grid grid-cols-2 gap-2 pt-1 border-t-2 border-dashed border-emerald-800/80 text-xs">
        <div className="p-2 sketch-surface bg-[#0c2d1b]">
          <span className="text-[11px] font-hand text-emerald-300/80 uppercase tracking-wider block">Token Price</span>
          <span className="font-mono font-bold text-white text-xs truncate block">
            {priceEth ? formatUsd(priceEth * ethPriceUsd) : "$0.00"}
          </span>
          <span className="text-[10px] font-mono text-slate-400 truncate block">
            {priceEth ? `${priceEth < 0.0001 ? priceEth.toFixed(9) : priceEth.toFixed(6)} ETH` : "0.00 ETH"}
          </span>
        </div>
        <div className="p-2 sketch-surface bg-[#0c2d1b] text-right">
          <span className="text-[11px] font-hand text-emerald-300/80 uppercase tracking-wider block">Market Cap</span>
          <span className="font-mono font-bold text-emerald-300 text-xs truncate block">
            {marketCapEth ? formatUsd(marketCapEth * ethPriceUsd) : "$0.00"}
          </span>
          <span className="text-[10px] font-mono text-emerald-400/70 truncate block">
            {marketCapEth ? `${marketCapEth.toFixed(3)} ETH` : "0.00 ETH"}
          </span>
        </div>
      </div>

      {/* Progress Bar - Hatched Hand-Drawn Emerald Progress Meter */}
      <div className="space-y-1.5 pt-1">
        <div className="flex justify-between items-center text-xs font-hand font-bold">
          <span className="text-emerald-200">Graduation Target (4.2 ETH)</span>
          <span className="text-emerald-300 font-mono">{progressPercent.toFixed(1)}%</span>
        </div>
        <div className="w-full h-3 bg-[#041208] rounded-sketch border-2 border-emerald-700/80 overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-emerald-500 via-green-400 to-lime-300 rounded-sketch sketch-progress-bar transition-all duration-300"
            style={{ width: `${progressPercent}%` }}
          />
        </div>
      </div>
    </Link>
  );
}
