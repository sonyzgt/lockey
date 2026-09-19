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
        sans: ["var(--font-sans)", "Inter", "system-ui", "sans-serif"],
        hand: ["var(--font-sans)", "Inter", "system-ui", "sans-serif"],
        kalam: ["var(--font-sans)", "Inter", "system-ui", "sans-serif"],
      },
      colors: {
        background: "var(--background)",
        foreground: "var(--foreground)",
        flat: {
          dark: "#090a0f",
          card: "#121318",
          surface: "#181920",
          border: "#27272a",
          yellow: "#facc15",
          gold: "#eab308",
          amber: "#f59e0b",
        },
        sketch: {
          dark: "#090a0f",
          card: "#121318",
          surface: "#181920",
          border: "#27272a",
          ink: "#000000",
          green: "#facc15",
          mint: "#fde047",
          emerald: "#eab308",
          lime: "#fef08a",
          paper: "#121318",
        },
      },
      boxShadow: {
        "sketch-sm": "0 1px 2px 0 rgba(0, 0, 0, 0.3)",
        "sketch": "0 2px 4px 0 rgba(0, 0, 0, 0.3)",
        "sketch-md": "0 4px 8px 0 rgba(0, 0, 0, 0.35)",
        "sketch-lg": "0 8px 16px 0 rgba(0, 0, 0, 0.4)",
        "sketch-green": "0 0 10px 0 rgba(234, 179, 8, 0.25)",
        "sketch-mint": "0 0 12px 0 rgba(250, 204, 21, 0.3)",
        "flat-glow": "0 0 14px 0 rgba(234, 179, 8, 0.2)",
      },
      borderRadius: {
        sketch: "12px",
        "sketch-sm": "8px",
        "sketch-pill": "9999px",
      },
    },
  },
  plugins: [],
};
export default config;
