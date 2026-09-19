import type { Metadata } from "next";
import { Inter, Patrick_Hand, Kalam } from "next/font/google";
import "./globals.css";
import { Web3Provider } from "@/components/Web3Provider";
import { Navbar } from "@/components/Navbar";
import Link from "next/link";
import { FileText } from "lucide-react";

const inter = Inter({ subsets: ["latin"], variable: "--font-sans" });
const patrickHand = Patrick_Hand({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-hand",
});
const kalam = Kalam({
  weight: ["400", "700"],
  subsets: ["latin"],
  variable: "--font-kalam",
});

export const metadata: Metadata = {
  metadataBase: new URL("https://lockey.site"),
  title: "LOCKEY | Live Narrative Radar & Fast Launch",
  description: "Monitor crypto narratives and launch tokens instantly on Robinhood Chain.",
  icons: {
    icon: "/logo.png",
    shortcut: "/logo.png",
    apple: "/logo.png",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body
        className={`${inter.variable} ${patrickHand.variable} ${kalam.variable} font-sans bg-[#090a0f] text-zinc-100 min-h-screen flex flex-col antialiased selection:bg-yellow-400 selection:text-black`}
      >
        <Web3Provider>
          <Navbar />
          <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8">
            {children}
          </main>
          <footer className="border-t border-zinc-800/80 bg-[#0c0d12] py-6 mt-16">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col sm:flex-row items-center justify-between gap-5 text-xs">
              {/* Network Badge in Flat Yellow Style */}
              <div className="flex items-center space-x-2 text-zinc-200 px-3.5 py-1.5 bg-zinc-900/90 border border-yellow-500/25 rounded-lg shadow-sm">
                <span className="w-2 h-2 rounded-full bg-yellow-400 animate-pulse"></span>
                <span className="font-semibold text-sm text-white tracking-wide">
                  Robinhood Chain (Pons v2)
                </span>
                <span className="text-zinc-600">•</span>
                <span className="font-mono text-xs text-yellow-400 font-semibold">ID: 4663</span>
                <span className="text-zinc-600">•</span>
                <span className="font-mono text-xs text-zinc-300 font-bold">ETH Native</span>
              </div>

              {/* Footer Actions */}
              <div className="flex items-center space-x-3">
                {/* Official Docs Link */}
                <Link
                  href="/docs"
                  className="px-3.5 py-1.5 flex items-center space-x-2 text-zinc-300 hover:text-yellow-400 bg-zinc-900/80 hover:bg-zinc-800 border border-zinc-750 hover:border-yellow-500/40 font-medium text-xs rounded-lg transition-all"
                >
                  <FileText className="w-3.5 h-3.5 text-yellow-400" />
                  <span className="font-semibold">Docs</span>
                </Link>

                {/* Official Twitter / X Link */}
                <a
                  href="https://x.com/lockeyhub"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="sketch-btn-secondary px-3.5 py-1.5 flex items-center space-x-2 text-yellow-400 hover:text-white font-medium text-xs rounded-lg transition-all"
                >
                  <svg
                    className="w-3.5 h-3.5 fill-current text-yellow-400 group-hover:text-white transition-colors"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 22.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                  </svg>
                  <span className="font-semibold">@lockeyhub</span>
                </a>
              </div>
            </div>
          </footer>
        </Web3Provider>
      </body>
    </html>
  );
}
