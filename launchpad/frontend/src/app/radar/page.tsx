"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import {
  Radar,
  ExternalLink,
  Rocket,
  Heart,
  Repeat,
  MessageCircle,
  AlertCircle,
  CheckCircle2,
  RefreshCw,
  Sparkles,
} from "lucide-react";
import { ParsedTweet } from "../api/x-feed/route";
import { FastLaunchModal } from "@/components/FastLaunchModal";

export default function RadarPage() {
  const [tweets, setTweets] = useState<ParsedTweet[]>([]);
  const [isInitialLoading, setIsInitialLoading] = useState(true);
  const [isScanning, setIsScanning] = useState(false);
  const [lastScannedTime, setLastScannedTime] = useState<string>("just now");
  const [newTweetIds, setNewTweetIds] = useState<Set<string>>(new Set());
  const [selectedTweetForLaunch, setSelectedTweetForLaunch] = useState<ParsedTweet | null>(null);
  const [apiNotice, setApiNotice] = useState<string | null>(null);

  const fetchFeed = useCallback(async () => {
    try {
      setIsScanning(true);
      const res = await fetch("/api/x-feed", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });

      const data = await res.json();
      if (data && data.apiError === "credits_depleted") {
        setApiNotice("X API Notice: Your X Developer credits are depleted (HTTP 402). Streaming updates from your 1,090 accounts. Top up at developer.x.com to stream live from Twitter.");
      } else {
        setApiNotice(null);
      }

      if (data && Array.isArray(data.tweets)) {
        const incoming: ParsedTweet[] = data.tweets;

        setTweets((prev) => {
          if (prev.length === 0) {
            return incoming;
          }

          const existingIds = new Set(prev.map((t) => t.id));
          const newlyArrivedIds: string[] = [];

          incoming.forEach((t) => {
            if (!existingIds.has(t.id)) {
              newlyArrivedIds.push(t.id);
            }
          });

          // Mark newly detected tweets
          if (newlyArrivedIds.length > 0) {
            setNewTweetIds((old) => {
              const updated = new Set(old);
              newlyArrivedIds.forEach((id) => updated.add(id));
              return updated;
            });
          }

          // Merge and deduplicate by ID
          const existingMap = new Map(prev.map((t) => [t.id, t]));
          incoming.forEach((t) => existingMap.set(t.id, t));

          // Sort descending by createdAt (newest first)
          const merged = Array.from(existingMap.values()).sort(
            (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
          );

          return merged.slice(0, 80);
        });

        setLastScannedTime(new Date().toLocaleTimeString());
      }
    } catch (err) {
      console.error("Failed to load X feed:", err);
    } finally {
      setIsInitialLoading(false);
      setIsScanning(false);
    }
  }, []);

  const [isSseConnected, setIsSseConnected] = useState(false);

  // 1. Real-time Webhook Stream (Server-Sent Events)
  useEffect(() => {
    let es: EventSource | null = null;
    const timer = setTimeout(() => {
      try {
        es = new EventSource("/api/stream");

        es.onopen = () => {
          setIsSseConnected(true);
        };

        es.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);
            if (data.type === "tweet" && data.tweet) {
              const incomingTweet: ParsedTweet = data.tweet;

              setNewTweetIds((old) => {
                const updated = new Set(old);
                updated.add(incomingTweet.id);
                return updated;
              });

              setTweets((prev) => {
                const existingMap = new Map(prev.map((t) => [t.id, t]));
                existingMap.set(incomingTweet.id, incomingTweet);
                return Array.from(existingMap.values())
                  .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
                  .slice(0, 80);
              });

              setLastScannedTime(new Date().toLocaleTimeString());
            } else if (data.type === "history" && Array.isArray(data.tweets) && data.tweets.length > 0) {
              setTweets((prev) => {
                if (prev.length === 0) return data.tweets;
                const existingMap = new Map(prev.map((t) => [t.id, t]));
                data.tweets.forEach((t: ParsedTweet) => existingMap.set(t.id, t));
                return Array.from(existingMap.values())
                  .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
                  .slice(0, 80);
              });
              setIsInitialLoading(false);
            }
          } catch (e) {
            console.error("Error parsing SSE event:", e);
          }
        };

        es.onerror = () => {
          setIsSseConnected(false);
        };
      } catch (e) {
        console.warn("SSE connection error:", e);
      }
    }, 200);

    return () => {
      clearTimeout(timer);
      if (es) es.close();
    };
  }, []);

  // 2. Initial fetch & background sync
  useEffect(() => {
    fetchFeed();
  }, [fetchFeed]);

  useEffect(() => {
    const timer = setInterval(() => {
      fetchFeed();
    }, 30000);

    return () => clearInterval(timer);
  }, [fetchFeed]);

  const formatTimeAgo = (dateString: string) => {
    try {
      const diff = Math.floor((Date.now() - new Date(dateString).getTime()) / 1000);
      if (diff < 30) return "just now";
      if (diff < 60) return `${diff}s ago`;
      if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
      if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
      return `${Math.floor(diff / 86400)}d ago`;
    } catch {
      return "recently";
    }
  };

  const formatExactTime = (dateString: string) => {
    try {
      const d = new Date(dateString);
      return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
    } catch {
      return "";
    }
  };

  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState("");

  const handleCopyTweet = (tweet: ParsedTweet) => {
    navigator.clipboard.writeText(`${tweet.tweetUrl}\n\n${tweet.text}`);
    setCopiedId(tweet.id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const filteredTweets = tweets.filter((t) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      t.author.username.toLowerCase().includes(q) ||
      t.author.name.toLowerCase().includes(q) ||
      t.text.toLowerCase().includes(q) ||
      (t.suggestedToken?.symbol && t.suggestedToken.symbol.toLowerCase().includes(q))
    );
  });

  return (
    <div className="space-y-6 pb-16 max-w-5xl mx-auto">
      {/* Header Banner in Emerald Sketch Style */}
      <div className="sketch-card p-5 sm:p-6 bg-[#092214] border-2 border-emerald-500 relative">
        <div className="hidden sm:block absolute -top-3 left-12 w-32 h-6 bg-emerald-400/35 border border-dashed border-emerald-400 -rotate-2 pointer-events-none"></div>

        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-start sm:items-center space-x-4">
            <div className="w-12 h-12 rounded-sketch border-2 border-emerald-400 bg-[#0c2e1b] shadow-sketch p-1 shrink-0 flex items-center justify-center text-emerald-300">
              <Radar className="w-7 h-7 text-emerald-400" />
            </div>
            <div>
              <div className="flex items-center space-x-3">
                <h1 className="text-2xl sm:text-3xl font-kalam font-bold text-white tracking-wide flex items-center space-x-2">
                  <span>X Narrative Radar</span>
                  <span className="text-lg">⚡</span>
                </h1>
                <span className="flex items-center space-x-1.5 px-2.5 py-0.5 sketch-badge bg-[#0c2e1b] text-emerald-300 font-hand font-bold text-xs border border-emerald-500/50">
                  <span className={`w-2 h-2 rounded-full ${isSseConnected ? "bg-emerald-400 animate-ping" : "bg-emerald-400"}`}></span>
                  <span>{isSseConnected ? "🔴 Live Stream Active" : "Auto-Refresh Active"}</span>
                </span>
              </div>
              <p className="text-xs sm:text-sm font-hand text-emerald-200/90 mt-0.5">
                Monitoring 1,000+ accounts in real-time • 1-Click Launch meme tokens on Pons curves
              </p>
            </div>
          </div>

          <div className="flex items-center space-x-3 self-end sm:self-center">
            <div className="px-3 py-1 sketch-surface text-xs font-mono text-emerald-300 flex items-center space-x-2 border border-emerald-700/50">
              <span className="w-2 h-2 rounded-full bg-emerald-400"></span>
              <span>{isSseConnected ? "Live Feed Synced" : `Last update: ${lastScannedTime}`}</span>
            </div>
          </div>
        </div>
      </div>

      {/* Main Stream Container - Bounded with Internal Scrollbar */}
      <div className="sketch-card p-4 sm:p-6 bg-[#06180e] border-2 border-emerald-600 shadow-2xl space-y-4">
        {/* Stream Top Control Bar */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-3 border-b border-emerald-900/70 text-xs font-mono">
          <div className="flex items-center space-x-3">
            <div className="flex items-center space-x-1.5 text-white font-bold">
              <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
              <span>LIVE FEED FEED STREAM</span>
            </div>
            <span className="px-2.5 py-0.5 rounded-full bg-[#0a2315] border border-emerald-600/60 text-emerald-300 text-xs font-mono">
              {filteredTweets.length} posts
            </span>
          </div>

          <div className="flex items-center space-x-2">
            <input
              type="text"
              placeholder="Search author, keyword, or $ticker..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="px-3.5 py-1.5 rounded-lg bg-[#0a2013] border border-emerald-700/70 text-white placeholder-emerald-600/80 text-xs focus:outline-none focus:border-emerald-400 font-hand w-full sm:w-72"
            />
            {searchQuery && (
              <button
                onClick={() => setSearchQuery("")}
                className="text-xs text-emerald-400 hover:text-white px-2 py-1"
              >
                Clear
              </button>
            )}
          </div>
        </div>

        {/* Scrollable Feed Box (Bounded Height - NEVER stretches page infinitely) */}
        <div className="max-h-[640px] overflow-y-auto pr-1.5 space-y-3.5 custom-scrollbar">
          {isInitialLoading && tweets.length === 0 ? (
            <div className="p-16 text-center space-y-3">
              <div className="w-8 h-8 border-2 border-emerald-400 border-t-transparent rounded-full animate-spin mx-auto"></div>
              <p className="font-hand text-base text-emerald-200">
                Connecting to live stream...
              </p>
            </div>
          ) : filteredTweets.length === 0 ? (
            <div className="p-12 text-center space-y-2 bg-[#081b10] rounded-xl border border-dashed border-emerald-900">
              <AlertCircle className="w-7 h-7 text-emerald-400 mx-auto opacity-70" />
              <p className="font-hand text-base text-emerald-200">
                {searchQuery ? "No posts match your search query." : "No posts captured in stream yet."}
              </p>
            </div>
          ) : (
            filteredTweets.map((tweet) => {
              const hasMedia = tweet.media && tweet.media.length > 0;
              const primaryMedia = hasMedia ? tweet.media![0].url : null;
              const isNew = newTweetIds.has(tweet.id);

              // Detect replies or quote
              const replyMatch = tweet.text.match(/^@([a-zA-Z0-9_]+)/);
              const replyHandle = replyMatch ? replyMatch[1] : null;

              // Check if retweet
              const isRetweet = tweet.text.startsWith("RT @");

              return (
                <div
                  key={tweet.id}
                  className={`bg-[#0a1610] border border-emerald-900/80 hover:border-emerald-500/70 rounded-xl p-4 transition-all space-y-3 relative group ${
                    isNew ? "border-emerald-400/90 shadow-[0_0_12px_rgba(52,211,153,0.25)]" : ""
                  }`}
                >
                  {/* New post tag */}
                  {isNew && (
                    <div className="absolute -top-2.5 right-4 px-2 py-0.5 rounded-full bg-emerald-400 text-slate-950 font-mono font-bold text-[10px] shadow-sm flex items-center space-x-1">
                      <Sparkles className="w-2.5 h-2.5 text-slate-950" />
                      <span>NEW</span>
                    </div>
                  )}

                  {/* Top Author Row */}
                  <div className="flex items-start justify-between gap-3">
                    <div className="flex items-start space-x-3">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={tweet.author.profileImageUrl}
                        alt={tweet.author.name}
                        className="w-10 h-10 rounded-full border border-emerald-500/50 object-cover shrink-0 mt-0.5"
                        onError={(e) => {
                          (e.target as HTMLImageElement).src = "/vana-logo.png";
                        }}
                      />
                      <div>
                        <div className="flex items-center space-x-1.5 flex-wrap">
                          <span className="font-bold text-white text-sm hover:underline cursor-pointer">
                            {tweet.author.name}
                          </span>
                          {tweet.author.verified && (
                            <CheckCircle2 className="w-3.5 h-3.5 text-sky-400 fill-sky-400/20 shrink-0" />
                          )}
                          <span className="text-[11px] font-mono text-slate-400">
                            {formatExactTime(tweet.createdAt)}
                          </span>
                          <span className="text-[11px] font-mono text-emerald-500/70">
                            ({formatTimeAgo(tweet.createdAt)})
                          </span>
                        </div>
                        <div className="flex items-center space-x-2 text-xs font-mono text-slate-400 mt-0.5">
                          <span>@{tweet.author.username}</span>
                          {replyHandle && (
                            <span className="text-emerald-400/80">
                              ↳ replied to @{replyHandle}
                            </span>
                          )}
                        </div>
                      </div>
                    </div>

                    {/* Action buttons (Copy link / Open on X) */}
                    <div className="flex items-center space-x-1 shrink-0">
                      <button
                        onClick={() => handleCopyTweet(tweet)}
                        className="p-1.5 rounded-md hover:bg-emerald-950/80 text-slate-400 hover:text-emerald-300 transition-colors"
                        title="Copy tweet link"
                      >
                        {copiedId === tweet.id ? (
                          <span className="text-[10px] text-emerald-400 font-mono">Copied!</span>
                        ) : (
                          <ExternalLink className="w-3.5 h-3.5" />
                        )}
                      </button>
                      <a
                        href={tweet.tweetUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="p-1.5 rounded-md hover:bg-emerald-950/80 text-slate-400 hover:text-emerald-300 transition-colors"
                        title="Open on X.com"
                      >
                        <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    </div>
                  </div>

                  {/* Tweet Body Content */}
                  <p className="text-sm text-slate-200 leading-relaxed whitespace-pre-line font-sans pl-1">
                    {tweet.text}
                  </p>

                  {/* Attached Media / Image Preview */}
                  {primaryMedia && (
                    <div className="rounded-lg overflow-hidden border border-emerald-900/60 max-h-72 bg-black/50 flex items-center justify-center">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={primaryMedia}
                        alt="Tweet media"
                        className="w-full h-full object-cover max-h-72"
                        onError={(e) => {
                          (e.target as HTMLElement).style.display = "none";
                        }}
                      />
                    </div>
                  )}

                  {/* Bottom Action & Launch Bar */}
                  <div className="pt-2.5 border-t border-emerald-950 flex flex-wrap items-center justify-between gap-2.5">
                    {/* Metrics */}
                    <div className="flex items-center space-x-4 text-xs font-mono text-slate-400">
                      <span className="flex items-center space-x-1 hover:text-rose-400 cursor-pointer">
                        <Heart className="w-3.5 h-3.5 text-rose-400/80" />
                        <span>{tweet.metrics?.likes.toLocaleString() ?? 0}</span>
                      </span>
                      <span className="flex items-center space-x-1 hover:text-emerald-400 cursor-pointer">
                        <Repeat className="w-3.5 h-3.5 text-emerald-400/80" />
                        <span>{tweet.metrics?.retweets.toLocaleString() ?? 0}</span>
                      </span>
                      <span className="flex items-center space-x-1 hover:text-sky-400 cursor-pointer">
                        <MessageCircle className="w-3.5 h-3.5 text-sky-400/80" />
                        <span>{tweet.metrics?.replies.toLocaleString() ?? 0}</span>
                      </span>

                      {/* Suggested token pill */}
                      <div className="flex items-center space-x-1.5 pl-2 border-l border-emerald-900/60">
                        <span className="text-[11px] text-slate-400">Ticker:</span>
                        <span className="px-2 py-0.5 rounded bg-emerald-950 border border-emerald-600/70 text-emerald-300 font-bold font-mono text-xs">
                          ${tweet.suggestedToken?.symbol || "TOKEN"}
                        </span>
                      </div>
                    </div>

                    {/* Instant Launch Button */}
                    <button
                      onClick={() => setSelectedTweetForLaunch(tweet)}
                      className="px-3.5 py-1.5 rounded-lg bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold font-mono text-xs flex items-center space-x-1.5 shadow-md hover:scale-[1.02] active:scale-[0.98] transition-all"
                    >
                      <Rocket className="w-3.5 h-3.5" />
                      <span>Launch Token</span>
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </div>

        {/* Bottom Stream Boundary ("Batas Bawah") */}
        <div className="pt-3 border-t border-emerald-900/70 flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs font-mono text-emerald-400/80">
          <div className="flex items-center space-x-2">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
            <span>Stream Boundary • Scroll inside box for full history</span>
          </div>
          <div className="text-slate-400">
            Showing {filteredTweets.length} of {tweets.length} total posts
          </div>
        </div>
      </div>

      {/* Fast Launch Modal */}
      <FastLaunchModal
        tweet={selectedTweetForLaunch}
        isOpen={Boolean(selectedTweetForLaunch)}
        onClose={() => setSelectedTweetForLaunch(null)}
      />
    </div>
  );
}
