"use client";

import { useState, useEffect } from "react";
import { X, Key, AtSign, Plus, Trash2, Check, RefreshCw, ExternalLink, ShieldCheck, Eye, EyeOff } from "lucide-react";

interface XScannerSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (settings: {
    bearerToken: string;
    trackedAccounts: string[];
    refreshInterval: number;
  }) => void;
}

const DEFAULT_ACCOUNTS = [
  "elonmusk",
  "VitalikButerin",
  "cz_binance",
  "whale_alert",
];

export function XScannerSettingsModal({
  isOpen,
  onClose,
  onSave,
}: XScannerSettingsModalProps) {
  const [bearerToken, setBearerToken] = useState("");
  const [showToken, setShowToken] = useState(false);
  const [trackedAccounts, setTrackedAccounts] = useState<string[]>(DEFAULT_ACCOUNTS);
  const [newAccountInput, setNewAccountInput] = useState("");
  const [refreshInterval, setRefreshInterval] = useState<number>(30); // seconds
  const [saveSuccess, setSaveSuccess] = useState(false);

  // Load from localStorage on mount
  useEffect(() => {
    try {
      const savedToken = localStorage.getItem("vana_x_bearer_token") || "";
      const savedAccounts = localStorage.getItem("vana_x_tracked_accounts");
      const savedInterval = localStorage.getItem("vana_x_refresh_interval");

      if (savedToken) setBearerToken(savedToken);
      if (savedAccounts) {
        const parsed = JSON.parse(savedAccounts);
        if (Array.isArray(parsed) && parsed.length > 0) {
          setTrackedAccounts(parsed);
        }
      }
      if (savedInterval) {
        setRefreshInterval(Number(savedInterval) || 30);
      }
    } catch (e) {
      console.warn("Error reading X scanner settings:", e);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  const handleAddAccount = () => {
    const clean = newAccountInput.replace("@", "").trim();
    if (!clean) return;
    if (!trackedAccounts.some((a) => a.toLowerCase() === clean.toLowerCase())) {
      setTrackedAccounts([...trackedAccounts, clean]);
    }
    setNewAccountInput("");
  };

  const handleRemoveAccount = (username: string) => {
    setTrackedAccounts(trackedAccounts.filter((a) => a !== username));
  };

  const handleSave = () => {
    try {
      localStorage.setItem("vana_x_bearer_token", bearerToken.trim());
      localStorage.setItem("vana_x_tracked_accounts", JSON.stringify(trackedAccounts));
      localStorage.setItem("vana_x_refresh_interval", refreshInterval.toString());
    } catch (e) {
      console.warn("Could not save to localStorage:", e);
    }

    onSave({
      bearerToken: bearerToken.trim(),
      trackedAccounts,
      refreshInterval,
    });

    setSaveSuccess(true);
    setTimeout(() => {
      setSaveSuccess(false);
      onClose();
    }, 800);
  };

  const handleClearToken = () => {
    setBearerToken("");
    localStorage.removeItem("vana_x_bearer_token");
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm animate-fade-in">
      <div className="relative w-full max-w-lg sketch-card bg-[#06180d] p-6 sm:p-8 space-y-6 shadow-sketch-lg border-2 border-emerald-500 max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between pb-4 border-b border-dashed border-emerald-800/80">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded-sketch bg-[#0c2e1b] border-2 border-emerald-400 flex items-center justify-center text-emerald-300">
              <Key className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-2xl font-kalam font-bold text-white tracking-wide">
                X Scanner Settings
              </h2>
              <p className="text-xs font-hand text-emerald-300/80">
                Configure live X (Twitter) API &amp; monitored accounts
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

        {/* X Bearer Token Input */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <label className="text-sm font-hand font-bold text-slate-200 flex items-center space-x-1.5">
              <span>X (Twitter) API v2 Bearer Token</span>
              <span className="text-[10px] px-2 py-0.5 rounded bg-emerald-900/60 text-emerald-300 border border-emerald-700/50">
                Stored Locally
              </span>
            </label>
            {bearerToken && (
              <button
                type="button"
                onClick={handleClearToken}
                className="text-[11px] font-hand text-rose-400 hover:underline"
              >
                Clear Token
              </button>
            )}
          </div>

          <div className="relative">
            <input
              type={showToken ? "text" : "password"}
              placeholder="AAAAAAAAAAAAAAAAAAAAA..."
              value={bearerToken}
              onChange={(e) => setBearerToken(e.target.value)}
              className="w-full pr-10 pl-4 py-2.5 sketch-inset text-xs font-mono text-emerald-200 placeholder:text-emerald-700 focus:outline-none"
            />
            <button
              type="button"
              onClick={() => setShowToken(!showToken)}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-emerald-400 hover:text-emerald-200"
            >
              {showToken ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            </button>
          </div>

          <p className="text-[11px] font-hand text-slate-400 leading-relaxed">
            Need a token? Generate one from the{" "}
            <a
              href="https://developer.x.com/en/portal/dashboard"
              target="_blank"
              rel="noopener noreferrer"
              className="text-emerald-400 underline hover:text-emerald-300 inline-flex items-center space-x-0.5"
            >
              <span>X Developer Portal</span>
              <ExternalLink className="w-3 h-3 ml-0.5 inline" />
            </a>
            . If empty, the scanner will use the live demo stream.
          </p>
        </div>

        {/* Tracked Accounts Manager */}
        <div className="space-y-3">
          <label className="text-sm font-hand font-bold text-slate-200 block">
            Monitored Accounts (KOLs &amp; News)
          </label>

          <div className="flex gap-2">
            <div className="relative flex-1">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-emerald-500 font-bold font-mono">
                @
              </span>
              <input
                type="text"
                placeholder="elonmusk, cz_binance..."
                value={newAccountInput}
                onChange={(e) => setNewAccountInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    handleAddAccount();
                  }
                }}
                className="w-full pl-8 pr-4 py-2 sketch-inset text-xs font-hand text-white placeholder:text-emerald-700 focus:outline-none"
              />
            </div>
            <button
              type="button"
              onClick={handleAddAccount}
              className="px-3.5 py-2 sketch-btn-secondary text-xs font-hand font-bold text-emerald-200 flex items-center space-x-1"
            >
              <Plus className="w-4 h-4" />
              <span>Add</span>
            </button>
          </div>

          {/* Account Tags */}
          <div className="flex flex-wrap gap-2 pt-1 max-h-36 overflow-y-auto">
            {trackedAccounts.map((handle) => (
              <span
                key={handle}
                className="inline-flex items-center space-x-1.5 px-3 py-1 rounded-sketch bg-[#0c2e1b] border border-emerald-600/60 text-xs font-hand font-bold text-emerald-200"
              >
                <span>@{handle}</span>
                <button
                  type="button"
                  onClick={() => handleRemoveAccount(handle)}
                  className="text-slate-400 hover:text-rose-400 transition-colors"
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              </span>
            ))}
            {trackedAccounts.length === 0 && (
              <p className="text-xs font-hand text-slate-500 italic">
                No accounts monitored. Add handles above.
              </p>
            )}
          </div>
        </div>

        {/* Auto-Refresh Interval */}
        <div className="space-y-2">
          <label className="text-sm font-hand font-bold text-slate-200 block">
            Auto-Refresh Stream Interval
          </label>
          <div className="grid grid-cols-4 gap-2">
            {[15, 30, 60, 0].map((interval) => (
              <button
                key={interval}
                type="button"
                onClick={() => setRefreshInterval(interval)}
                className={`py-2 px-3 rounded-sketch text-xs font-hand font-bold transition ${
                  refreshInterval === interval
                    ? "sketch-btn-primary text-slate-950"
                    : "sketch-btn-secondary text-slate-300"
                }`}
              >
                {interval === 0 ? "Manual" : `${interval}s`}
              </button>
            ))}
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex items-center justify-end space-x-3 pt-4 border-t border-dashed border-emerald-800/80">
          <button
            type="button"
            onClick={onClose}
            className="px-5 py-2.5 sketch-btn-secondary text-sm font-hand text-slate-300"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSave}
            className="px-6 py-2.5 sketch-btn-primary text-slate-950 font-hand font-bold text-base flex items-center space-x-2"
          >
            {saveSuccess ? (
              <>
                <Check className="w-4 h-4 text-emerald-950" />
                <span>Saved!</span>
              </>
            ) : (
              <span>Save &amp; Apply</span>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}
