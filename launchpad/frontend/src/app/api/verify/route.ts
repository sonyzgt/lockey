import { NextRequest, NextResponse } from "next/server";
import { exec } from "child_process";
import path from "path";

export async function POST(req: NextRequest) {
  try {
    const { tokenAddress } = await req.json();

    if (!tokenAddress || !/^0x[a-fA-F0-9]{40}$/.test(tokenAddress)) {
      return NextResponse.json({ error: "Invalid token address" }, { status: 400 });
    }

    const contractsDir = path.resolve(process.cwd(), "../contracts");
    const forgePath = "C:\\Users\\ADMIN\\.foundry\\bin\\forge.exe";

    // 1. Verify on Sourcify (Open-source, decentralized, zero API key required)
    const sourcifyCmd = `"${forgePath}" verify-contract ${tokenAddress} src/LaunchToken.sol:LaunchToken --verifier sourcify --chain 4663`;

    const runCommand = (cmd: string): Promise<{ stdout: string; stderr: string }> => {
      return new Promise((resolve) => {
        exec(cmd, { cwd: contractsDir, timeout: 30000 }, (error, stdout, stderr) => {
          if (error) {
            console.warn(`[AutoVerify] Warning on command "${cmd}":`, error.message);
          }
          resolve({ stdout, stderr });
        });
      });
    };

    console.log(`[AutoVerify] Starting automated verification for token: ${tokenAddress}`);
    const sourcifyResult = await runCommand(sourcifyCmd);
    console.log(`[AutoVerify] Sourcify output:`, sourcifyResult.stdout);

    // 2. If ETHERSCAN_API_KEY is configured in env, also verify on Blockscout / Explorer
    const etherscanKey = process.env.ETHERSCAN_API_KEY;
    let etherscanResult = null;
    if (etherscanKey) {
      const etherscanCmd = `"${forgePath}" verify-contract ${tokenAddress} src/LaunchToken.sol:LaunchToken --chain 4663 --etherscan-api-key ${etherscanKey}`;
      etherscanResult = await runCommand(etherscanCmd);
      console.log(`[AutoVerify] Explorer output:`, etherscanResult.stdout);
    }

    return NextResponse.json({
      success: true,
      message: "Automated verification initiated successfully",
      sourcify: sourcifyResult.stdout,
      etherscan: etherscanResult?.stdout || null,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Internal server error";
    console.error("[AutoVerify] Verification failed:", error);
    return NextResponse.json(
      { error: message },
      { status: 500 }
    );
  }
}
