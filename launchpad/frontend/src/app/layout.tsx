import type { Metadata } from "next";
import { Inter, Patrick_Hand, Kalam } from "next/font/google";
import "./globals.css";
import { Web3Provider } from "@/components/Web3Provider";
import { Navbar } from "@/components/Navbar";

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
  title: "VANA Launchpad | Robinhood Chain",
  description: "Create meme tokens, trade on Pons v2 bonding curves, and graduate liquidity to Uniswap v4 on Robinhood Chain.",
  icons: {
    icon: "/vana-logo.png",
    shortcut: "/vana-logo.png",
    apple: "/vana-logo.png",
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
        className={`${inter.variable} ${patrickHand.variable} ${kalam.variable} font-sans bg-[#05140b] text-slate-100 min-h-screen flex flex-col antialiased selection:bg-emerald-400 selection:text-slate-950`}
      >
        <Web3Provider>
          <Navbar />
          <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8">
            {children}
          </main>
          <footer className="border-t-2 border-dashed border-emerald-800/60 bg-[#06180d] py-8 mt-16">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col sm:flex-row items-center justify-between gap-5 text-xs">
              {/* Network Badge in Emerald Style */}
              <div className="sketch-badge flex items-center space-x-2 text-emerald-100 px-4 py-1.5 bg-[#0c2e1b] border border-emerald-600/50">
                <span className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse"></span>
                <span className="font-hand text-base font-bold text-white tracking-wide">
                  Robinhood Chain (Pons v2)
                </span>
                <span className="text-emerald-500">•</span>
                <span className="font-mono text-xs text-emerald-300">ID: 4663</span>
                <span className="text-emerald-500">•</span>
                <span className="font-mono text-xs text-emerald-200 font-bold">ETH Native</span>
              </div>

              {/* Official Twitter / X Link */}
              <a
                href="https://x.com/vana_family"
                target="_blank"
                rel="noopener noreferrer"
                className="sketch-btn-secondary px-4 py-2 flex items-center space-x-2.5 text-emerald-200 hover:text-white font-hand font-bold text-base group transition-all"
              >
                <svg
                  className="w-4 h-4 fill-current text-emerald-400 group-hover:text-emerald-200 transition-colors"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 22.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                </svg>
                <span>@vana_family</span>
              </a>
            </div>
          </footer>
        </Web3Provider>
      </body>
    </html>
  );
}
