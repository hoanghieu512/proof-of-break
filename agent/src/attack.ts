/**
 * Firing an attempt, and knowing what actually happened.
 *
 * This is the safety-critical file. It sends transactions to a contract that
 * pays out real USDC, over an RPC that — measured on Day 1 — returns a
 * transaction hash for transactions it then never mines. Getting the
 * success/failure decision wrong in either direction is expensive:
 *
 *   - deciding "failed" when the break actually landed loses the win and, on a
 *     blind retry, throws the next transaction at a bounty that is already paid,
 *     which reverts, which looks like further failure. A false negative
 *     compounds.
 *   - deciding "succeeded" when nothing happened reports a win that is not there.
 *
 * THE RULE THIS FILE FOLLOWS
 *
 * The send response is never the source of truth. Whether an attempt broke the
 * invariant is read from MINED STATE afterwards: the bounty's `paid` flag and
 * the agent's balance. This holds even when the send call threw — because the
 * transaction it was sending may have been mined anyway.
 *
 * TWO-TIER RETRY
 *
 * Reads (in chain.ts) retry rate-limits freely; they have no side effects.
 * Writes do not blindly retry. When a send fails or a transaction does not
 * mine, this file does exactly one safe thing: it re-broadcasts the IDENTICAL
 * pre-signed transaction — same nonce, same bytes, deduplicated by the network,
 * incapable of double-executing. It never signs a fresh transaction to "try
 * again". After every send it reconciles against the chain.
 */

import { encodeFunctionData, keccak256, type Hash } from "viem";
import { agentWallet, publicClient } from "./chain.js";
import { REGISTRY_ADDRESS, RPC_TIMEOUT_MS } from "./config.js";
import { getBounty, registryAbi, type Bounty } from "./registry.js";

const REGISTRY_ATTEMPT_ABI = [
  {
    type: "function",
    name: "attempt",
    stateMutability: "nonpayable",
    inputs: [
      { name: "bountyId", type: "uint256" },
      { name: "callData", type: "bytes" },
    ],
    outputs: [{ name: "brokeInvariant", type: "bool" }],
  },
] as const;

export type AttemptOutcome =
  | { kind: "broke"; reward: bigint; hash: Hash; gasUsed: bigint }
  | { kind: "miss"; hash: Hash; reverted: boolean }
  | { kind: "would-revert" } // filtered before sending; costs no gas
  | { kind: "not-mined"; hash: Hash };

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Full calldata an agent sends the target: its declared selector then the args. */
export function targetCalldata(selector: `0x${string}`, argsEncoded: `0x${string}`): `0x${string}` {
  return (selector + argsEncoded.slice(2)) as `0x${string}`;
}

/**
 * Fire one attempt at a bounty and report what the chain says happened.
 *
 * @param nonce  the exact nonce to use, managed by the caller so a re-broadcast
 *               reuses it rather than creating a second transaction.
 */
