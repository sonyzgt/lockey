import fs from "fs";
import path from "path";
import { EventEmitter } from "events";
import { ParsedTweet } from "@/app/api/x-feed/route";

// Global singleton EventEmitter to broadcast real-time events across Next.js routes
declare global {
  // eslint-disable-next-line no-var
  var __tweetEmitter: EventEmitter | undefined;
}

if (!global.__tweetEmitter) {
  global.__tweetEmitter = new EventEmitter();
  global.__tweetEmitter.setMaxListeners(500);
}

export const tweetEmitter = global.__tweetEmitter;

const DB_DIR = path.join(process.cwd(), "data");
const DB_FILE = path.join(DB_DIR, "tweets.json");

function ensureDbExists() {
  try {
    if (!fs.existsSync(DB_DIR)) {
      fs.mkdirSync(DB_DIR, { recursive: true });
    }
    if (!fs.existsSync(DB_FILE)) {
      fs.writeFileSync(DB_FILE, JSON.stringify([], null, 2), "utf-8");
    }
  } catch (err) {
    console.error("Error creating tweets database directory:", err);
  }
}

export function getStoredTweets(limit = 100): ParsedTweet[] {
  try {
    ensureDbExists();
    if (!fs.existsSync(DB_FILE)) return [];
    const content = fs.readFileSync(DB_FILE, "utf-8");
    const list: ParsedTweet[] = JSON.parse(content || "[]");
    return Array.isArray(list) ? list.slice(0, limit) : [];
  } catch (err) {
    console.error("Error reading stored tweets:", err);
    return [];
  }
}

export function saveStoredTweet(tweet: ParsedTweet): boolean {
  try {
    ensureDbExists();
    const current = getStoredTweets(1000);
    
    // Deduplicate
    const exists = current.some((t) => t.id === tweet.id);
    if (exists) return false;

    // Prepend new tweet
    const updated = [tweet, ...current].slice(0, 1000);
    fs.writeFileSync(DB_FILE, JSON.stringify(updated, null, 2), "utf-8");

    // Broadcast to real-time subscribers
    tweetEmitter.emit("new_tweet", tweet);
    return true;
  } catch (err) {
    console.error("Error saving stored tweet:", err);
    return false;
  }
}

export function saveBatchStoredTweets(tweets: ParsedTweet[]): number {
  try {
    ensureDbExists();
    const current = getStoredTweets(1000);
    const existingIds = new Set(current.map((t) => t.id));
    
    const newTweets: ParsedTweet[] = [];
    tweets.forEach((t) => {
      if (!existingIds.has(t.id)) {
        newTweets.push(t);
        existingIds.add(t.id);
      }
    });

    if (newTweets.length === 0) return 0;

    const updated = [...newTweets, ...current].slice(0, 1000);
    fs.writeFileSync(DB_FILE, JSON.stringify(updated, null, 2), "utf-8");

    // Broadcast each new tweet to subscribers
    newTweets.forEach((t) => {
      tweetEmitter.emit("new_tweet", t);
    });

    return newTweets.length;
  } catch (err) {
    console.error("Error batch saving stored tweets:", err);
    return 0;
  }
}
