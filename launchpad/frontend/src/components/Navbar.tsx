"use client";

import { useState, useRef, useEffect } from "react";
import Link from "next/link";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { Wallet, AlertTriangle, ChevronDown, Coins, LogOut, Copy, Check } from "lucide-react";
import { robinhoodChain } from "../config/chain";

export function Navbar() {
  const { address, isConnected, chain } = useAccount();
  const { connectors, connect } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const [isDropdownOpen, setIsDropdownOpen] = useState(false);
  const [isCopied, setIsCopied] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsDropdownOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
    };
  }, []);

  const isWrongNetwork = isConnected && chain?.id !== robinhoodChain.id;

  return (
    <header className="sticky top-0 z-50 bg-[#090a0f]/95 backdrop-blur-md border-b border-zinc-800 shadow-sm">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        <div className="flex items-center space-x-8">
          <Link href="/" className="flex items-center space-x-3 group">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="/logo.png"
              alt="LOCKEY Logo"
              className="w-11 h-11 object-contain rounded-lg transition-transform group-hover:scale-105"
            />
            <span className="text-xl font-extrabold text-white tracking-tight group-hover:text-yellow-400 transition">
              LOCKEY
            </span>
          </Link>

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

              {/* Wallet Dropdown Container */}
              <div className="relative" ref={dropdownRef}>
                <button
                  onClick={() => setIsDropdownOpen((prev) => !prev)}
                  className="flex items-center space-x-2 px-3.5 py-1.5 bg-zinc-900 hover:bg-zinc-800 border border-zinc-700 hover:border-yellow-500/50 rounded-lg text-xs font-mono text-zinc-200 transition-colors focus:outline-none"
                >
                  <div className="w-2 h-2 rounded-full bg-yellow-400"></div>
                  <span className="font-semibold">
                    {address ? `${address.slice(0, 6)}...${address.slice(-4)}` : ""}
                  </span>
                  <ChevronDown className={`w-3.5 h-3.5 text-zinc-400 transition-transform ${isDropdownOpen ? "rotate-180" : ""}`} />
                </button>

                {isDropdownOpen && (
                  <div className="absolute right-0 mt-2 w-52 bg-[#121318] border border-zinc-800 rounded-xl shadow-2xl py-1.5 z-50 animate-fade-in text-xs font-sans">
                    <div className="px-3.5 py-2 border-b border-zinc-800/80 font-mono text-[11px]">
                      <span className="block text-[10px] text-zinc-500 uppercase tracking-wider font-semibold">Connected</span>
                      <span className="text-zinc-200 font-bold truncate block">{address}</span>
                    </div>

                    <div className="py-1">
                      <Link
                        href="/creator-dashboard"
                        onClick={() => setIsDropdownOpen(false)}
                        className="flex items-center space-x-2.5 px-3.5 py-2 text-zinc-300 hover:text-yellow-400 hover:bg-zinc-900 transition-colors font-medium"
                      >
                        <Coins className="w-4 h-4 text-yellow-400" />
                        <span>Claim Fees</span>
                      </Link>

                      <button
                        onClick={() => {
                          if (address) navigator.clipboard.writeText(address);
                          setIsCopied(true);
                          setTimeout(() => setIsCopied(false), 1500);
                        }}
                        className="w-full flex items-center justify-between px-3.5 py-2 text-zinc-300 hover:text-white hover:bg-zinc-900 transition-colors font-medium text-left"
                      >
                        <div className="flex items-center space-x-2.5">
                          {isCopied ? <Check className="w-4 h-4 text-yellow-400" /> : <Copy className="w-4 h-4 text-zinc-400" />}
                          <span>Copy Address</span>
                        </div>
                        {isCopied && <span className="text-[10px] text-yellow-400 font-mono">Copied!</span>}
                      </button>
                    </div>

                    <div className="border-t border-zinc-800/80 pt-1">
                      <button
                        onClick={() => {
                          setIsDropdownOpen(false);
                          disconnect();
                        }}
                        className="w-full flex items-center space-x-2.5 px-3.5 py-2 text-rose-400 hover:bg-rose-500/10 transition-colors font-medium text-left"
                      >
                        <LogOut className="w-4 h-4" />
                        <span>Logout</span>
                      </button>
                    </div>
                  </div>
                )}
              </div>
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
