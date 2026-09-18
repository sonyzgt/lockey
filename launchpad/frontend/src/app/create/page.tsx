"use client";

import { useState, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract, useBalance } from "wagmi";
import { formatUnits, parseUnits, parseEventLogs, toHex } from "viem";
import { Rocket, Info, AlertCircle, CheckCircle2, Sparkles, UploadCloud, X, Loader2, Coins, Globe, MessageSquare, Send } from "lucide-react";
import { CONTRACT_ADDRESSES } from "@/config/chain";
import { PONS_FACTORY_ABI, PONS_ROUTER_ABI } from "@/config/abis";
import { useToast } from "@/components/Toast";

export default function CreateTokenPage() {
  const router = useRouter();
  const toast = useToast();
  const { isConnected, address } = useAccount();

  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [description, setDescription] = useState("");
  const [imageUrl, setImageUrl] = useState("");
  const [website, setWebsite] = useState("");
  const [twitter, setTwitter] = useState("");
  const [telegram, setTelegram] = useState("");
  const [discord, setDiscord] = useState("");
  
  // Custom Creator Royalty Rate Selection (0% to 10%)
  const [creatorFeePercent, setCreatorFeePercent] = useState<number>(1); // Default 1%
  const [buybackEnabled, setBuybackEnabled] = useState<boolean>(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Optional Initial Dev Buy (in ETH)
  const [devBuyAmount, setDevBuyAmount] = useState<string>("");

  // Pinata Image Upload States
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [isUploadingImage, setIsUploadingImage] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [isDragging, setIsDragging] = useState(false);

  const uploadToPinata = async (file: File) => {
    setIsUploadingImage(true);
    setUploadError(null);

    try {
      const formData = new FormData();
      formData.append("file", file);

      const res = await fetch("/api/upload", {
        method: "POST",
        body: formData,
      });

      let data: any;
      try {
        data = await res.json();
      } catch {
        if (res.status === 413) {
          throw new Error("Image exceeds web server size limit (HTTP 413). Please upload an image under 1MB or update Nginx client_max_body_size.");
        }
        throw new Error(`Upload failed with server status ${res.status}`);
      }

      if (!res.ok) {
        throw new Error(data.error || "Failed to upload image");
      }

      const resolvedUrl = data.ipfsUri?.startsWith("ipfs://")
        ? data.ipfsUri
        : (typeof window !== "undefined" && (data.url?.startsWith("/") || data.gatewayUrl?.startsWith("/"))
          ? `${window.location.origin}${data.url || data.gatewayUrl}`
          : (data.url || data.gatewayUrl || data.ipfsUri));

      setImageUrl(resolvedUrl);
    } catch (err: unknown) {
      console.error("Image upload error:", err);
      const msg = err instanceof Error ? err.message : "Failed to upload image";
      setUploadError(msg);
    } finally {
      setIsUploadingImage(false);
    }
  };

  const handleImageSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (file.size > 5 * 1024 * 1024) {
      setUploadError("File size exceeds 5MB limit");
      return;
    }

    setImageFile(file);
    const previewUrl = URL.createObjectURL(file);
    setImagePreview(previewUrl);

    uploadToPinata(file);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);

    const file = e.dataTransfer.files?.[0];
    if (!file) return;

    if (!file.type.startsWith("image/")) {
      setUploadError("File must be an image format (PNG, JPG, WebP, GIF, SVG)");
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      setUploadError("File size exceeds 5MB limit");
      return;
    }

    setImageFile(file);
    const previewUrl = URL.createObjectURL(file);
    setImagePreview(previewUrl);

    uploadToPinata(file);
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  };

  const handleDragLeave = () => {
    setIsDragging(false);
  };

  const handleRemoveImage = () => {
    setImageFile(null);
    if (imagePreview) {
      URL.revokeObjectURL(imagePreview);
    }
    setImagePreview(null);
    setImageUrl("");
    setUploadError(null);
  };

  // Read Protocol Settings from Pons Factory
  const { data: launchFee } = useReadContract({
    address: CONTRACT_ADDRESSES.factory,
    abi: PONS_FACTORY_ABI,
    functionName: "launchFee",
  });

  const { data: expectedEconomics } = useReadContract({
    address: CONTRACT_ADDRESSES.factory,
    abi: PONS_FACTORY_ABI,
    functionName: "previewLaunchEconomics",
    args: [0n, "0x0000000000000000000000000000000000000000"],
  });

  const { data: userEthBalance } = useBalance({
    address: address,
  });

  const { writeContract, data: txHash, isPending: isSubmitting } = useWriteContract();
  const { data: txReceipt, isLoading: isWaitingTx, isSuccess: isCreated } = useWaitForTransactionReceipt({ hash: txHash });

  const redirectedRef = useRef(false);

  useEffect(() => {
    if (isCreated && txReceipt && !redirectedRef.current) {
      let tokenAddr: string | null = null;
      let curveAddr: string | null = null;
      try {
        const parsedLogs = parseEventLogs({
          abi: PONS_FACTORY_ABI,
          eventName: "TokenLaunched",
          logs: txReceipt.logs,
        });
        if (parsedLogs.length > 0 && parsedLogs[0].args?.token) {
          tokenAddr = parsedLogs[0].args.token;
          curveAddr = parsedLogs[0].args.curve || null;
        }
      } catch (err) {
        console.warn("Error parsing TokenLaunched event:", err);
      }

      if (!tokenAddr) {
        const factoryAddr = CONTRACT_ADDRESSES.factory.toLowerCase();
        for (const log of txReceipt.logs) {
          if (log.address.toLowerCase() === factoryAddr && log.topics[1]) {
            tokenAddr = `0x${log.topics[1].slice(26)}`;
            if (log.topics[2]) {
              curveAddr = `0x${log.topics[2].slice(26)}`;
            }
            break;
          }
        }
      }

      if (tokenAddr) {
        redirectedRef.current = true;

        // Persist token to platform backend & local cache so it appears exclusively in Vana Explorer
        try {
          fetch("/api/tokens", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              token: tokenAddr,
              curve: curveAddr || "",
              deployer: address,
              name,
              symbol,
              logo: imageUrl || "",
              description,
              txHash,
              blockNumber: txReceipt.blockNumber ? txReceipt.blockNumber.toString() : "",
            }),
          }).catch((e) => console.warn("Could not register token to platform API:", e));

          const existingLocal = JSON.parse(localStorage.getItem("vana_platform_tokens") || "[]");
          if (!existingLocal.some((t: { token?: string }) => t.token?.toLowerCase() === tokenAddr?.toLowerCase())) {
            existingLocal.unshift({
              token: tokenAddr,
              curve: curveAddr || "",
              deployer: address,
              name,
              symbol,
              logo: imageUrl || "",
              description,
              txHash,
              createdAt: new Date().toISOString(),
            });
            localStorage.setItem("vana_platform_tokens", JSON.stringify(existingLocal));
          }
        } catch (err) {
          console.warn("Failed to cache platform token:", err);
        }

        toast.success(
          "Token Launched Successfully via Vana!",
          "Entering live token curve trading page...",
          txHash
        );

        // Automatically navigate into the token page
        const timer = setTimeout(() => {
          router.push(`/token/${tokenAddr}`);
        }, 1200);

        return () => clearTimeout(timer);
      }
    }
  }, [isCreated, txReceipt, txHash, router, toast, address, name, symbol, imageUrl, description]);

  // Dev Buy Calculations
  const parsedDevBuy = devBuyAmount && Number(devBuyAmount) > 0
    ? parseUnits(devBuyAmount, 18)
    : 0n;

  const currentLaunchFee = launchFee ?? parseUnits("0.0005", 18);
  const totalRequiredEth = currentLaunchFee + parsedDevBuy;

  const isInsufficientEth =
    userEthBalance && userEthBalance.value < totalRequiredEth;

  const handleDeploy = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);

    if (!name || !symbol) return;
    if (!address) {
      setErrorMessage("Please connect your Web3 wallet first.");
      return;
    }

    try {
      const salt = toHex(crypto.getRandomValues(new Uint8Array(32)));
      const fallbackEconomics = expectedEconomics || "0x0000000000000000000000000000000000000000000000000000000000000000";

      const tokenParams = {
        name,
        symbol,
        logo: imageUrl || "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi",
        description,
        socials: {
          twitter: twitter.trim(),
          telegram: telegram.trim(),
          discord: discord.trim(),
          website: website.trim(),
          farcaster: "",
        },
        creatorFeeRecipient: address,
        creatorTaxBps: Math.min(Math.max(Math.round(creatorFeePercent * 100), 0), 1000),
        buybackEnabled,
        expectedEconomics: fallbackEconomics,
        salt,
      };

      if (parsedDevBuy > 0n) {
        writeContract({
          address: CONTRACT_ADDRESSES.launchAndBuy,
          abi: PONS_ROUTER_ABI,
          functionName: "launchAndBuy",
          args: [
            tokenParams,
            0n, // launchConfigId 0 (Standard fixed supply)
            "0x0000000000000000000000000000000000000000", // native ETH pairToken
            parsedDevBuy,
            0n, // minTokensOut
            address, // recipient
            [], // extra snipe exemptions
          ],
          value: totalRequiredEth,
        });
      } else {
        writeContract({
          address: CONTRACT_ADDRESSES.factory,
          abi: PONS_FACTORY_ABI,
          functionName: "launchToken",
          args: [
            tokenParams,
            0n,
            "0x0000000000000000000000000000000000000000",
          ],
          value: currentLaunchFee,
        });
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Failed to initiate token deployment.";
      console.error(err);
      toast.error("Deployment Error", msg.split("\n")[0]);
      setErrorMessage(msg);
    }
  };

  return (
    <div className="max-w-5xl mx-auto space-y-8 pb-20">
      {/* Header Banner */}
      <div className="space-y-2">
        <div className="inline-flex items-center space-x-2 px-3 py-1 sketch-badge bg-[#0c2e1b] text-emerald-300 text-xs font-hand font-bold tracking-wide border border-emerald-500/40">
          <Sparkles className="w-4 h-4 text-emerald-400" />
          <span>Creator&apos;s Blueprint • Pons v2 on Robinhood Chain</span>
        </div>
        <h1 className="text-4xl sm:text-5xl font-kalam font-bold text-white tracking-wide flex items-center space-x-2">
          <span>Launch Meme Token</span>
          <span className="text-3xl">🚀</span>
        </h1>
        <p className="text-base font-hand text-emerald-200/90">
          Deploy token with automated bonding curve & liquidity migration to Uniswap v4 on Robinhood Chain (Zero-Rug Guarantee).
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
        {/* Left Form: Blueprint Sketchpad */}
        <form onSubmit={handleDeploy} className="lg:col-span-7 space-y-6 sketch-card p-6 sm:p-8 relative bg-[#092214]">
          {/* Top Mint Tape */}
          <div className="hidden sm:block absolute -top-3 left-10 w-28 h-5 bg-emerald-400/35 border border-dashed border-emerald-400 rotate-1 pointer-events-none"></div>

          <div className="space-y-5">
            <div>
              <label className="block text-base font-hand font-bold text-slate-200 mb-1">
                Token Name *
              </label>
              <input
                type="text"
                required
                placeholder="e.g. Robinhood Doge"
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full px-4 py-2.5 sketch-inset text-sm font-hand text-white placeholder:text-slate-500 focus:outline-none"
              />
            </div>

            <div>
              <label className="block text-base font-hand font-bold text-slate-200 mb-1">
                Ticker Symbol *
              </label>
              <input
                type="text"
                required
                placeholder="e.g. RDOGE"
                value={symbol}
                onChange={(e) => setSymbol(e.target.value.toUpperCase())}
                className="w-full px-4 py-2.5 sketch-inset text-sm text-white uppercase font-mono placeholder:text-slate-500 focus:outline-none"
              />
            </div>

            {/* Creator Fee Royalty Stamps */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <label className="block text-base font-hand font-bold text-slate-200">
                  Creator Trading Royalty *
                </label>
                <span className="text-sm font-mono text-yellow-300 font-bold">
                  {creatorFeePercent}% ({creatorFeePercent * 100} bps)
                </span>
              </div>
              
              <p className="text-xs font-hand text-slate-400">
                Automated royalties transferred to your wallet on every buy & sell trade across the bonding curve (max 10%):
              </p>

              <div className="grid grid-cols-5 gap-2.5 pt-1">
                {[0, 1, 2, 3, 5].map((fee) => {
                  const isSelected = creatorFeePercent === fee;
                  return (
                    <button
                      key={fee}
                      type="button"
                      onClick={() => setCreatorFeePercent(fee)}
                      className={`py-2 rounded-sketch font-bold font-hand transition flex flex-col items-center justify-center ${
                        isSelected
                          ? "sketch-btn-primary text-slate-950 font-bold"
                          : "sketch-btn-secondary text-slate-300"
                      }`}
                    >
                      <span className="text-base">{fee}%</span>
                      <span className="text-[10px] opacity-80">Royalty</span>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Buyback & Vesting Toggle */}
            <div className="p-4 sketch-surface flex items-center justify-between">
              <div className="space-y-0.5">
                <span className="text-sm font-hand font-bold text-white block">Auto Buyback & 5-Year Vesting</span>
                <span className="text-xs font-hand text-slate-400 block">
                  A portion of trading fees is used for token buyback & locked in 5-year vesting.
                </span>
              </div>
              <input
                type="checkbox"
                checked={buybackEnabled}
                onChange={(e) => setBuybackEnabled(e.target.checked)}
                className="w-5 h-5 rounded accent-sky-500 cursor-pointer"
              />
            </div>

            <div>
              <label className="block text-base font-hand font-bold text-slate-200 mb-1">
                Project Description (Optional)
              </label>
              <textarea
                rows={3}
                placeholder="Tell the story of your meme token and community vision..."
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                className="w-full px-4 py-2.5 sketch-inset text-sm font-hand text-white placeholder:text-slate-500 focus:outline-none"
              />
            </div>

            {/* Pinata IPFS Image Upload Zone in Sketch Style */}
            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="block text-base font-hand font-bold text-slate-200">
                  Token Logo / Image
                </label>
                {imageUrl && (
                  <span className="text-xs font-hand text-emerald-400 font-bold flex items-center space-x-1">
                    <CheckCircle2 className="w-3.5 h-3.5" />
                    <span>Image Ready</span>
                  </span>
                )}
              </div>

              {imagePreview ? (
                <div className="relative sketch-surface p-4 flex items-center space-x-4">
                  <div className="relative w-16 h-16 rounded-sketch overflow-hidden bg-[#061426] border-2 border-sky-400 shrink-0 flex items-center justify-center shadow-sketch-sm">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={imagePreview}
                      alt="Token Preview"
                      className="w-full h-full object-cover rounded-sketch"
                    />
                    {isUploadingImage && (
                      <div className="absolute inset-0 bg-black/70 flex items-center justify-center">
                        <Loader2 className="w-6 h-6 text-sky-400 animate-spin" />
                      </div>
                    )}
                  </div>

                  <div className="flex-1 min-w-0 space-y-1">
                    <p className="text-sm font-hand font-bold text-white truncate">
                      {imageFile?.name || "Uploaded Image"}
                    </p>
                    {isUploadingImage ? (
                      <p className="text-xs font-hand text-sky-300 flex items-center space-x-1">
                        <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        <span>Uploading image...</span>
                      </p>
                    ) : imageUrl ? (
                      <p className="text-[11px] font-mono text-emerald-400 truncate">
                        {imageUrl}
                      </p>
                    ) : null}
                  </div>

                  <button
                    type="button"
                    onClick={handleRemoveImage}
                    disabled={isUploadingImage}
                    className="p-1.5 sketch-btn-secondary text-slate-400 hover:text-rose-400"
                    title="Remove image"
                  >
                    <X className="w-4 h-4" />
                  </button>
                </div>
              ) : (
                <div
                  onDrop={handleDrop}
                  onDragOver={handleDragOver}
                  onDragLeave={handleDragLeave}
                  className={`relative border-2 border-dashed rounded-sketch p-6 text-center transition cursor-pointer ${
                    isDragging
                      ? "border-sky-400 bg-sky-500/10"
                      : "border-slate-600 hover:border-sky-400 sketch-surface"
                  }`}
                >
                  <input
                    type="file"
                    accept="image/png,image/jpeg,image/webp,image/gif,image/svg+xml"
                    onChange={handleImageSelect}
                    className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                    disabled={isUploadingImage}
                  />
                  <div className="flex flex-col items-center justify-center space-y-2 pointer-events-none">
                    <div className="w-12 h-12 rounded-sketch sketch-btn-primary flex items-center justify-center text-slate-950">
                      <UploadCloud className="w-6 h-6" />
                    </div>
                    <div className="space-y-0.5">
                      <p className="text-base font-hand font-bold text-white">
                        Drag &amp; drop logo image here, or <span className="text-sky-400 underline">browse files</span>
                      </p>
                      <p className="text-xs font-hand text-slate-400">
                        PNG, JPG, WebP, GIF up to 5MB
                      </p>
                    </div>
                  </div>
                </div>
              )}

              {uploadError && (
                <p className="mt-2 text-xs font-hand text-rose-400 flex items-center space-x-1.5">
                  <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                  <span>{uploadError}</span>
                </p>
              )}
            </div>

            {/* Social Links */}
            <div className="space-y-3 pt-2">
              <label className="block text-base font-hand font-bold text-slate-200">
                Social Links &amp; Community
              </label>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div className="relative">
                  <Globe className="w-4 h-4 text-slate-500 absolute left-3.5 top-3" />
                  <input
                    type="url"
                    placeholder="Website URL"
                    value={website}
                    onChange={(e) => setWebsite(e.target.value)}
                    className="w-full pl-10 pr-4 py-2 sketch-inset text-xs font-mono text-white placeholder:text-slate-500 focus:outline-none"
                  />
                </div>
                <div className="relative">
                  <span className="text-slate-500 font-bold absolute left-3.5 top-2 text-xs">𝕏</span>
                  <input
                    type="text"
                    placeholder="Twitter / X"
                    value={twitter}
                    onChange={(e) => setTwitter(e.target.value)}
                    className="w-full pl-10 pr-4 py-2 sketch-inset text-xs font-mono text-white placeholder:text-slate-500 focus:outline-none"
                  />
                </div>
                <div className="relative">
                  <Send className="w-4 h-4 text-slate-500 absolute left-3.5 top-3" />
                  <input
                    type="text"
                    placeholder="Telegram"
                    value={telegram}
                    onChange={(e) => setTelegram(e.target.value)}
                    className="w-full pl-10 pr-4 py-2 sketch-inset text-xs font-mono text-white placeholder:text-slate-500 focus:outline-none"
                  />
                </div>
                <div className="relative">
                  <MessageSquare className="w-4 h-4 text-slate-500 absolute left-3.5 top-3" />
                  <input
                    type="text"
                    placeholder="Discord"
                    value={discord}
                    onChange={(e) => setDiscord(e.target.value)}
                    className="w-full pl-10 pr-4 py-2 sketch-inset text-xs font-mono text-white placeholder:text-slate-500 focus:outline-none"
                  />
                </div>
              </div>
            </div>

            {/* Optional Dev Buy Section */}
            <div className="pt-4 border-t-2 border-dashed border-slate-700 space-y-3">
              <div className="flex items-center justify-between">
                <label className="text-base font-hand font-bold text-slate-200 flex items-center space-x-1.5">
                  <Coins className="w-4 h-4 text-yellow-300" />
                  <span>Initial Dev Buy (Optional)</span>
                </label>
                <span className="text-xs text-slate-400 font-mono">
                  Balance: {userEthBalance ? `${Number(formatUnits(userEthBalance.value, 18)).toFixed(4)} ETH` : "0.00 ETH"}
                </span>
              </div>
              
              <p className="text-xs font-hand text-slate-400 leading-relaxed">
                Purchase tokens atomically during deployment via Pons v2 <code>launchAndBuy</code> router (snipe tax free).
              </p>

              <div className="relative">
                <input
                  type="number"
                  step="0.001"
                  min="0"
                  placeholder="0.0 (ETH)"
                  value={devBuyAmount}
                  onChange={(e) => setDevBuyAmount(e.target.value)}
                  className="w-full px-4 py-2.5 sketch-inset text-sm text-white font-mono placeholder:text-slate-500 focus:outline-none"
                />
                <button
                  type="button"
                  onClick={() => {
                    if (userEthBalance && userEthBalance.value > currentLaunchFee) {
                      const safeMax = userEthBalance.value - currentLaunchFee - parseUnits("0.001", 18);
                      if (safeMax > 0n) {
                        setDevBuyAmount(formatUnits(safeMax, 18));
                      }
                    }
                  }}
                  className="absolute right-3 top-2 px-3 py-0.5 text-xs font-hand font-bold sketch-btn-secondary text-sky-300"
                >
                  MAX
                </button>
              </div>
            </div>

            {/* Protocol Cost Summary Note */}
            <div className="p-4 sketch-surface space-y-2 text-xs font-hand">
              <div className="flex justify-between items-center text-slate-300 text-sm">
                <span className="flex items-center space-x-1.5">
                  <Info className="w-4 h-4 text-sky-400" />
                  <span>Pons Protocol Launch Fee</span>
                </span>
                <span className="font-mono font-bold text-white">
                  {formatUnits(currentLaunchFee, 18)} ETH
                </span>
              </div>
              {parsedDevBuy > 0n && (
                <div className="flex justify-between items-center text-slate-300 text-sm">
                  <span>Initial Dev Buy</span>
                  <span className="font-mono font-bold text-yellow-300">
                    {formatUnits(parsedDevBuy, 18)} ETH
                  </span>
                </div>
              )}
              <div className="flex justify-between items-center text-slate-200 pt-2 border-t border-slate-700 text-sm">
                <span className="font-bold">Total ETH Required</span>
                <span className="font-mono font-bold text-emerald-400 text-base">
                  {formatUnits(totalRequiredEth, 18)} ETH
                </span>
              </div>
            </div>

            {isInsufficientEth && (
              <div className="p-3 sketch-card border-rose-500/40 text-rose-300 text-xs font-hand font-bold flex items-center space-x-2">
                <AlertCircle className="w-4 h-4 shrink-0" />
                <span>Insufficient ETH balance for launch fee + dev buy.</span>
              </div>
            )}

            {errorMessage && (
              <div className="p-4 sketch-card border-rose-500/40 text-rose-300 text-xs font-hand font-bold flex items-start space-x-2.5">
                <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                <span>{errorMessage}</span>
              </div>
            )}

            <button
              type="submit"
              disabled={isSubmitting || isWaitingTx || isUploadingImage || isInsufficientEth || !isConnected}
              className="w-full py-3.5 sketch-btn-primary text-slate-950 font-bold text-xl flex items-center justify-center space-x-2 disabled:opacity-50"
            >
              {isSubmitting || isWaitingTx ? (
                <>
                  <Loader2 className="w-5 h-5 animate-spin" />
                  <span>{isSubmitting ? "Waiting for Wallet Approval..." : "Deploying to Robinhood Chain..."}</span>
                </>
              ) : !isConnected ? (
                <span>Connect Wallet First</span>
              ) : (
                <>
                  <Rocket className="w-6 h-6" />
                  <span>Launch Token ({formatUnits(totalRequiredEth, 18)} ETH)</span>
                </>
              )}
            </button>
          </div>
        </form>

        {/* Right Column: Live Doodle Index Card Preview */}
        <div className="lg:col-span-5 space-y-6 lg:sticky lg:top-24">
          <div className="sketch-card p-6 space-y-4 relative bg-[#092214]">
            {/* Top Mint Tape */}
            <div className="absolute -top-3 left-1/2 -translate-x-1/2 w-28 h-5 bg-emerald-400/40 border border-dashed border-emerald-400 -rotate-1 pointer-events-none"></div>

            <div className="flex items-center justify-between border-b-2 border-dashed border-emerald-800/80 pb-3">
              <span className="font-hand text-base font-bold text-emerald-300 uppercase tracking-wider flex items-center space-x-1">
                <Sparkles className="w-4 h-4 text-emerald-400" />
                <span>Token Card Preview</span>
              </span>
              <span className="text-xs font-mono sketch-badge px-2 py-0.5 bg-[#0c2e1b] text-emerald-300 border border-emerald-600/40">
                Live Draft
              </span>
            </div>

            <div className="flex items-start space-x-4 pt-1">
              <div className="w-16 h-16 rounded-sketch overflow-hidden bg-[#041208] border-2 border-emerald-400 shrink-0 flex items-center justify-center shadow-sketch-sm">
                {imagePreview ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={imagePreview} alt="Preview" className="w-full h-full object-cover rounded-sketch" />
                ) : (
                  <span className="text-2xl">🪙</span>
                )}
              </div>
              <div className="min-w-0">
                <h3 className="text-2xl font-kalam font-bold text-white truncate">
                  {name.trim() || "Your Token Name"}
                </h3>
                <span className="text-sm px-2.5 py-0.5 sketch-badge bg-emerald-500/20 text-emerald-300 font-mono font-bold uppercase border border-emerald-500/40">
                  ${symbol.trim() || "TICKER"}
                </span>
              </div>
            </div>

            <p className="text-sm font-hand text-slate-300 line-clamp-3 leading-relaxed">
              {description.trim() || "Your token description will appear here on Vana Token Explorer..."}
            </p>

            <div className="p-3 sketch-surface space-y-2 text-xs font-hand">
              <div className="flex justify-between items-center text-slate-300">
                <span>Total Token Supply:</span>
                <span className="font-mono font-bold text-white">1,000,000,000</span>
              </div>
              <div className="flex justify-between items-center text-slate-300">
                <span>Creator Royalty:</span>
                <span className="font-mono font-bold text-yellow-300">{creatorFeePercent}%</span>
              </div>
              <div className="flex justify-between items-center text-slate-300">
                <span>Curve Graduation Target:</span>
                <span className="font-mono font-bold text-emerald-400">4.2 ETH (Uniswap v4)</span>
              </div>
            </div>

            <div className="pt-2 text-center text-xs font-hand text-slate-400">
              ✏️ This token will be exclusively tracked on Vana Explorer
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
