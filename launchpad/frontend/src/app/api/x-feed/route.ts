import { NextRequest, NextResponse } from "next/server";

export interface ParsedTweet {
  id: string;
  text: string;
  createdAt: string;
  tweetUrl: string;
  author: {
    id: string;
    name: string;
    username: string;
    profileImageUrl: string;
    verified: boolean;
  };
  media?: {
    url: string;
    type: string;
    width?: number;
    height?: number;
  }[];
  metrics?: {
    likes: number;
    retweets: number;
    replies: number;
  };
  suggestedToken?: {
    name: string;
    symbol: string;
  };
}

// Realistic simulation feed for when X API key is not yet set up or rate limited
const MOCK_TWEETS: ParsedTweet[] = [
  {
    id: "mock-1",
    text: "Mars is the destination. The new sentient AI rover will roam Olympus Mons soon. Next frontier begins.",
    createdAt: new Date(Date.now() - 1000 * 60 * 3).toISOString(), // 3 mins ago
    tweetUrl: "https://x.com/elonmusk",
    author: {
      id: "44196397",
      name: "Elon Musk",
      username: "elonmusk",
      profileImageUrl: "https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=200&auto=format&fit=crop&q=80",
      verified: true,
    },
    media: [
      {
        url: "https://images.unsplash.com/photo-1614728894747-a83421e2b9c9?w=800&auto=format&fit=crop&q=80",
        type: "photo",
      },
    ],
    metrics: {
      likes: 48200,
      retweets: 9240,
      replies: 5120,
    },
    suggestedToken: {
      name: "Olympus Rover",
      symbol: "OLYMPUS",
    },
  },
  {
    id: "mock-2",
    text: "Decentralized consensus is about mathematically verifiable trust, not blind faith. Bonding curves are redefining tokenomics.",
    createdAt: new Date(Date.now() - 1000 * 60 * 14).toISOString(), // 14 mins ago
    tweetUrl: "https://x.com/VitalikButerin",
    author: {
      id: "295218901",
      name: "vitalik.eth",
      username: "VitalikButerin",
      profileImageUrl: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&auto=format&fit=crop&q=80",
      verified: true,
    },
    media: [
      {
        url: "https://images.unsplash.com/photo-1639762681485-074b7f938ba0?w=800&auto=format&fit=crop&q=80",
        type: "photo",
      },
    ],
    metrics: {
      likes: 21500,
      retweets: 3890,
      replies: 1420,
    },
    suggestedToken: {
      name: "Verifiable Trust",
      symbol: "TRUST",
    },
  },
  {
    id: "mock-3",
    text: "Building never stops. When market is loud, keep focus on liquidity infrastructure and transparent community curves.",
    createdAt: new Date(Date.now() - 1000 * 60 * 29).toISOString(), // 29 mins ago
    tweetUrl: "https://x.com/cz_binance",
    author: {
      id: "902926941413453824",
      name: "CZ 🔶 BNB",
      username: "cz_binance",
      profileImageUrl: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&auto=format&fit=crop&q=80",
      verified: true,
    },
    media: [
      {
        url: "https://images.unsplash.com/photo-1622979135225-d2ba269bc1df?w=800&auto=format&fit=crop&q=80",
        type: "photo",
      },
    ],
    metrics: {
      likes: 31200,
      retweets: 6140,
      replies: 2310,
    },
    suggestedToken: {
      name: "Keep Building",
      symbol: "BUILD",
    },
  },
  {
    id: "mock-4",
    text: "The green frog never sleeps. Digital culture on-chain is outperforming legacy media.",
    createdAt: new Date(Date.now() - 1000 * 60 * 45).toISOString(),
    tweetUrl: "https://x.com/WhaleAlert",
    author: {
      id: "1039833297746956288",
      name: "Whale Alert",
      username: "whale_alert",
      profileImageUrl: "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=200&auto=format&fit=crop&q=80",
      verified: true,
    },
    media: [
      {
        url: "https://images.unsplash.com/photo-1579783902614-a3fb3927b675?w=800&auto=format&fit=crop&q=80",
        type: "photo",
      },
    ],
    metrics: {
      likes: 12400,
      retweets: 2410,
      replies: 890,
    },
    suggestedToken: {
      name: "Green Culture",
      symbol: "CULTURE",
    },
  },
];

