import { NextRequest, NextResponse } from "next/server";
import { saveBatchStoredTweets, saveStoredTweet } from "@/lib/tweetDb";
import { ParsedTweet } from "@/app/api/x-feed/route";

export const dynamic = "force-dynamic";

function extractSuggestedToken(text: string): { name: string; symbol: string } {
  const cashtagMatch = text.match(/\$([A-Za-z0-9_]{2,8})\b/);
  if (cashtagMatch) {
    const symbol = cashtagMatch[1].toUpperCase();
    return {
      name: symbol.charAt(0) + symbol.slice(1).toLowerCase(),
      symbol,
    };
  }

  const clean = text
    .replace(/https?:\/\/\S+/g, "")
    .replace(/@\w+/g, "")
    .replace(/[^a-zA-Z0-9\s]/g, "")
    .trim();

  const words = clean.split(/\s+/).filter((w) => w.length > 2);
  if (words.length === 0) {
    return { name: "Lockey Narrative", symbol: "LOCK" };
  }

  const name = words.slice(0, 2).join(" ");
  let symbol = "";
  if (words.length >= 2) {
    symbol = (words[0].slice(0, 2) + words[1].slice(0, 3)).toUpperCase();
  } else {
    symbol = words[0].slice(0, 5).toUpperCase();
  }

  return {
    name: name.slice(0, 20),
    symbol: symbol.slice(0, 8),
  };
}

function normalizeRawTweet(raw: any): ParsedTweet | null {
  if (!raw) return null;

  const id = raw.id || raw.tweet_id || raw.id_str || String(Date.now());
  const text = raw.text || raw.full_text || raw.content || "";
  if (!text) return null;

  const createdAt = raw.created_at ? new Date(raw.created_at).toISOString() : new Date().toISOString();

  // Author extraction (supports both TwitterAPI.io user object and standard formats)
  const user = raw.user || raw.author || {};
  const username = (user.screen_name || user.username || raw.username || "crypto_insider").replace("@", "");
  const name = user.name || raw.author_name || username;
  const avatar = user.profile_image_url_https || user.profile_image_url || "/lockey-logo.svg";
  const verified = Boolean(user.verified || user.is_blue_verified);

  // Media extraction
  const mediaList: { url: string; type: string }[] = [];
  const rawMedia =
    raw.extended_entities?.media ||
    raw.entities?.media ||
    raw.media ||
    [];

  if (Array.isArray(rawMedia)) {
    rawMedia.forEach((m: any) => {
      const url = m.media_url_https || m.media_url || m.url || m.preview_image_url;
      if (url) {
        mediaList.push({
          url,
          type: m.type || "photo",
        });
      }
    });
  }

  const likes = raw.favorite_count || raw.like_count || raw.metrics?.likes || 0;
  const retweets = raw.retweet_count || raw.metrics?.retweets || 0;
  const replies = raw.reply_count || raw.metrics?.replies || 0;

  const suggested = extractSuggestedToken(text);

  return {
    id: String(id),
    text,
    createdAt,
    tweetUrl: `https://x.com/${username}/status/${id}`,
    author: {
      id: String(user.id || username),
      name,
      username,
      profileImageUrl: avatar,
      verified,
    },
    media: mediaList,
    metrics: {
      likes,
      retweets,
      replies,
    },
    suggestedToken: suggested,
  };
}

export async function POST(req: NextRequest) {
  try {
    // 1. Secret verification (optional security check)
    const expectedSecret = process.env.TWITTERAPI_WEBHOOK_SECRET;
    if (expectedSecret) {
      const urlSecret = req.nextUrl.searchParams.get("secret");
      const headerSecret = req.headers.get("x-webhook-secret");
      if (urlSecret !== expectedSecret && headerSecret !== expectedSecret) {
        return NextResponse.json({ error: "Unauthorized: Invalid secret" }, { status: 401 });
      }
    }

    const payload = await req.json().catch(() => ({}));

    // Handle different TwitterAPI.io payload wrappers
    let rawItems: any[] = [];
    if (Array.isArray(payload)) {
      rawItems = payload;
    } else if (Array.isArray(payload.data)) {
      rawItems = payload.data;
    } else if (Array.isArray(payload.tweets)) {
      rawItems = payload.tweets;
    } else if (payload.tweet) {
      rawItems = [payload.tweet];
    } else if (payload.text || payload.id) {
      rawItems = [payload];
    }

    const normalizedTweets: ParsedTweet[] = [];
    rawItems.forEach((item) => {
      const parsed = normalizeRawTweet(item);
      if (parsed) normalizedTweets.push(parsed);
    });

    if (normalizedTweets.length === 0) {
      return NextResponse.json({
        success: true,
        received: 0,
        message: "No parseable tweets found in payload",
      });
    }

    const savedCount = saveBatchStoredTweets(normalizedTweets);

    return NextResponse.json({
      success: true,
      processed: normalizedTweets.length,
      saved: savedCount,
      timestamp: new Date().toISOString(),
    });
  } catch (err: unknown) {
    console.error("Webhook processing error:", err);
    const message = err instanceof Error ? err.message : "Server error processing webhook";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET(req: NextRequest) {
  return NextResponse.json({
    status: "active",
    service: "Lockey TwitterAPI.io Webhook Endpoint",
    url: req.nextUrl.href,
    message: "Send POST requests with tweet payloads from TwitterAPI.io here.",
  });
}