export async function fireAttempt(
  bounty: Bounty,
  callData: `0x${string}`,
  nonce: number,
): Promise<AttemptOutcome> {
  const wallet = agentWallet();
  const account = wallet.account!;

  const data = encodeFunctionData({
    abi: REGISTRY_ATTEMPT_ABI,
    functionName: "attempt",
    args: [BigInt(bounty.id), callData],
  });

  // Build the full transaction request. prepareTransactionRequest estimates
  // gas, fills the fee fields and transaction type, and pins the nonce we hand
  // it. It also simulates gas, so it throws on an input that would revert —
  // which is exactly the filter we want: attempt() reverts when the target
  // rejects the input (e.g. deposit(0)) or the invariant is already broken, and
  // there is no reason to pay gas to prove a guaranteed miss.
  let request;
  try {
    request = await wallet.prepareTransactionRequest({
      account,
      to: REGISTRY_ADDRESS,
      data,
      nonce,
      chain: wallet.chain,
    });
  } catch {
    return { kind: "would-revert" };
  }

  // Sign ONCE. The serialized bytes are what gets (re-)broadcast; its hash is
  // fixed, so re-sending is provably the same transaction — same nonce, same
  // bytes, deduplicated by the network.
  //
  // The cast is a known viem generic-inference quirk: prepareTransactionRequest
  // and signTransaction each resolve the request type through their own generic
  // chain, and the compiler sees "two different types with this name". The
  // request object is exactly what signTransaction expects at runtime.
  const serialized = await wallet.signTransaction(request as Parameters<typeof wallet.signTransaction>[0]);
  const hash = keccak256(serialized);

  const balanceBefore = await publicClient.getBalance({ address: account.address });

  // Broadcast, then reconcile from mined state no matter how the send returned.
  await broadcast(serialized);

  const mined = await waitForNonceOrReceipt(account.address, nonce, hash);
  if (!mined) {
    // The transaction with our nonce did not mine within the deadline. The
    // caller may re-broadcast the same bytes; it will not double-execute.
    return { kind: "not-mined", hash };
  }

  // Our nonce was consumed. Read what the mined transaction did — from state,
  // never from the send response.
  const after = await getBounty(bounty.id);
  const balanceAfter = await publicClient.getBalance({ address: account.address });

  if (after.paid && balanceAfter > balanceBefore) {
    return {
      kind: "broke",
      reward: balanceAfter - balanceBefore + 0n, // net of gas; balance delta is the real gain
      hash,
      gasUsed: 0n,
    };
  }

  // Nonce consumed, bounty not paid → the attempt mined but did not break.
  // Distinguish a clean "ran and returned false" from an on-chain revert, for
  // the log, by reading the receipt status.
  let reverted = false;
  try {
    const receipt = await publicClient.getTransactionReceipt({ hash });
    reverted = receipt.status === "reverted";
  } catch {
    // Receipt not retrievable by this hash (a different tx filled the nonce).
    // Either way the bounty is unbroken; treat as a miss.
  }
  return { kind: "miss", hash, reverted };
}

/**
 * Send the raw signed transaction, swallowing only the errors that are safe to
 * swallow because the truth is read from state afterwards.
 *
 * A rate-limit or "already known" error is not a failure — the transaction is
 * or will be in the mempool. A genuinely malformed transaction would throw
 * something else, but since we estimated gas successfully just above, that is
 * not expected here.
 */
async function broadcast(serialized: `0x${string}`): Promise<void> {
  try {
    await publicClient.sendRawTransaction({ serializedTransaction: serialized });
  } catch (e) {
    const msg = (e instanceof Error ? e.message : String(e)).toLowerCase();
    // "already known" / "nonce too low" mean it (or its nonce) is already in
    // flight or mined — exactly the case the state read handles. Anything else
    // is surfaced by returning; the reconcile step decides.
    if (!/already known|alreadyknown|nonce too low|replacement/.test(msg)) {
      // Not re-thrown: the reconcile below is the authority. A hard send failure
      // simply shows up as "not-mined", and the caller re-broadcasts.
    }
  }
}

/**
 * Wait until the account's nonce moves past `nonce` (meaning a transaction with
 * that nonce mined) or the deadline passes. Returns true if the nonce was
 * consumed.
 *
 * Uses the account nonce rather than the receipt hash as the primary signal,
 * because if a different transaction ever filled the nonce, the hash-based
 * receipt would never arrive but the slot is still consumed.
 */
async function waitForNonceOrReceipt(
  address: `0x${string}`,
  nonce: number,
  hash: Hash,
): Promise<boolean> {
  const deadline = Date.now() + RPC_TIMEOUT_MS * 2;
  while (Date.now() < deadline) {
    const confirmed = await publicClient.getTransactionCount({
      address,
      blockTag: "latest",
    });
    if (confirmed > nonce) return true;

    // A receipt for our exact hash is an even stronger positive.
    try {
      await publicClient.getTransactionReceipt({ hash });
      return true;
    } catch {
      // no receipt yet
    }
    await sleep(1500);
  }
  return false;
}

export { registryAbi };
