import { NextRequest, NextResponse } from "next/server";
import fs from "fs/promises";
import path from "path";
import crypto from "crypto";

export async function POST(req: NextRequest) {
  try {
    const formData = await req.formData();
    const file = formData.get("file") as File | null;

    if (!file) {
      return NextResponse.json({ error: "No file provided" }, { status: 400 });
    }

    if (file.size > 5 * 1024 * 1024) {
      return NextResponse.json(
        { error: "File size exceeds 5MB limit" },
        { status: 400 }
      );
    }

    const bytes = await file.arrayBuffer();
    const buffer = Buffer.from(bytes);

    // 1. If PINATA_JWT is configured, attempt upload to Pinata IPFS first
    const pinataJwt = process.env.PINATA_JWT;
    if (pinataJwt && pinataJwt.trim() !== "") {
      try {
        const pinataFormData = new FormData();
        const blob = new Blob([buffer], { type: file.type });
        pinataFormData.append("file", blob, file.name || "token-image");

        const metadata = JSON.stringify({
          name: file.name || "launchpad-token-image",
        });
        pinataFormData.append("pinataMetadata", metadata);

        const pinataOptions = JSON.stringify({
          cidVersion: 1,
        });
        pinataFormData.append("pinataOptions", pinataOptions);

        const response = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${pinataJwt}`,
          },
          body: pinataFormData,
        });

        if (response.ok) {
          const result = await response.json();
          const ipfsHash = result.IpfsHash;
          const gateway =
            process.env.NEXT_PUBLIC_PINATA_GATEWAY || "https://gateway.pinata.cloud/ipfs/";
          const normalizedGateway = gateway.endsWith("/") ? gateway : `${gateway}/`;
          const gatewayUrl = `${normalizedGateway}${ipfsHash}`;
          const ipfsUri = `ipfs://${ipfsHash}`;

          return NextResponse.json({
            success: true,
            ipfsHash,
            ipfsUri,
            gatewayUrl,
            url: gatewayUrl,
          });
        } else {
          console.warn("Pinata upload returned non-ok, falling back to local server storage:", await response.text());
        }
      } catch (pinataErr) {
        console.warn("Pinata upload failed, falling back to local server storage:", pinataErr);
      }
    }

    // 2. Fallback: Save directly to public/uploads directory on server
    const uploadsDir = path.join(process.cwd(), "public", "uploads");
    await fs.mkdir(uploadsDir, { recursive: true });

    const ext = path.extname(file.name) || ".png";
    const hash = crypto.randomBytes(12).toString("hex");
    const safeFilename = `token-${Date.now()}-${hash}${ext}`;
    const filePath = path.join(uploadsDir, safeFilename);

    await fs.writeFile(filePath, buffer);

    const publicUrl = `/uploads/${safeFilename}`;

    return NextResponse.json({
      success: true,
      ipfsHash: "",
      ipfsUri: publicUrl,
      gatewayUrl: publicUrl,
      url: publicUrl,
      local: true,
    });
  } catch (err: unknown) {
    console.error("Upload handler error:", err);
    const message = err instanceof Error ? err.message : "Internal server error during upload";
    return NextResponse.json(
      { error: message },
      { status: 500 }
    );
  }
}
