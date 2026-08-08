import "server-only";

/**
 * Reading Arc, on the server only.
 *
 * `server-only` at the top is load-bearing, not decoration: if any client
 * component ever imports this file the build fails. That is the mechanism that
 * enforces "no RPC from the browser", rather than a convention someone has to
 * remember.
 *
 * Why the browser must never talk to the RPC directly: Arc's public endpoint
 * throttles reads, and the agent shares that budget. A page that read from the
 * browser would multiply RPC load by the number of viewers, and if that
 * happened while a demo run was being recorded, the agent would be the thing
 * that got throttled.
 */

import { createPublicClient, defineChain, http, parseAbi } from "viem";

export const REGISTRY_ADDRESS =
  (process.env.REGISTRY as `0x${string}`) ??
  ("0xbBd50574b55CE9F7453882E2d3361b393AD3F99C" as const);

export const RPC_URL = process.env.ARC_RPC_URL ?? "https://rpc.testnet.arc.network";
export const EXPLORER = "https://testnet.arcscan.app";

export const arcTestnet = defineChain({
  id: 5042002,
  name: "Arc Testnet",
  // 18 decimals, not the 6 that USDC's ERC-20 form uses. Every amount on the
  // page is formatted against this.
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: { default: { name: "Arcscan", url: EXPLORER } },
});

export const publicClient = createPublicClient({
  chain: arcTestnet,
  transport: http(RPC_URL, {
    timeout: 15_000,
    // One retry only. The page must render fast or degrade visibly; it must not
    // sit there hammering a struggling endpoint.
    retryCount: 1,
    retryDelay: 500,
  }),
});

export const registryAbi = parseAbi([
  "function bountyCount() view returns (uint256)",
  "function totalEscrowed() view returns (uint256)",
  "function getBounty(uint256) view returns ((address sponsor, address target, address checker, bytes4 selector, uint256 reward, bool paid, string functionSignature))",
]);

export const checkerAbi = parseAbi([
  "function checkInvariant() view returns (bool)",
]);
