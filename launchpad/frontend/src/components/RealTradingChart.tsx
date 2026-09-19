"use client";

import React, { useState, useEffect, useMemo, useCallback } from "react";
import { usePublicClient } from "wagmi";
import { formatUnits, parseAbiItem } from "viem";
import {
  Activity,
  ArrowUpRight,
  ArrowDownRight,
  ExternalLink,
  RefreshCw,
  Clock,
} from "lucide-react";
import { formatUsd } from "@/hooks/useEthPrice";

export interface TradeEvent {
  id: string;
  type: "BUY" | "SELL";
  blockNumber: bigint;
  timestamp: number;
  txHash: string;
  trader: string;
  quoteAmount: number; // in native ETH
  tokenAmount: number; // in TOKEN
  price: number; // in ETH
  marketCap: number; // in ETH
}

interface RealTradingChartProps {
  tokenAddress?: `0x${string}`;
  curveAddress?: `0x${string}`;
  tokenSymbol?: string;
  currentPriceScaled?: bigint;
  currentMarketCap?: bigint;
  currentPriceEth?: number;
  currentMarketCapEth?: number;
  ethPriceUsd?: number;
  launchedAt?: bigint;
  isGraduated?: boolean;
  refreshTrigger?: number;
  onStatsChange?: (stats: { volumeEth: number; tradeCount: number }) => void;
}

