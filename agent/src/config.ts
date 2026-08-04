/**
 * Every knob the agent has, in one file.
 *
 * The pacing value below is the important one. Task 7 will reuse the exact same
 * number for the rate it fires attempts, so it lives here rather than being
 * repeated at each call site.
 */

import { defineChain } from "viem";

/**
 * Load the repo-root .env, letting anything already in the shell win.
 *
 * Runs at module load, not from main(). An earlier version called this from
 * main() while chain.ts resolved the RPC URL at import time — so the .env value
 * was read after it was needed and quietly ignored. It happened to work because
 * the fallback URL was the same string, which is the kind of accident that
 * holds until the day you point the agent at a different chain.
 *
 * Shell-first ordering matters for the same reason: the local test harness
 * overrides ARC_RPC_URL and REGISTRY to run against anvil, and .env must not
 * stamp Arc's values back over them.
 */
function loadEnvOnce(): void {
  const fromShell = { ...process.env };
  try {
    process.loadEnvFile(new URL("../../.env", import.meta.url).pathname);
  } catch {
    // Absent or already exported. requireEnv() gives a better message than a
    // stack trace would.
  }
  for (const [k, v] of Object.entries(fromShell)) {
    if (v !== undefined) process.env[k] = v;
  }
}

loadEnvOnce();

/** Kept as a no-op export so callers can be explicit about ordering. */
export function loadEnv(): void {}

export function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v || v.trim() === "") {
    throw new Error(
      `missing ${name}. Expected it in the repo-root .env file. ` +
        `See .env.example for the shape.`,
    );
  }
  return v.trim();
}

/**
 * The ONLY address the agent is allowed to know in advance.
 *
 * Everything else — which contracts to attack, what function to call, how many
 * bounties exist — is read from this contract at runtime. That is the line
 * between an agent and a script following orders, and it is the thing the
 * Agentic Economy track is looking at.
 */
export const REGISTRY_ADDRESS = (process.env.REGISTRY ??
  "0xbBd50574b55CE9F7453882E2d3361b393AD3F99C") as `0x${string}`;

/** Overridable so the scenario harness can point the agent at a local chain. */
export const ARC_CHAIN_ID = Number(process.env.CHAIN_ID ?? 5042002);

/** Resolved once, after .env is loaded, so an override actually takes effect. */
export const RPC_URL =
  process.env.ARC_RPC_URL?.trim() || "https://rpc.testnet.arc.network";

export const arcTestnet = defineChain({
  id: ARC_CHAIN_ID,
  name: process.env.CHAIN_NAME ?? "Arc Testnet",
  // Native gas on Arc is USDC with 18 decimals, not the 6 the ERC-20 form uses.
  // Getting this wrong makes every amount the agent prints wrong by 10^12.
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: {
    default: { name: "Arcscan", url: "https://testnet.arcscan.app" },
  },
});

/**
 * Minimum gap between JSON-RPC calls, in milliseconds.
 *
 * Measured on Day 1 (docs/measurements/day1-report.md): `eth_call` on Arc's
 * public RPC is throttled at roughly 2.2 requests per second, while
 * eth_blockNumber, eth_getBalance and eth_estimateGas are not. A cost-based
 * explanation was tested and disproved — the limit tracks the method.
 *
 * 700ms is about 1.43 req/s, a deliberate ~35% margin under that ceiling. Every
 * read the agent makes is an eth_call, so this applies to all of them.
 *
 * The margin is not sufficient on its own, and that is a measured statement
 * rather than a caution. Three consecutive scans at this interval were
 * throttled 1, then 2, then 4 times — the same 22 calls each run, the rejections
 * climbing. So Arc's limit behaves like a budget that drains over a window, not
 * a fixed rate: the 2.2/s figure was measured on a full bucket, and repeated
 * runs do not get it.
 *
 * The retry in chain.ts is therefore the real defence and not a fallback; it
 * absorbed every one of those rejections, and all three scans still returned
 * the correct answer with zero errors. Raising this number reduces how often
 * the retry is needed. It does not remove the need for it.
 */
export const RPC_MIN_INTERVAL_MS = 700;

/** Give up on a single RPC call after this long. */
export const RPC_TIMEOUT_MS = 30_000;

/** Retries for a call that fails with a rate-limit error. */
export const RPC_RETRY_ATTEMPTS = 3;
export const RPC_RETRY_BACKOFF_MS = 2_000;
