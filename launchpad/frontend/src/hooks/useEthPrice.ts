import { useState, useEffect } from 'react';

// Fallback constant in case network request fails
const FALLBACK_ETH_PRICE = 2510;

export function useEthPrice() {
  const [ethPriceUsd, setEthPriceUsd] = useState<number>(FALLBACK_ETH_PRICE);

  useEffect(() => {
    let isMounted = true;

    async function fetchPrice() {
      try {
        const res = await fetch('https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDT');
        if (res.ok) {
          const data = await res.json();
          const p = parseFloat(data.price);
          if (p > 0 && isMounted) {
            setEthPriceUsd(p);
            return;
          }
        }
      } catch (err) {
        try {
          const cgRes = await fetch('https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd');
          if (cgRes.ok) {
            const cgData = await cgRes.json();
            const p = cgData?.ethereum?.usd;
            if (p > 0 && isMounted) {
              setEthPriceUsd(p);
              return;
            }
          }
        } catch {
          // ignore, keep fallback
        }
      }
    }

    fetchPrice();
    const interval = setInterval(fetchPrice, 30000);
    return () => {
      isMounted = false;
      clearInterval(interval);
    };
  }, []);

  return ethPriceUsd;
}

export function formatUsd(val: number): string {
  if (!val || isNaN(val) || val <= 0) return '.00';
  if (val >= 1_000_000) {
    return '$' + (val / 1_000_000).toFixed(2) + 'M';
  }
  if (val >= 1_000) {
    return '$' + (val / 1_000).toFixed(2) + 'K';
  }
  if (val >= 1) {
    return '$' + val.toFixed(2);
  }
  if (val >= 0.0001) {
    return '$' + val.toFixed(4);
  }
  return '$' + val.toFixed(7);
}
