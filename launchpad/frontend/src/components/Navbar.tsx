"use client";

import Link from "next/link";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { Wallet, AlertTriangle } from "lucide-react";
import { robinhoodChain } from "../config/chain";

export function Navbar() {
  const { address, isConnected, chain } = useAccount();
  const { connectors, connect } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const isWrongNetwork = isConnected && chain?.id !== robinhoodChain.id;

  return (
    <header className="sticky top-0 z-50 bg-[#090a0f]/95 backdrop-blur-md border-b border-zinc-800 shadow-sm">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center space-x-8">
          <Link href="/" className="flex items-center space-x-3 group">
            <div className="relative w-10 h-10 rounded-xl border border-yellow-500/40 bg-zinc-900 flex items-center justify-center p-1.5 shadow-sm transition-colors group-hover:border-yellow-400">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/lockey-logo.svg"
                alt="LOCKEY Logo"
                className="w-full h-full object-contain"
              />
            </div>
            <div>
              <div className="flex items-center space-x-2">
                <span className="text-xl font-extrabold text-white tracking-tight group-hover:text-yellow-400 transition">
                  LOCKEY
                </span>
                <span className="text-[10px] px-1.5 py-0.2 bg-yellow-400/10 text-yellow-400 font-mono font-bold rounded border border-yellow-400/30 uppercase">
                  Radar
                </span>
              </div>
              <span className="block text-[10px] text-yellow-500 font-mono tracking-wider uppercase">
                Robinhood Chain • 4663
              </span>
            </div>
          </Link>

          <nav className="hidden md:flex items-center space-x-6 text-sm font-medium">
            <Link
              href="/"
              className="text-zinc-300 hover:text-yellow-400 transition-colors flex items-center space-x-1.5"
            >
              <span>X Radar</span>
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-yellow-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2 w-2 bg-yellow-400"></span>
              </span>
            </Link>
            <Link
              href="/creator-dashboard"
              className="text-zinc-300 hover:text-yellow-400 transition-colors"
            >
              Creator Fees
            </Link>
            <Link
              href="/docs"
              className="text-zinc-300 hover:text-yellow-400 transition-colors flex items-center space-x-1"
            >
              <span>Docs</span>
            </Link>
          </nav>
        </div>

        <div className="flex items-center space-x-3">
          <a
            href="https://x.com"
            target="_blank"
            rel="noopener noreferrer"
            className="hidden sm:flex items-center space-x-2 px-3 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-700 hover:border-yellow-500/40 rounded-lg text-xs font-medium text-zinc-300 hover:text-yellow-400 transition-colors"
            title="Follow @lockey on X"
          >
            <svg className="w-3.5 h-3.5 fill-current text-yellow-400" viewBox="0 0 24 24">
              <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 22.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
            </svg>
            <span className="font-semibold">@lockey</span>
          </a>

          <div className="hidden sm:flex items-center space-x-2 px-3 py-1.5 bg-zinc-900 border border-zinc-800 text-xs font-mono text-zinc-300 rounded-lg">
            <span className="w-2 h-2 rounded-full bg-yellow-400 animate-pulse"></span>
            <span className="font-semibold text-white">Robinhood</span>
            <span className="text-zinc-600">•</span>
            <span className="text-yellow-400 font-bold">ETH</span>
          </div>

          {isConnected ? (
            <div className="flex items-center space-x-2">
              {isWrongNetwork && (
                <button
                  onClick={() => switchChain?.({ chainId: robinhoodChain.id })}
                  className="flex items-center space-x-1.5 px-3 py-1.5 bg-rose-500/20 text-rose-300 hover:bg-rose-500/30 border border-rose-500/40 rounded-lg text-xs font-semibold"
                >
                  <AlertTriangle className="w-3.5 h-3.5" />
                  <span>Switch Network</span>
                </button>
              )}
              <button
                onClick={() => disconnect()}
                className="flex items-center space-x-2 px-3.5 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-700 hover:border-yellow-500/50 rounded-lg text-xs font-mono text-zinc-200 transition-colors"
              >
                <div className="w-2 h-2 rounded-full bg-yellow-400"></div>
                <span className="font-semibold">
                  {address ? `${address.slice(0, 6)}...${address.slice(-4)}` : ""}
                </span>
              </button>
            </div>
          ) : (
            <button
              onClick={() => {
                const connector = connectors[0];
                if (connector) connect({ connector });
              }}
              className="flex items-center space-x-2 px-4 py-2 bg-yellow-400 hover:bg-yellow-300 text-black font-semibold text-xs rounded-lg shadow-sm transition-colors"
            >
              <Wallet className="w-4 h-4" />
              <span>Connect Wallet</span>
            </button>
          )}
        </div>
      </div>
    </header>
  );
}