function extractSuggestedToken(text: string): { name: string; symbol: string } {
  // Check for cashtags like $PEPE or $DOGE
  const cashtagMatch = text.match(/\$([A-Za-z0-9_]{2,8})\b/);
  if (cashtagMatch) {
    const symbol = cashtagMatch[1].toUpperCase();
    return {
      name: symbol.charAt(0) + symbol.slice(1).toLowerCase(),
      symbol,
    };
  }

  // Remove URLs, mentions, emojis, special characters
  const clean = text
    .replace(/https?:\/\/\S+/g, "")
    .replace(/@\w+/g, "")
    .replace(/[^a-zA-Z0-9\s]/g, "")
    .trim();

  const words = clean.split(/\s+/).filter((w) => w.length > 2);
  if (words.length === 0) {
    return { name: "Vana Narrative", symbol: "VNARR" };
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

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({}));
    const envAccounts = process.env.X_TARGET_ACCOUNTS
      ? process.env.X_TARGET_ACCOUNTS.split(",")
          .map((s) => s.trim().replace("@", ""))
          .filter(Boolean)
      : null;

    const usernames =
      (body.usernames as string[] | undefined) ||
      (envAccounts && envAccounts.length > 0 ? envAccounts : [
        "elonmusk",
        "VitalikButerin",
        "cz_binance",
        "whale_alert",
      ]);
    const customQuery = (body.query as string | undefined)?.trim();
    const clientBearer = (body.bearerToken as string | undefined)?.trim();

    const bearerToken =
      clientBearer ||
      process.env.X_BEARER_TOKEN ||
      process.env.TWITTER_BEARER_TOKEN;

    // If no token is configured, return the realistic mock stream
    if (!bearerToken) {
      return NextResponse.json({
        success: true,
        isMock: true,
        message: "No X Bearer Token provided. Displaying live demo feed.",
        tweets: MOCK_TWEETS,
      });
    }

    // Build Twitter API v2 Search Query
    let queryParam = "";
    if (customQuery) {
      queryParam = `${customQuery} -is:retweet`;
    } else {
      const fromClauses = usernames
        .map((u) => `from:${u.replace("@", "")}`)
        .join(" OR ");
      queryParam = `(${fromClauses}) -is:retweet`;
    }

    const url = new URL("https://api.twitter.com/2/tweets/search/recent");
    url.searchParams.set("query", queryParam);
    url.searchParams.set("max_results", "20");
    url.searchParams.set(
      "tweet.fields",
      "created_at,public_metrics,entities,attachments,author_id"
    );
    url.searchParams.set(
      "expansions",
      "author_id,attachments.media_keys"
    );
    url.searchParams.set(
      "user.fields",
      "name,username,profile_image_url,verified"
    );
    url.searchParams.set(
      "media.fields",
      "url,preview_image_url,type,width,height"
    );

    const xRes = await fetch(url.toString(), {
      headers: {
        Authorization: `Bearer ${bearerToken}`,
      },
      next: { revalidate: 10 },
    });

    if (!xRes.ok) {
      const errText = await xRes.text();
      console.warn("X API returned non-200, falling back to mock stream:", xRes.status, errText);
      return NextResponse.json({
        success: true,
        isMock: true,
        warning: `X API returned HTTP ${xRes.status}. Using simulation stream.`,
        tweets: MOCK_TWEETS,
      });
    }

    const xData = await xRes.json();
    const rawTweets: any[] = xData.data || [];
    const usersMap = new Map<string, any>();
    (xData.includes?.users || []).forEach((u: any) => usersMap.set(u.id, u));

    const mediaMap = new Map<string, any>();
    (xData.includes?.media || []).forEach((m: any) => mediaMap.set(m.media_key, m));

    const parsedTweets: ParsedTweet[] = rawTweets.map((t: any) => {
      const user = usersMap.get(t.author_id);
      const tweetMediaKeys: string[] = t.attachments?.media_keys || [];
      const mediaList = tweetMediaKeys
        .map((k) => mediaMap.get(k))
        .filter(Boolean)
        .map((m) => ({
          url: m.url || m.preview_image_url || "",
          type: m.type || "photo",
          width: m.width,
          height: m.height,
        }))
        .filter((m) => Boolean(m.url));

      const suggested = extractSuggestedToken(t.text);

      return {
        id: t.id,
        text: t.text,
        createdAt: t.created_at,
        tweetUrl: user?.username ? `https://x.com/${user.username}/status/${t.id}` : `https://x.com/i/web/status/${t.id}`,
        author: {
          id: t.author_id,
          name: user?.name || "Unknown Author",
          username: user?.username || "unknown",
          profileImageUrl: user?.profile_image_url || "/vana-logo.png",
          verified: Boolean(user?.verified),
        },
        media: mediaList,
        metrics: {
          likes: t.public_metrics?.like_count || 0,
          retweets: t.public_metrics?.retweet_count || 0,
          replies: t.public_metrics?.reply_count || 0,
        },
        suggestedToken: suggested,
      };
    });

    return NextResponse.json({
      success: true,
      isMock: false,
      tweets: parsedTweets,
    });
  } catch (error: unknown) {
    console.error("Error in /api/x-feed:", error);
    return NextResponse.json({
      success: true,
      isMock: true,
      error: "Internal server exception. Returned fallback stream.",
      tweets: MOCK_TWEETS,
    });
  }
}

export async function GET(req: NextRequest) {
  return POST(req);
}
