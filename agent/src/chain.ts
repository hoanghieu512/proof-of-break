/**
 * The connection to Arc, with every RPC call serialised, paced and counted.
 *
 * Written by hand rather than using viem's stock http transport for one reason:
 * Arc throttles `eth_call` at about 2.2 requests per second, and every read the
 * agent makes is an eth_call. A transport that fires requests as fast as the
 * code asks will get a portion of them rejected, and the agent will conclude a
 * bounty is broken when really the question never arrived.
 *
 * So requests go through a single-file queue with a minimum gap between them,
 * and the same object counts them. Task 7 sends transactions through this too.
 */

import {
  createPublicClient,
  createWalletClient,
  custom,
  type PublicClient,
  type WalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import {
  arcTestnet,
  RPC_MIN_INTERVAL_MS,
  RPC_RETRY_ATTEMPTS,
  RPC_RETRY_BACKOFF_MS,
  RPC_TIMEOUT_MS,
  RPC_URL,
  requireEnv,
} from "./config.js";

export interface RpcStats {
  calls: number;
  byMethod: Record<string, number>;
  throttled: number;
  errors: number;
  errorsByMethod: Record<string, number>;
  startedAt: number;
}

export const stats: RpcStats = {
  calls: 0,
  byMethod: {},
  throttled: 0,
  errors: 0,
  errorsByMethod: {},
  startedAt: Date.now(),
};

/**
 * A thrown result only counts as a "real error" for methods the agent depends
 * on being answered. Everything else is either an expected answer or viem's own
 * fallback probing, and counting it would make a clean run look alarming:
 *
 *   eth_estimateGas         reverts are the would-revert filter working — how
 *                           the agent learns an input (deposit(0), an already-
 *                           broken bounty) is a guaranteed miss, before any gas.
 *   eth_fillTransaction     viem probes this while building a transaction; the
 *                           node rejects it and viem falls back. The transaction
 *                           still builds — every run here proves it.
 *   eth_getTransactionReceipt   polled before a transaction has mined; a miss is
 *                           "not yet", not a failure.
 *
 * An error on eth_sendRawTransaction or a plain read the agent made itself is
 * real and is counted.
 */
const BENIGN_ERROR_METHODS = new Set([
  "eth_estimateGas",
  "eth_fillTransaction",
  "eth_getTransactionReceipt",
]);

export function elapsedSeconds(): number {
  return (Date.now() - stats.startedAt) / 1000;
}

export function observedRate(): number {
  const s = elapsedSeconds();
  return s > 0 ? stats.calls / s : 0;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Serialises everything and enforces the minimum gap. */
let chain: Promise<unknown> = Promise.resolve();
let lastCallAt = 0;

function schedule<T>(fn: () => Promise<T>): Promise<T> {
  const run = chain.then(async () => {
    const wait = RPC_MIN_INTERVAL_MS - (Date.now() - lastCallAt);
    if (wait > 0) await sleep(wait);
    lastCallAt = Date.now();
    return fn();
  });
  // Keep the queue alive even when a call rejects.
  chain = run.then(
    () => undefined,
    () => undefined,
  );
  return run as Promise<T>;
}

/** True for the three rejection shapes Arc's public RPC actually returns. */
function isRateLimit(status: number, code?: number): boolean {
  return status === 429 || code === -32011 || code === -32005 || code === -32003;
}

async function rpc(method: string, params: unknown[]): Promise<unknown> {
  for (let attempt = 0; ; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), RPC_TIMEOUT_MS);
    try {
      const res = await fetch(RPC_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          // Identify honestly. Arc returns 403 to the default Python agent
          // string; node's default is fine, but being explicit costs nothing
          // and makes the traffic recognisable in a log.
          "User-Agent": "proof-of-break-agent/0.6.0",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: controller.signal,
      });

      const body = (await res.json().catch(() => null)) as
        | { result?: unknown; error?: { code?: number; message?: string } }
        | null;

      if (!res.ok || body?.error) {
        const code = body?.error?.code;
        if (isRateLimit(res.status, code) && attempt < RPC_RETRY_ATTEMPTS) {
          stats.throttled++;
          await sleep(RPC_RETRY_BACKOFF_MS * (attempt + 1));
          continue;
        }
        if (isRateLimit(res.status, code)) stats.throttled++;
        // Anything else — including a reverted eth_call — is a real answer
        // about the chain and must reach the caller intact.
        const err = new Error(
          body?.error?.message ?? `HTTP ${res.status} from ${method}`,
        ) as Error & { code?: number };
        err.code = code;
        throw err;
      }

      return body?.result;
    } finally {
      clearTimeout(timer);
    }
  }
}

const countingTransport = custom({
  async request({ method, params }) {
    stats.calls++;
    stats.byMethod[method] = (stats.byMethod[method] ?? 0) + 1;
    try {
      return await schedule(() => rpc(method, (params as unknown[]) ?? []));
    } catch (e) {
      stats.errorsByMethod[method] = (stats.errorsByMethod[method] ?? 0) + 1;
      // A reverting estimateGas is the revert-filter working, not a fault.
      if (!BENIGN_ERROR_METHODS.has(method)) stats.errors++;
      throw e;
    }
  },
});

export const publicClient: PublicClient = createPublicClient({
  chain: arcTestnet,
  transport: countingTransport,
});

/**
 * The agent's own wallet.
 *
 * Separate from the deployer on purpose. If the wallet that funded a bounty
 * were also the one claiming it, the money would move from one pocket to the
 * other and prove nothing. In this task the account only identifies the agent;
 * Task 7 is where it signs.
 */
export function agentAccount() {
  const key = requireEnv("AGENT_PRIVATE_KEY");
  const normalised = (key.startsWith("0x") ? key : `0x${key}`) as `0x${string}`;
  return privateKeyToAccount(normalised);
}

/**
 * A wallet client for the agent, on the same paced transport.
 *
 * Signing and sending go through the same single-file queue as reads, so the
 * pacing that protects reads also protects the send. Note the queue's built-in
 * retry re-POSTs the identical bytes, which is safe here: a resend of the same
 * signed transaction is idempotent by nonce and cannot double-execute. The
 * dangerous kind of retry — building a fresh transaction after a network error
 * — is never done by the transport; that decision is left to attack.ts, which
 * decides from mined state instead.
 */
export function agentWallet(): WalletClient {
  return createWalletClient({
    account: agentAccount(),
    chain: arcTestnet,
    transport: countingTransport,
  });
}
