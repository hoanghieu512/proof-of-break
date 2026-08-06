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
 * Minimum gap between JSON-RPC calls, in milliseconds. Applies to every call —
 * reads and, in Task 7, the sends too.
 *
 * 700ms is 1.43 req/s. That number is now backed by a proper sustained-rate
 * measurement, not the Day 1 burst figure (docs/measurements/task7-sustained-rate.md).
 *
 * WHAT WAS MEASURED. eth_call — the one method Arc throttles — was driven at a
 * fixed pace for four minutes at each of 1.5, 1.0 and 0.6 req/s, with rejections
 * bucketed per 30s to catch escalation. All three were completely flat: zero
 * throttling, start to finish. A fourth run at 1.5 req/s with retries enabled
 * was also flat, so the "do retries drain the same budget" question is moot at
 * this rate — nothing throttles, so nothing is retried.
 *
 * HOW THIS SITS WITH THE EARLIER READINGS. Day 1 saw eth_call reject at ~2.2/s,
 * and Task 6 saw three back-to-back scans throttle 1→2→4 at this very interval.
 * Neither reproduced under sustained measurement. The most likely reason is that
 * both earlier readings started on a partially drained budget — Task 6's scans
 * came straight after a burst of verify/scan traffic, with no cooldown. The
 * throttling is real but transient; the sustainable rate is comfortably ≥1.5/s.
 *
 * So 1.43 req/s sits just under the measured flat ceiling of 1.5, with margin.
 * The retry in chain.ts stays as defence against the transient throttling the
 * earlier runs saw, but at this pace it is rarely triggered.
 */
export const RPC_MIN_INTERVAL_MS = 700;

/** Give up on a single RPC call after this long. */
export const RPC_TIMEOUT_MS = 30_000;

/** Retries for a call that fails with a rate-limit error. */
export const RPC_RETRY_ATTEMPTS = 3;
export const RPC_RETRY_BACKOFF_MS = 2_000;

// -------------------------------------------------------------- attack ----

/**
 * Input generation strategy, chosen at the top level — never by the agent.
 *
 *   boundary-first  the QA strategy: try the boundary list, then random
 *   random-only     the control: random from the start
 *
 * Two modes exist to reproduce, on camera, the head-to-head the project rests
 * on. Set with STRATEGY=random-only in the environment.
 */
export const STRATEGY: "boundary-first" | "random-only" =
  process.env.STRATEGY === "random-only" ? "random-only" : "boundary-first";

/**
 * Hard cap on attempts in a single run, so a run cannot go forever.
 *
 * Boundary-first reaches the demo bug on probe 6, so the cap only matters for
 * random-only, and random-only against a live chain is not how the control is
 * meant to be run (see scripts/compare-strategies.sh — it measures the control
 * offline). 64 is comfortably past the 13-entry boundary list.
 */
export const ATTACK_MAX_ATTEMPTS = Number(process.env.ATTACK_MAX_ATTEMPTS ?? 64);
