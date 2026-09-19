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

    return () => {
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
    }, 15000);

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

  return (
    <div className="space-y-8 pb-16">
      {/* Header Banner in Emerald Sketch Style */}
      <div className="sketch-card p-6 sm:p-8 bg-[#092214] border-2 border-emerald-500 relative">
        <div className="hidden sm:block absolute -top-3 left-12 w-32 h-6 bg-emerald-400/35 border border-dashed border-emerald-400 -rotate-2 pointer-events-none"></div>

        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-start sm:items-center space-x-4">
            <div className="w-14 h-14 rounded-sketch border-2 border-emerald-400 bg-[#0c2e1b] shadow-sketch p-1 shrink-0 flex items-center justify-center text-emerald-300">
              <Radar className={`w-8 h-8 text-emerald-400 ${isScanning ? "animate-spin" : "animate-pulse"}`} />
            </div>
            <div>
              <div className="flex items-center space-x-3">
                <h1 className="text-3xl sm:text-4xl font-kalam font-bold text-white tracking-wide flex items-center space-x-2">
                  <span>X Narrative Radar</span>
                  <span className="text-xl">⚡</span>
                </h1>
                <span className="flex items-center space-x-1.5 px-3 py-0.5 sketch-badge bg-[#0c2e1b] text-emerald-300 font-hand font-bold text-xs border border-emerald-500/50">
                  <span className={`w-2 h-2 rounded-full ${isSseConnected ? "bg-emerald-400 animate-ping" : "bg-emerald-400"}`}></span>
                  <span>{isSseConnected ? "🔴 Live Stream Active" : "Auto-Refresh Active"}</span>
                </span>
              </div>
              <p className="text-sm font-hand text-emerald-200/90 mt-1">
                Live breaking posts from 1,000+ monitored accounts • Launch meme tokens instantly on Pons bonding curves
              </p>
            </div>
          </div>

          {/* Live Scanner Activity Indicator */}
          <div className="flex items-center space-x-3 self-end sm:self-center">
            <div className="px-3.5 py-1.5 sketch-surface text-xs font-mono text-emerald-300 flex items-center space-x-2 border border-emerald-700/50">
              <span className={`w-2 h-2 rounded-full ${isScanning ? "bg-amber-400 animate-ping" : "bg-emerald-400 animate-pulse"}`}></span>
              <span>{isScanning ? "Scanning X..." : `Last scan: ${lastScannedTime}`}</span>
            </div>
          </div>
        </div>

        {apiNotice && (
          <div className="mt-4 p-3 rounded-sketch bg-amber-950/60 border border-amber-500/50 text-amber-200 text-xs font-hand flex items-center justify-between gap-3">
            <div className="flex items-center space-x-2">
              <AlertCircle className="w-4 h-4 text-amber-400 shrink-0" />
              <span>{apiNotice}</span>
            </div>
            <button
              onClick={() => setApiNotice(null)}
              className="text-amber-400 hover:text-white text-xs underline shrink-0 font-mono"
            >
              Dismiss
            </button>
          </div>
        )}
      </div>

      {/* Tweets Grid / Feed */}
      {isInitialLoading && tweets.length === 0 ? (
        <div className="sketch-card p-16 text-center space-y-4 bg-[#092214]">
          <RefreshCw className="w-8 h-8 text-emerald-400 animate-spin mx-auto" />
          <p className="font-hand text-lg text-emerald-200">
            Scanning 1,000+ accounts for newest narratives...
          </p>
        </div>
      ) : tweets.length === 0 ? (
        <div className="sketch-card p-12 text-center space-y-3 bg-[#092214]">
          <AlertCircle className="w-8 h-8 text-emerald-400 mx-auto opacity-70" />
          <p className="font-hand text-lg text-emerald-100">No tweets found in current stream.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {tweets.map((tweet) => {
            const hasMedia = tweet.media && tweet.media.length > 0;
            const primaryMedia = hasMedia ? tweet.media![0].url : null;
            const isNew = newTweetIds.has(tweet.id);

            return (
              <div
                key={tweet.id}
                className={`sketch-card p-5 bg-[#081e12] flex flex-col justify-between space-y-4 hover:border-emerald-400 transition-all group relative ${
                  isNew ? "border-emerald-400 shadow-[0_0_15px_rgba(52,211,153,0.3)] animate-fade-in" : ""
                }`}
              >
                {/* New post highlight badge */}
                {isNew && (
                  <div className="absolute -top-3 right-6 px-2.5 py-0.5 rounded-full bg-emerald-400 text-slate-950 font-hand font-bold text-xs shadow-sm flex items-center space-x-1 animate-bounce">
                    <Sparkles className="w-3 h-3 text-slate-950" />
                    <span>NEW POST</span>
                  </div>
                )}

                <div className="space-y-3">
                  {/* Tweet Header */}
                  <div className="flex items-start justify-between">
                    <div className="flex items-center space-x-3">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={tweet.author.profileImageUrl}
                        alt={tweet.author.name}
                        className="w-11 h-11 rounded-full border-2 border-emerald-400 object-cover shadow-sketch-sm"
                        onError={(e) => {
                          (e.target as HTMLImageElement).src = "/vana-logo.png";
                        }}
                      />
                      <div>
                        <div className="flex items-center space-x-1.5">
                          <span className="font-hand font-bold text-white text-base leading-tight">
                            {tweet.author.name}
                          </span>
                          {tweet.author.verified && (
                            <CheckCircle2 className="w-3.5 h-3.5 text-sky-400 fill-sky-400/20" />
                          )}
                        </div>
                        <div className="flex items-center space-x-2 text-xs font-mono text-emerald-400">
                          <span>@{tweet.author.username}</span>
                          <span>•</span>
                          <span className="text-slate-400">{formatTimeAgo(tweet.createdAt)}</span>
                        </div>
                      </div>
                    </div>

                    <a
                      href={tweet.tweetUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="p-1.5 sketch-btn-secondary text-slate-400 hover:text-emerald-300"
                      title="View original on X"
                    >
                      <ExternalLink className="w-4 h-4" />
                    </a>
                  </div>

                  {/* Tweet Content Text */}
                  <p className="text-sm font-hand text-slate-100 leading-relaxed whitespace-pre-line">
                    {tweet.text}
                  </p>

                  {/* Attached Media / Image */}
                  {primaryMedia && (
                    <div className="relative rounded-sketch overflow-hidden border border-emerald-700/60 max-h-56 bg-black/40 flex items-center justify-center">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={primaryMedia}
                        alt="Tweet media"
                        className="w-full h-full object-cover max-h-56 group-hover:scale-105 transition-transform duration-300"
                        onError={(e) => {
                          (e.target as HTMLElement).style.display = "none";
                        }}
                      />
                    </div>
                  )}

                  {/* Engagement Metrics */}
                  <div className="flex items-center space-x-4 text-xs font-mono text-slate-400 pt-1">
                    <span className="flex items-center space-x-1">
                      <Heart className="w-3.5 h-3.5 text-rose-400" />
                      <span>{tweet.metrics?.likes.toLocaleString() ?? 0}</span>
                    </span>
                    <span className="flex items-center space-x-1">
                      <Repeat className="w-3.5 h-3.5 text-emerald-400" />
                      <span>{tweet.metrics?.retweets.toLocaleString() ?? 0}</span>
                    </span>
                    <span className="flex items-center space-x-1">
                      <MessageCircle className="w-3.5 h-3.5 text-sky-400" />
                      <span>{tweet.metrics?.replies.toLocaleString() ?? 0}</span>
                    </span>
                  </div>
                </div>

                {/* Fast Launch Action Bar */}
                <div className="pt-3 border-t border-dashed border-emerald-800/80 flex items-center justify-between gap-3">
                  <div className="flex items-center space-x-1.5 text-xs font-hand">
                    <span className="text-slate-400">Suggested:</span>
                    <span className="px-2 py-0.5 rounded bg-emerald-950 border border-emerald-500/60 text-emerald-300 font-bold font-mono">
                      ${tweet.suggestedToken?.symbol || "TOKEN"}
                    </span>
                  </div>

                  <button
                    onClick={() => setSelectedTweetForLaunch(tweet)}
                    className="px-4 py-2 sketch-btn-primary text-slate-950 font-hand font-bold text-sm flex items-center space-x-1.5 shadow-sketch hover:scale-105 transition-transform"
                  >
                    <Rocket className="w-4 h-4" />
                    <span>Launch Token</span>
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Fast Launch Modal */}
      <FastLaunchModal
        tweet={selectedTweetForLaunch}
        isOpen={Boolean(selectedTweetForLaunch)}
        onClose={() => setSelectedTweetForLaunch(null)}
      />
    </div>
  );
}
