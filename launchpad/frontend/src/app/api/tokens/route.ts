import { NextRequest, NextResponse } from "next/server";
import fs from "fs/promises";
import path from "path";

export interface PlatformTokenRecord {
  token: string;
  curve: string;
  deployer: string;
  name: string;
  symbol: string;
  logo?: string;
  description?: string;
  txHash?: string;
  blockNumber?: string;
  createdAt: string;
}

const DATA_FILE_PATH = path.join(process.cwd(), "src", "data", "platform-tokens.json");

async function readTokens(): Promise<PlatformTokenRecord[]> {
  try {
    const data = await fs.readFile(DATA_FILE_PATH, "utf-8");
    const parsed = JSON.parse(data);
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    console.warn("Could not read platform-tokens.json, returning empty list:", err);
    return [];
  }
}

async function saveTokens(tokens: PlatformTokenRecord[]): Promise<void> {
  const dir = path.dirname(DATA_FILE_PATH);
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(DATA_FILE_PATH, JSON.stringify(tokens, null, 2), "utf-8");
}

export async function GET() {
  try {
    const tokens = await readTokens();
    return NextResponse.json({ success: true, tokens });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Failed to fetch platform tokens";
    return NextResponse.json(
      { success: false, error: msg },
      { status: 500 }
    );
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      token,
      curve,
      deployer,
      name,
      symbol,
      logo,
      description,
      txHash,
      blockNumber,
    } = body;

    if (!token || typeof token !== "string" || !token.startsWith("0x")) {
      return NextResponse.json(
        { success: false, error: "Invalid token address" },
        { status: 400 }
      );
    }

    const tokens = await readTokens();
    const existingIndex = tokens.findIndex(
      (t) => t.token.toLowerCase() === token.toLowerCase()
    );

    const newRecord: PlatformTokenRecord = {
      token: token.toLowerCase(),
      curve: curve || "",
      deployer: deployer || "",
      name: name || "",
      symbol: symbol || "",
      logo: logo || "",
      description: description || "",
      txHash: txHash || "",
      blockNumber: blockNumber || "",
      createdAt: new Date().toISOString(),
    };

    if (existingIndex >= 0) {
      tokens[existingIndex] = {
        ...tokens[existingIndex],
        ...newRecord,
        createdAt: tokens[existingIndex].createdAt || newRecord.createdAt,
      };
    } else {
      tokens.unshift(newRecord);
    }

    await saveTokens(tokens);
    return NextResponse.json({ success: true, tokens, record: newRecord });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Failed to save platform token";
    console.error("Error saving platform token:", err);
    return NextResponse.json(
      { success: false, error: msg },
      { status: 500 }
    );
  }
}

export async function DELETE(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const token = searchParams.get("token");

    if (token) {
      const tokens = await readTokens();
      const filtered = tokens.filter((t) => t.token.toLowerCase() !== token.toLowerCase());
      await saveTokens(filtered);
      return NextResponse.json({ success: true, tokens: filtered });
    } else {
      // Clear all tokens
      await saveTokens([]);
      return NextResponse.json({ success: true, tokens: [] });
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Failed to delete token(s)";
    return NextResponse.json(
      { success: false, error: msg },
      { status: 500 }
    );
  }
}
