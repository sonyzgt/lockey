import { NextRequest, NextResponse } from "next/server";

export async function POST(req: NextRequest) {
  try {
    const pinataJwt = process.env.PINATA_JWT;
    if (!pinataJwt || pinataJwt.trim() === "") {
      return NextResponse.json(
        {
          error:
            "PINATA_JWT is not configured. Please add your Pinata JWT to frontend/.env.local (PINATA_JWT=your_jwt_here).",
        },
        { status: 400 }
      );
    }

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

    const pinataFormData = new FormData();
    pinataFormData.append("file", file);

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

    if (!response.ok) {
      const errText = await response.text();
      console.error("Pinata error:", errText);
      return NextResponse.json(
        { error: `Pinata upload failed (${response.status}): ${errText}` },
        { status: response.status }
      );
    }

    const result = await response.json();
    const ipfsHash = result.IpfsHash;
    const gateway =
      process.env.NEXT_PUBLIC_PINATA_GATEWAY || "https://gateway.pinata.cloud/ipfs/";
    const normalizedGateway = gateway.endsWith("/") ? gateway : `${gateway}/`;
    const gatewayUrl = `${normalizedGateway}${ipfsHash}`;
    const ipfsUri = `ipfs://${ipfsHash}`;

    return NextResponse.json({
      ipfsHash,
      ipfsUri,
      gatewayUrl,
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
