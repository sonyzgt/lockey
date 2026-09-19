import { NextRequest } from "next/server";
import { tweetEmitter, getStoredTweets } from "@/lib/tweetDb";
import { ParsedTweet } from "@/app/api/x-feed/route";

export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    start(controller) {
      // 1. Send initial connected event
      const initialPayload = JSON.stringify({
        type: "connected",
        message: "Live stream connected to Vana Radar",
        timestamp: new Date().toISOString(),
      });
      controller.enqueue(encoder.encode(`data: ${initialPayload}\n\n`));

      // 2. Send recent stored tweets immediately
      const recent = getStoredTweets(25);
      if (recent.length > 0) {
        const historyPayload = JSON.stringify({
          type: "history",
          tweets: recent,
        });
        controller.enqueue(encoder.encode(`data: ${historyPayload}\n\n`));
      }

      // 3. Listener for new real-time tweets emitted by Webhook
      const onNewTweet = (tweet: ParsedTweet) => {
        try {
          const tweetPayload = JSON.stringify({
            type: "tweet",
            tweet,
          });
          controller.enqueue(encoder.encode(`data: ${tweetPayload}\n\n`));
        } catch (e) {
          console.error("Error pushing tweet to stream:", e);
        }
      };

      tweetEmitter.on("new_tweet", onNewTweet);

      // 4. Heartbeat ping every 20 seconds to keep connection alive through Nginx proxy
      const pingInterval = setInterval(() => {
        try {
          controller.enqueue(encoder.encode(": ping\n\n"));
        } catch {
          clearInterval(pingInterval);
        }
      }, 20000);

      // Clean up on disconnect
      req.signal.addEventListener("abort", () => {
        clearInterval(pingInterval);
        tweetEmitter.off("new_tweet", onNewTweet);
        try {
          controller.close();
        } catch {
          // stream already closed
        }
      });
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no", // Tells Nginx not to buffer SSE
    },
  });
}
