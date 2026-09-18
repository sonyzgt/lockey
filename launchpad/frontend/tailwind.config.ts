import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      fontFamily: {
        hand: ["var(--font-hand)", "Patrick Hand", "cursive", "sans-serif"],
        kalam: ["var(--font-kalam)", "Kalam", "cursive", "sans-serif"],
      },
      colors: {
        background: "var(--background)",
        foreground: "var(--foreground)",
        sketch: {
          dark: "#05140b",
          card: "#092214",
          surface: "#0d2f1b",
          border: "#1d6d3d",
          ink: "#020f06",
          green: "#22c55e",
          mint: "#4ade80",
          emerald: "#10b981",
          lime: "#86efac",
          paper: "#092214",
        },
      },
      boxShadow: {
        "sketch-sm": "2px 2px 0px 0px #000000",
        "sketch": "3px 3px 0px 0px #000000",
        "sketch-md": "4px 4px 0px 0px #000000",
        "sketch-lg": "6px 6px 0px 0px #000000",
        "sketch-green": "3px 3px 0px 0px #15803d",
        "sketch-mint": "3px 3px 0px 0px #22c55e",
      },
      borderRadius: {
        sketch: "255px 15px 225px 15px/15px 225px 15px 255px",
        "sketch-sm": "15px 225px 15px 255px/255px 15px 225px 15px",
        "sketch-pill": "255px 25px 225px 25px/25px 225px 25px 255px",
      },
    },
  },
  plugins: [],
};
export default config;
