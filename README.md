# LOCKEY Launchpad ⚡

> **Live Narrative Radar & Fast Fair Launchpad on Robinhood Chain**  
> Direct integration with **Pons v2 Factory (`0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e`)**.

[![Robinhood Chain](https://img.shields.io/badge/Chain-Robinhood%204663-eab308)](https://robinhood.com)
[![Pons v2 Protocol](https://img.shields.io/badge/Protocol-Pons%20v2-yellow)](https://docs.ponsfamily.com/v2)
[![Twitter](https://img.shields.io/badge/Twitter-@lockeyhub-black?logo=x)](https://x.com/lockeyhub)

---

## 🚀 Key Features

- **Live Narrative Radar**: Real-time Twitter / X sentiment detection and instant viral narrative token launcher.
- **Pons v2 Factory Direct Launch**: Deploys zero-rug ERC20 bonding curve tokens directly through Pons v2 on Robinhood Chain (`Chain ID: 4663`).
- **USD / GMGN Synchronized Metrics**: Real-time Market Cap ($), token price ($), and total volume ($) with ETH native values.
- **Flat Yellow Modern UI**: Sleek, high-contrast dark theme with vibrant yellow accents.
- **Automated Graduation**: When the curve reaches its target liquidity, 100% of liquidity automatically migrates and locks into Uniswap v4.
- **Creator Royalties Escrow**: Real-time claiming dashboard for creator fee distributions via Pons Fee Escrow.
- **Pure Fair Launch**: Zero 5-year lockup traps or hidden buyback locks.

---

## 🛠️ Project Structure

```
lockey/
├── launchpad/
│   ├── frontend/            # Next.js 14, Wagmi, Viem, Tailwind CSS, Lucide icons
│   │   ├── src/
│   │   │   ├── app/         # App router (Radar, Explore, Create, Token Detail, Creator Fees, Docs)
│   │   │   ├── components/  # RealTradingChart, Navbar, FastLaunchModal, etc.
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
npm run build
npm run start
```

---

## 🌐 Official Links

- **Twitter / X**: [@lockeyhub](https://x.com/lockeyhub)
- **Chain**: Robinhood Chain (`Chain ID: 4663`, Native: `ETH`)
- **Pons Factory Contract**: `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e`
