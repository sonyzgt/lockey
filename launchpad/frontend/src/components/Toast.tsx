"use client";

import React, { createContext, useContext, useState, useCallback, useEffect } from "react";
import { CheckCircle2, AlertCircle, Info, X, ExternalLink } from "lucide-react";

export type ToastType = "success" | "error" | "info";

export interface ToastItem {
  id: string;
  type: ToastType;
  title: string;
  message?: string;
  txHash?: string;
  duration?: number;
}

interface ToastContextType {
  toast: (options: Omit<ToastItem, "id">) => void;
  success: (title: string, message?: string, txHash?: string) => void;
  error: (title: string, message?: string) => void;
  info: (title: string, message?: string) => void;
  dismiss: (id: string) => void;
}

const ToastContext = createContext<ToastContextType | undefined>(undefined);

export function useToast() {
  const context = useContext(ToastContext);
  if (!context) {
    throw new Error("useToast must be used within a ToastProvider");
  }
  return context;
}

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  const dismiss = useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const toast = useCallback(
    ({ type, title, message, txHash, duration = 5000 }: Omit<ToastItem, "id">) => {
      setToasts((prev) => {
        // Prevent duplicate toast spamming
        const isDuplicate = prev.some(
          (t) => t.title === title && t.txHash === txHash && t.message === message
        );
        if (isDuplicate) return prev;

        const id = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
        // Cap maximum simultaneous toasts to 3 to keep screen clean
        const trimmed = prev.slice(-2);
        return [...trimmed, { id, type, title, message, txHash, duration }];
      });
    },
    []
  );

  const success = useCallback(
    (title: string, message?: string, txHash?: string) => {
      toast({ type: "success", title, message, txHash, duration: 5500 });
    },
    [toast]
  );

  const error = useCallback(
    (title: string, message?: string) => {
      toast({ type: "error", title, message, duration: 7000 });
    },
    [toast]
  );

  const info = useCallback(
    (title: string, message?: string) => {
      toast({ type: "info", title, message, duration: 5000 });
    },
    [toast]
  );

  return (
    <ToastContext.Provider value={{ toast, success, error, info, dismiss }}>
      {children}
      {/* Floating Pop-up Toast Container */}
      <div
        aria-live="polite"
        className="fixed top-5 right-5 z-[9999] flex flex-col gap-3 max-w-sm sm:max-w-md w-full pointer-events-none px-4 sm:px-0"
      >
        {toasts.map((item) => (
          <ToastCard key={item.id} item={item} onDismiss={() => dismiss(item.id)} />
        ))}
      </div>
    </ToastContext.Provider>
  );
}

function ToastCard({ item, onDismiss }: { item: ToastItem; onDismiss: () => void }) {
  const duration = item.duration || 5000;

  useEffect(() => {
    const timer = setTimeout(() => {
      onDismiss();
    }, duration);
    return () => clearTimeout(timer);
  }, [duration, onDismiss]);

  const isSuccess = item.type === "success";
  const isError = item.type === "error";

  return (
    <div
      role="alert"
      className={`pointer-events-auto relative overflow-hidden rounded-2xl p-4 sm:p-5 backdrop-blur-xl border shadow-2xl transition-all duration-300 animate-in fade-in slide-in-from-top-4 ${
        isSuccess
          ? "bg-[#06181b]/95 border-emerald-500/40 text-emerald-100 shadow-emerald-950/60"
          : isError
          ? "bg-[#1f0a0d]/95 border-rose-500/40 text-rose-100 shadow-rose-950/60"
          : "bg-[#061224]/95 border-sky-500/40 text-sky-100 shadow-sky-950/60"
      }`}
    >
      <div className="flex items-start space-x-3.5">
        {/* Glow Icon */}
        <div
          className={`shrink-0 w-9 h-9 rounded-xl flex items-center justify-center border shadow-inner ${
            isSuccess
              ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-400"
              : isError
              ? "bg-rose-500/10 border-rose-500/30 text-rose-400"
              : "bg-sky-500/10 border-sky-500/30 text-sky-400"
          }`}
        >
          {isSuccess && <CheckCircle2 className="w-5 h-5" />}
          {isError && <AlertCircle className="w-5 h-5" />}
          {!isSuccess && !isError && <Info className="w-5 h-5" />}
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0 pr-6 space-y-1">
          <h4 className="text-sm font-extrabold text-white tracking-wide leading-tight">
            {item.title}
          </h4>
          {item.message && (
            <p className="text-xs text-slate-300 leading-relaxed break-words font-medium">
              {item.message}
            </p>
          )}

          {item.txHash && (
            <div className="pt-2">
              <a
                href={`https://robinhoodchain.blockscout.com/tx/${item.txHash}`}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center space-x-1.5 text-[11px] font-mono font-bold text-emerald-400 hover:text-emerald-300 underline decoration-emerald-500/40 hover:decoration-emerald-400 transition"
              >
                <span>View on Robinhood Explorer</span>
                <ExternalLink className="w-3 h-3" />
              </a>
            </div>
          )}
        </div>

        {/* Dismiss X button */}
        <button
          type="button"
          onClick={onDismiss}
          className="absolute top-3.5 right-3.5 p-1 rounded-lg text-slate-400 hover:text-white hover:bg-white/10 transition"
          aria-label="Close notification"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Auto-dismiss progress indicator */}
      <div
        className={`absolute bottom-0 left-0 h-1 ${
          isSuccess ? "bg-emerald-400/40" : isError ? "bg-rose-400/40" : "bg-sky-400/40"
        }`}
        style={{
          width: "100%",
          animation: `shrinkWidth ${duration}ms linear forwards`,
        }}
      />
      <style jsx>{`
        @keyframes shrinkWidth {
          from {
            width: 100%;
          }
          to {
            width: 0%;
          }
        }
      `}</style>
    </div>
  );
}
