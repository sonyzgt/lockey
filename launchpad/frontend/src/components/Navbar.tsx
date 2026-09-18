"use client";

import Link from "next/link";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { Wallet, AlertTriangle, Sparkles } from "lucide-react";
import { robinhoodChain } from "../config/chain";

export function Navbar() {
  const { address, isConnected, chain } = useAccount();
  const { connectors, connect } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const isWrongNetwork = isConnected && chain?.id !== robinhoodChain.id;

  return (
    <header className="sticky top-0 z-50 bg-[#06180d]/90 backdrop-blur-md border-b-2 border-emerald-800/80 shadow-[0_4px_0_0_#000000]">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-20 py-3 flex items-center justify-between">
        <div className="flex items-center space-x-8">
          <Link href="/" className="flex items-center space-x-3 group">
            <div className="relative w-11 h-11 rounded-sketch border-2 border-emerald-400 bg-[#0c2e1b] flex items-center justify-center shadow-sketch-sm group-hover:rotate-3 transition-transform">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="/vana-logo.png"
                alt="VANA Logo"
                className="w-full h-full object-cover rounded-sketch"
              />
            </div>
            <div>
              <div className="flex items-center space-x-1.5">
                <span className="text-2xl font-kalam font-bold text-white tracking-wide group-hover:text-emerald-300 transition">
                  VANA
                </span>
                <span className="text-xs px-1.5 py-0.5 rounded-md bg-emerald-500/20 text-emerald-300 font-hand border border-emerald-500/40">
                  doodle
                </span>
              </div>
              <span className="block text-[10px] text-emerald-400 font-mono tracking-wider uppercase">
                Robinhood Chain • 4663
              </span>
            </div>
          </Link>

          <nav className="hidden md:flex items-center space-x-6 font-hand text-lg font-bold">
            <Link
              href="/"
              className="text-emerald-100 hover:text-emerald-300 hover:sketch-squiggly transition duration-150"
            >
              Explore Curves
            </Link>
            <Link
              href="/create"
              className="text-emerald-100 hover:text-emerald-300 hover:sketch-squiggly transition duration-150"
            >
              Create Token
            </Link>
            <Link
              href="/creator-dashboard"
              className="text-emerald-100 hover:text-emerald-300 hover:sketch-squiggly transition duration-150"
            >
              Creator Fees
            </Link>
            <Link
              href="/docs"
              className="text-emerald-100 hover:text-emerald-300 hover:sketch-squiggly transition duration-150 flex items-center space-x-1"
            >
              <span>Docs</span>
            </Link>
          </nav>
        </div>

        <div className="flex items-center space-x-3">
          <a
            href="https://x.com/vana_family"
            target="_blank"
            rel="noopener noreferrer"
            className="hidden sm:flex items-center space-x-2 px-3 py-1.5 sketch-btn-secondary text-xs font-hand text-emerald-200 hover:text-white"
            title="Follow @vana_family on X"
          >
            <svg className="w-3.5 h-3.5 fill-current text-emerald-400" viewBox="0 0 24 24">
              <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 22.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
            </svg>
            <span className="font-bold">@vana_family</span>
          </a>

          <div className="hidden sm:flex items-center space-x-2 px-3 py-1.5 sketch-badge bg-[#0c2e1b] text-xs font-mono text-emerald-200 border border-emerald-600/40">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
            <span className="font-hand text-sm font-bold text-white">Robinhood</span>
            <span className="text-emerald-500">•</span>
            <span className="text-emerald-300 font-bold">ETH</span>
          </div>

          {isConnected ? (
            <div className="flex items-center space-x-2">
              {isWrongNetwork && (
                <button
                  onClick={() => switchChain?.({ chainId: robinhoodChain.id })}
                  className="flex items-center space-x-1.5 px-3 py-1.5 sketch-btn-secondary bg-rose-500/20 text-rose-300 hover:bg-rose-500/30 text-xs font-bold font-hand shadow-sketch-sm"
                >
                  <AlertTriangle className="w-3.5 h-3.5" />
                  <span>Switch Network</span>
                </button>
              )}
              <button
                onClick={() => disconnect()}
                className="flex items-center space-x-2 px-4 py-2 sketch-btn-secondary text-xs font-mono text-emerald-100"
              >
                <div className="w-2 h-2 rounded-full bg-emerald-400"></div>
                <span className="font-bold">
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
              className="flex items-center space-x-2 px-5 py-2 sketch-btn-primary text-slate-950 font-bold text-base"
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