export function RealTradingChart({
  tokenAddress,
  curveAddress,
  tokenSymbol = "TOKEN",
  currentPriceScaled,
  currentMarketCap,
  currentPriceEth,
  currentMarketCapEth,
  ethPriceUsd = 2510,
  launchedAt,
  isGraduated,
  refreshTrigger,
  onStatsChange,
}: RealTradingChartProps) {
  const publicClient = usePublicClient();
  const [trades, setTrades] = useState<TradeEvent[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [activeMetric, setActiveMetric] = useState<"price" | "marketCap">("marketCap");
  const [hoveredPoint, setHoveredPoint] = useState<{
    x: number;
    y: number;
    trade: TradeEvent | null;
    displayValue: string;
    displayLabel: string;
  } | null>(null);

  // Fetch real onchain trades from the BondingCurve events
  const fetchTrades = useCallback(async () => {
    if (!publicClient || !curveAddress || curveAddress === "0x0000000000000000000000000000000000000000") {
      return;
    }

    try {
      setIsLoading(true);
      const currentBlock = await publicClient.getBlockNumber();
      // On Robinhood Chain, fetch recent 200,000 blocks to capture complete trade history
      const fromBlock = currentBlock > 200000n ? currentBlock - 200000n : 0n;

      const buyFilter = parseAbiItem(
        "event CurveBuy(address indexed buyer, address indexed recipient, uint256 quoteIn, uint256 tokensOut, uint256 fee, uint256 tax)"
      );
      const sellFilter = parseAbiItem(
        "event CurveSell(address indexed seller, address indexed recipient, uint256 tokensIn, uint256 quoteOut, uint256 fee, uint256 tax)"
      );

      const [buyLogs, sellLogs] = await Promise.all([
        publicClient.getLogs({
          address: curveAddress,
          event: buyFilter,
          fromBlock,
          toBlock: currentBlock,
        }),
        publicClient.getLogs({
          address: curveAddress,
          event: sellFilter,
          fromBlock,
          toBlock: currentBlock,
        }),
      ]);

      const now = Date.now();
      // Robinhood block time is ~2 seconds per block
      const parsedBuys: TradeEvent[] = buyLogs.map((l) => {
        const blocksAgo = Number(currentBlock - l.blockNumber);
        const ts = now - blocksAgo * 2000;
        const qEth = Number(formatUnits(l.args.quoteIn ?? 0n, 18));
        const tTokens = Number(formatUnits(l.args.tokensOut ?? 0n, 18));
        const p = tTokens > 0 ? qEth / tTokens : 0.00000000168;
        const mc = p * 1_000_000_000;
        return {
          id: `${l.transactionHash}-${l.logIndex}`,
          type: "BUY",
          blockNumber: l.blockNumber,
          timestamp: ts,
          txHash: l.transactionHash,
          trader: l.args.buyer || "0x",
          quoteAmount: qEth,
          tokenAmount: tTokens,
          price: p,
          marketCap: mc,
        };
      });

      const parsedSells: TradeEvent[] = sellLogs.map((l) => {
        const blocksAgo = Number(currentBlock - l.blockNumber);
        const ts = now - blocksAgo * 2000;
        const qEth = Number(formatUnits(l.args.quoteOut ?? 0n, 18));
        const tTokens = Number(formatUnits(l.args.tokensIn ?? 0n, 18));
        const p = tTokens > 0 ? qEth / tTokens : 0.00000000168;
        const mc = p * 1_000_000_000;
        return {
          id: `${l.transactionHash}-${l.logIndex}`,
          type: "SELL",
          blockNumber: l.blockNumber,
          timestamp: ts,
          txHash: l.transactionHash,
          trader: l.args.seller || "0x",
          quoteAmount: qEth,
          tokenAmount: tTokens,
          price: p,
          marketCap: mc,
        };
      });

      // Combine and sort chronologically
      const allTrades = [...parsedBuys, ...parsedSells].sort(
        (a, b) => a.timestamp - b.timestamp
      );

      setTrades(allTrades);
    } catch (err) {
      console.warn("Failed to fetch on-chain trades:", err);
    } finally {
      setIsLoading(false);
    }
  }, [publicClient, curveAddress]);

  useEffect(() => {
    fetchTrades();
  }, [fetchTrades, refreshTrigger]);

  // Construct chart series: Floor baseline -> onchain trades -> latest live point
  const chartSeries = useMemo(() => {
    // Initial floor price for Pons v2 is 1.68 ETH MC / 1B tokens = 0.00000000168 ETH
    const initialPrice = 0.00000000168;
    const initialMc = 1.68;
    const launchTs = launchedAt ? Number(launchedAt) * 1000 : Date.now() - 3600000;

    const points: Array<{
      timestamp: number;
      price: number;
      marketCap: number;
      trade: TradeEvent | null;
    }> = [
      {
        timestamp: launchTs,
        price: initialPrice,
        marketCap: initialMc,
        trade: null,
      },
    ];

    // Append all real on-chain trades
    trades.forEach((t) => {
      points.push({
        timestamp: t.timestamp,
        price: t.price,
        marketCap: t.marketCap,
        trade: t,
      });
    });

    // Append latest live point from props if provided
    if (currentPriceEth !== undefined && currentMarketCapEth !== undefined) {
      points.push({
        timestamp: Date.now(),
        price: currentPriceEth > 0 ? currentPriceEth : initialPrice,
        marketCap: currentMarketCapEth > 0 ? currentMarketCapEth : initialMc,
        trade: null,
      });
    } else if (currentPriceScaled && currentMarketCap) {
      const livePrice = Number(formatUnits(currentPriceScaled, 18));
      const liveMc = Number(formatUnits(currentMarketCap, 18));
      points.push({
        timestamp: Date.now(),
        price: livePrice > 0 ? livePrice : initialPrice,
        marketCap: liveMc > 0 ? liveMc : initialMc,
        trade: null,
      });
    } else {
      points.push({
        timestamp: Date.now(),
        price: points[points.length - 1].price,
        marketCap: points[points.length - 1].marketCap,
        trade: null,
      });
    }

    return points;
  }, [trades, currentPriceEth, currentMarketCapEth, currentPriceScaled, currentMarketCap, launchedAt]);

  // Current stats derived from real onchain points
  const latestPoint = chartSeries[chartSeries.length - 1];
  const initialPoint = chartSeries[0];
  const currentPriceDisplay = currentPriceEth !== undefined && currentPriceEth > 0
    ? currentPriceEth
    : latestPoint.price;
  const currentMcDisplay = currentMarketCapEth !== undefined && currentMarketCapEth > 0
    ? currentMarketCapEth
    : latestPoint.marketCap;

  const currentMcUsd = currentMcDisplay * ethPriceUsd;
  const currentPriceUsd = currentPriceDisplay * ethPriceUsd;

  const priceDeltaPercent =
    initialPoint.price > 0
      ? ((currentPriceDisplay - initialPoint.price) / initialPoint.price) * 100
      : 0;

  const isPositive = priceDeltaPercent >= 0;

  // High, Low, Total Volume in native ETH & USD
  const prices = chartSeries.map((p) => p.price);
  const maxPrice = Math.max(...prices);
  const minPrice = Math.min(...prices);
  const totalVolumeETH = trades.reduce((acc, t) => acc + t.quoteAmount, 0);
  const totalVolumeUSD = totalVolumeETH * ethPriceUsd;

  // Sync volume to parent component
  useEffect(() => {
    if (onStatsChange) {
      onStatsChange({
        volumeEth: totalVolumeETH,
        tradeCount: trades.length,
      });
    }
  }, [totalVolumeETH, trades.length, onStatsChange]);

  // SVG Chart Geometry
  const svgWidth = 800;
  const svgHeight = 280;
  const padding = { top: 20, right: 30, bottom: 30, left: 65 };
  const graphWidth = svgWidth - padding.left - padding.right;
  const graphHeight = svgHeight - padding.top - padding.bottom;

  const values = chartSeries.map((p) =>
    activeMetric === "price" ? p.price * ethPriceUsd : p.marketCap * ethPriceUsd
  );
  const valMin = Math.min(...values);
  const valMax = Math.max(...values);
  const valRange = valMax === valMin ? valMax * 0.1 || 1 : valMax - valMin;

  const yMin = Math.max(0, valMin - valRange * 0.1);
  const yMax = valMax + valRange * 0.1;

  const tMin = chartSeries[0].timestamp;
  const tMax = chartSeries[chartSeries.length - 1].timestamp;
  const tRange = tMax === tMin ? 1 : tMax - tMin;

  // Compute SVG Points
  const coordinates = useMemo(() => {
    return chartSeries.map((p) => {
      const x = padding.left + ((p.timestamp - tMin) / tRange) * graphWidth;
      const val = activeMetric === "price" ? p.price * ethPriceUsd : p.marketCap * ethPriceUsd;
      const y = padding.top + (1 - (val - yMin) / (yMax - yMin)) * graphHeight;
      return { x, y, point: p };
    });
  }, [chartSeries, tMin, tRange, graphWidth, activeMetric, ethPriceUsd, yMin, yMax, graphHeight, padding.left, padding.top]);

  // SVG Path strings
  const linePath = useMemo(() => {
    if (coordinates.length === 0) return "";
    return coordinates.reduce((acc, curr, idx) => {
      return idx === 0 ? `M ${curr.x} ${curr.y}` : `${acc} L ${curr.x} ${curr.y}`;
    }, "");
  }, [coordinates]);

  const areaPath = useMemo(() => {
    if (coordinates.length === 0) return "";
    const firstX = coordinates[0].x;
    const lastX = coordinates[coordinates.length - 1].x;
    const bottomY = padding.top + graphHeight;
    return `${linePath} L ${lastX} ${bottomY} L ${firstX} ${bottomY} Z`;
  }, [linePath, coordinates, padding.top, graphHeight]);

  // Y-axis ticks in USD
  const yTicks = useMemo(() => {
    const ticksCount = 4;
    return Array.from({ length: ticksCount + 1 }).map((_, i) => {
      const value = yMin + ((yMax - yMin) * i) / ticksCount;
      const y = padding.top + (1 - i / ticksCount) * graphHeight;
      return { value, y };
    });
  }, [yMin, yMax, graphHeight, padding.top]);

  return (
    <div className="sketch-card p-5 sm:p-6 space-y-6 bg-[#121318] border border-zinc-800 rounded-2xl">
      {/* Chart Header Bar */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-zinc-800 pb-4">
        {/* Left: Price & Market Cap Real-Time */}
        <div className="space-y-1">
          <div className="flex items-center space-x-3">
            <span className="text-2xl sm:text-3xl font-black font-mono text-white tracking-tight">
              {activeMetric === "price"
                ? formatUsd(currentPriceUsd)
                : formatUsd(currentMcUsd)}
            </span>
            <span className="text-xs font-mono text-yellow-400 bg-yellow-400/10 border border-yellow-400/30 px-2 py-0.5 rounded-md">
              {activeMetric === "price"
                ? `${currentPriceDisplay < 0.0001 ? currentPriceDisplay.toFixed(9) : currentPriceDisplay.toFixed(6)} ETH`
                : `${currentMcDisplay.toFixed(3)} ETH`}
            </span>
            <span
              className={`inline-flex items-center space-x-0.5 text-xs font-mono font-bold px-2 py-0.5 rounded-md ${
                isPositive
                  ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30"
                  : "bg-rose-500/15 text-rose-400 border border-rose-500/30"
              }`}
            >
              {isPositive ? (
                <ArrowUpRight className="w-3.5 h-3.5" />
              ) : (
                <ArrowDownRight className="w-3.5 h-3.5" />
              )}
              <span>{priceDeltaPercent >= 0 ? "+" : ""}{priceDeltaPercent.toFixed(2)}%</span>
            </span>
          </div>

          <div className="flex flex-wrap items-center gap-3 text-xs font-mono text-slate-400">
            <span>
              Pair: <strong className="text-yellow-400">{tokenSymbol}/ETH</strong>
            </span>
            <span>•</span>
            <span>
              MC: <strong className="text-white font-bold">{formatUsd(currentMcUsd)}</strong> <span className="text-slate-500 text-[11px]">({currentMcDisplay.toFixed(3)} ETH)</span>
            </span>
            <span>•</span>
            <span>
              24h High: <strong className="text-slate-200">{formatUsd(maxPrice * ethPriceUsd)}</strong>
            </span>
            <span>•</span>
            <span>
              24h Low: <strong className="text-slate-200">{formatUsd(minPrice * ethPriceUsd)}</strong>
            </span>
            <span>•</span>
            <span>
              Total Vol: <strong className="text-yellow-400 font-bold">{formatUsd(totalVolumeUSD)}</strong> <span className="text-slate-500 text-[11px]">({totalVolumeETH.toFixed(3)} ETH)</span>
            </span>
          </div>
        </div>

        {/* Right: Metric Switcher & Live Indicator */}
        <div className="flex items-center space-x-2 shrink-0">
          {/* Market Status Indicator */}
          <div className="px-2.5 py-1 text-[11px] font-mono flex items-center space-x-1.5 bg-yellow-400/10 border border-yellow-400/30 text-yellow-400 rounded-md">
            <span className="w-2 h-2 rounded-full bg-yellow-400 animate-pulse"></span>
            <span>{isGraduated ? "Uniswap v4 Pool" : "Robinhood On-Chain"}</span>
          </div>

          {/* Metric Switch */}
          <div className="clay-inset p-0.5 rounded-xl flex text-xs font-mono">
            <button
              type="button"
              onClick={() => setActiveMetric("marketCap")}
              className={`px-3 py-1 rounded-lg transition font-bold ${
                activeMetric === "marketCap"
                  ? "clay-btn-primary text-slate-950 shadow"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              Market Cap
            </button>
            <button
              type="button"
              onClick={() => setActiveMetric("price")}
              className={`px-3 py-1 rounded-lg transition font-bold ${
                activeMetric === "price"
                  ? "clay-btn-primary text-slate-950 shadow"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              Price
            </button>
          </div>

          {/* Refresh Button */}
          <button
            type="button"
            onClick={fetchTrades}
            disabled={isLoading}
            className="p-1.5 clay-btn-secondary text-slate-400 hover:text-white"
            title="Refresh onchain trades"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? "animate-spin text-sky-400" : ""}`} />
          </button>
        </div>
      </div>

      {/* Interactive SVG Chart Container */}
      <div className="relative w-full overflow-hidden clay-surface rounded-2xl p-2 sm:p-4">
        {/* Subtle grid backdrop */}
        <svg
          viewBox={`0 0 ${svgWidth} ${svgHeight}`}
          className="w-full h-56 sm:h-72 select-none overflow-visible"
          onMouseLeave={() => setHoveredPoint(null)}
          onMouseMove={(e) => {
            const rect = e.currentTarget.getBoundingClientRect();
            const mouseX = ((e.clientX - rect.left) / rect.width) * svgWidth;
            // Find closest coordinate point
            let closest = coordinates[0];
            let minDist = Infinity;
            coordinates.forEach((c) => {
              const d = Math.abs(c.x - mouseX);
              if (d < minDist) {
                minDist = d;
                closest = c;
              }
            });

            if (closest) {
              const valUsd = activeMetric === "price" ? closest.point.price * ethPriceUsd : closest.point.marketCap * ethPriceUsd;
              const valEth = activeMetric === "price" ? closest.point.price : closest.point.marketCap;
              const formattedVal = `${formatUsd(valUsd)} (${activeMetric === "price" ? (valEth < 0.0001 ? valEth.toFixed(9) : valEth.toFixed(6)) : valEth.toFixed(3)} ETH)`;
              setHoveredPoint({
                x: closest.x,
                y: closest.y,
                trade: closest.point.trade,
                displayValue: formattedVal,
                displayLabel: new Date(closest.point.timestamp).toLocaleTimeString(),
              });
            }
          }}
        >
          <defs>
            <linearGradient id="bullGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#10b981" stopOpacity="0.35" />
              <stop offset="100%" stopColor="#10b981" stopOpacity="0.0" />
            </linearGradient>
            <linearGradient id="bearGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#f43f5e" stopOpacity="0.35" />
              <stop offset="100%" stopColor="#f43f5e" stopOpacity="0.0" />
            </linearGradient>
            <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feComposite in="SourceGraphic" in2="blur" operator="over" />
            </filter>
          </defs>

          {/* Horizontal Grid lines */}
          {yTicks.map((tick, i) => (
            <g key={i}>
              <line
                x1={padding.left}
                y1={tick.y}
                x2={svgWidth - padding.right}
                y2={tick.y}
                stroke="#123d22"
                strokeDasharray="4 4"
                strokeWidth="1"
              />
              <text
                x={padding.left - 8}
                y={tick.y + 4}
                textAnchor="end"
                fill="#4ade80"
                fontSize="10"
                fontFamily="monospace"
              >
                {formatUsd(tick.value)}
              </text>
            </g>
          ))}

          {/* Area fill */}
          <path
            d={areaPath}
            fill={isPositive ? "url(#bullGradient)" : "url(#bearGradient)"}
          />

          {/* Main Price Line */}
          <path
            d={linePath}
            fill="none"
            stroke={isPositive ? "#10b981" : "#f43f5e"}
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            filter="url(#glow)"
          />

          {/* Individual trade markers */}
          {coordinates.map((c, i) => {
            if (!c.point.trade) return null;
            const isBuy = c.point.trade.type === "BUY";
            return (
              <circle
                key={i}
                cx={c.x}
                cy={c.y}
                r={hoveredPoint && hoveredPoint.x === c.x ? 5 : 3.5}
                className="transition-all duration-150 cursor-pointer"
                fill={isBuy ? "#22c55e" : "#ef4444"}
                stroke="#ffffff"
                strokeWidth="1.5"
              />
            );
          })}

          {/* Crosshair indicator when hovering */}
          {hoveredPoint && (
            <g>
              <line
                x1={hoveredPoint.x}
                y1={padding.top}
                x2={hoveredPoint.x}
                y2={padding.top + graphHeight}
                stroke="#4ade80"
                strokeWidth="1"
                strokeDasharray="2 2"
              />
              <circle
                cx={hoveredPoint.x}
                cy={hoveredPoint.y}
                r="5"
                fill="#22c55e"
                stroke="#ffffff"
                strokeWidth="2"
                filter="url(#glow)"
              />
            </g>
          )}
        </svg>

        {/* Hover Tooltip Overlay */}
        {hoveredPoint && (
          <div
            className="absolute pointer-events-none sketch-card p-3 text-xs font-mono shadow-2xl border border-emerald-500/40 bg-[#06180e]/95 space-y-1 z-20"
            style={{
              left: `${Math.min(Math.max(10, (hoveredPoint.x / svgWidth) * 100), 75)}%`,
              top: "12px",
            }}
          >
            <div className="flex items-center justify-between gap-3 border-b border-emerald-900/60 pb-1">
              <span className="text-slate-400 text-[10px]">{hoveredPoint.displayLabel}</span>
              {hoveredPoint.trade && (
                <span
                  className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${
                    hoveredPoint.trade.type === "BUY"
                      ? "bg-emerald-500/20 text-emerald-300"
                      : "bg-rose-500/20 text-rose-300"
                  }`}
                >
                  {hoveredPoint.trade.type}
                </span>
              )}
            </div>
            <div className="text-emerald-300 font-extrabold text-sm">{hoveredPoint.displayValue}</div>
            {hoveredPoint.trade && (
              <div className="text-[10px] text-slate-400 space-y-0.5 pt-0.5">
                <div>Vol USD: {formatUsd(hoveredPoint.trade.quoteAmount * ethPriceUsd)} ({hoveredPoint.trade.quoteAmount.toFixed(4)} ETH)</div>
                <div>Tokens: {hoveredPoint.trade.tokenAmount.toLocaleString(undefined, { maximumFractionDigits: 0 })}</div>
              </div>
            )}
          </div>
        )}

        {/* Zero trades notice if brand new token */}
        {trades.length === 0 && (
          <div className="absolute inset-x-0 bottom-4 flex justify-center pointer-events-none">
            <span className="sketch-badge px-3 py-1 text-[11px] font-mono text-emerald-300">
              Floor Price Initialized • Ready to Trade
            </span>
          </div>
        )}
      </div>

      {/* Recent On-Chain Trades Table */}
      <div className="space-y-3 pt-2">
        <div className="flex items-center justify-between text-xs">
          <span className="font-bold text-white flex items-center space-x-2">
            <Activity className="w-4 h-4 text-emerald-400" />
            <span>Recent On-Chain Activity ({trades.length})</span>
          </span>
          <span className="text-[11px] font-mono text-slate-400">
            {tokenAddress ? `Token: ${tokenAddress.slice(0, 6)}...${tokenAddress.slice(-4)} • ` : ""}Source: Robinhood Chain
          </span>
        </div>

        {trades.length > 0 ? (
          <div className="max-h-[240px] overflow-y-auto overflow-x-auto rounded-xl border border-zinc-800 bg-zinc-950/90">
            <table className="w-full text-left text-xs font-mono relative">
              <thead className="sticky top-0 z-10 bg-zinc-900 text-zinc-300 border-b border-zinc-800 text-[11px] shadow-sm">
                <tr>
                  <th className="py-2.5 px-3">Type</th>
                  <th className="py-2.5 px-3">Price (USD)</th>
                  <th className="py-2.5 px-3">Volume (USD)</th>
                  <th className="py-2.5 px-3">Tokens</th>
                  <th className="py-2.5 px-3">Trader</th>
                  <th className="py-2.5 px-3 text-right">Explorer</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-800/80 text-zinc-200">
                {trades
                  .slice()
                  .reverse()
                  .map((t) => (
                    <tr key={t.id} className="hover:bg-emerald-500/10 transition">
                      <td className="py-2 px-3">
                        <span
                          className={`px-2 py-0.5 rounded font-bold text-[10px] ${
                            t.type === "BUY"
                              ? "bg-emerald-500/20 text-emerald-400"
                              : "bg-rose-500/20 text-rose-400"
                          }`}
                        >
                          {t.type}
                        </span>
                      </td>
                      <td className="py-2 px-3 text-slate-200">
                        {formatUsd(t.price * ethPriceUsd)}
                        <span className="text-[10px] text-slate-500 block">{t.price < 0.0001 ? t.price.toFixed(9) : t.price.toFixed(6)} ETH</span>
                      </td>
                      <td className="py-2 px-3 font-semibold text-white">
                        {formatUsd(t.quoteAmount * ethPriceUsd)}
                        <span className="text-[10px] text-slate-500 block">{t.quoteAmount.toFixed(4)} ETH</span>
                      </td>
                      <td className="py-2 px-3 text-slate-300">
                        {t.tokenAmount.toLocaleString(undefined, { maximumFractionDigits: 0 })}
                      </td>
                      <td className="py-2 px-3 text-slate-400 text-[11px]">
                        {`${t.trader.slice(0, 6)}...${t.trader.slice(-4)}`}
                      </td>
                      <td className="py-2 px-3 text-right">
                        <a
                          href={`https://robinhoodchain.blockscout.com/tx/${t.txHash}`}
                          target="_blank"
                          rel="noreferrer"
                          className="text-emerald-400 hover:text-emerald-300 inline-flex items-center space-x-1"
                        >
                          <span>Tx</span>
                          <ExternalLink className="w-3 h-3" />
                        </a>
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="py-8 text-center clay-surface rounded-xl text-xs font-mono text-slate-500 space-y-1">
            <Clock className="w-5 h-5 mx-auto text-slate-600 mb-1" />
            <p>No on-chain trades executed yet for this curve.</p>
            <p className="text-[11px] text-slate-600">
              Execute a buy or sell on the right to see live transaction points.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

