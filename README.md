# VANA Launchpad 🌿

> **Next-Gen Meme Fair Launchpad & Bonding Curve Protocol on Robinhood Chain**  
> Direct integration with **Pons v2 Factory (`0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e`)**.

[![Robinhood Chain](https://img.shields.io/badge/Chain-Robinhood%204663-10b981)](https://robinhood.com)
[![Pons v2 Protocol](https://img.shields.io/badge/Protocol-Pons%20v2-emerald)](https://docs.ponsfamily.com/v2)
[![Twitter](https://img.shields.io/badge/Twitter-@vana__family-black?logo=x)](https://x.com/vana_family)

---

## 🚀 Key Features

- **Pons v2 Factory Direct Launch**: Deploys zero-rug ERC20 bonding curve tokens directly through Pons v2 on Robinhood Chain (`Chain ID: 4663`).
- **USD / GMGN Synchronized Metrics**: Real-time Market Cap ($), token price ($), and total volume ($) with ETH native values.
- **Hand-Drawn Sketch Aesthetic**: Unique emerald and mint green doodle theme.
- **Automated Graduation**: When the curve reaches its target liquidity, 100% of liquidity automatically migrates and locks into Uniswap v4.
- **Creator Royalties Escrow**: Real-time claiming dashboard for creator fee distributions via Pons Fee Escrow.
- **Isolated Platform Explorer**: Dedicated curation tracking exclusively tokens created through Vana.

---

## 🛠️ Project Structure

```
vana/
├── launchpad/
│   ├── frontend/            # Next.js 14, Wagmi, Viem, Tailwind CSS, Lucide icons
│   │   ├── src/
│   │   │   ├── app/         # App router (Explore, Create, Token Detail, Creator Fees, Docs)
│   │   │   ├── components/  # RealTradingChart, Navbar, Toast, etc.
│   │   │   ├── config/      # Chain config, Pons ABI, Uniswap v4 addresses
│   │   │   ├── data/        # Platform token registry (JSON)
│   │   │   └── hooks/       # useEthPrice, etc.
│   └── contracts/           # Solidity contracts & Foundry test suite
└── README.md
```

---

## 💻 Getting Started (Frontend)

```bash
cd launchpad/frontend
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

---

## 🌐 Official Links

- **Twitter / X**: [@vana_family](https://x.com/vana_family)
- **Chain**: Robinhood Chain (`Chain ID: 4663`, Native: `ETH`)
- **Pons Factory Contract**: `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e`
