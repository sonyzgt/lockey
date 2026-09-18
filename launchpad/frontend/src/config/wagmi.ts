import { http, createConfig } from "wagmi";
import { injected } from "wagmi/connectors/injected";
import { robinhoodChain } from "./chain";

export const wagmiConfig = createConfig({
  chains: [robinhoodChain],
  connectors: [
    injected(),
  ],
  transports: {
    [robinhoodChain.id]: http(process.env.NEXT_PUBLIC_RPC_URL || "https://rpc.mainnet.chain.robinhood.com"),
  },
  ssr: true,
});

