/**
 * The attack loop: generate, fire, stop when something breaks.
 *
 * It stops on the first successful break by design (the task's requirement). It
 * does not roll on to the next bounty — a fresh run does that, and the scan's
 * filtering in Task 6 will then skip the bounty just claimed.
 */

import type { Hash } from "viem";
import { fireAttempt, targetCalldata, type AttemptOutcome } from "./attack.js";
import { publicClient } from "./chain.js";
import { candidates, type Candidate, type Strategy } from "./generator.js";
import type { Bounty } from "./registry.js";
import type { ParsedSignature } from "./signature.js";

export interface AttemptRecord {
  probe: number;
  candidate: Candidate;
  outcome: AttemptOutcome;
}

export interface LoopResult {
  broke: boolean;
  winningProbe?: number;
  winningValue?: bigint;
  winningHash?: Hash;
  reward?: bigint;
  attempts: number;
  boundaryAttempts: number;
  randomAttempts: number;
}

export interface LoopOptions {
  strategy: Strategy;
  /** Hard cap so a run cannot go forever. */
  maxAttempts: number;
  account: `0x${string}`;
  /** Called before each attempt, for the on-camera log. */
  onProbe?: (probe: number, candidate: Candidate) => void;
  /** Called after each attempt with its result. */
  onResult?: (record: AttemptRecord) => void;
}

export async function attackLoop(
  bounty: Bounty,
  signature: ParsedSignature,
  opts: LoopOptions,
): Promise<LoopResult> {
  let probe = 0;
  let boundaryAttempts = 0;
  let randomAttempts = 0;

  // One nonce, advanced only when a nonce is actually consumed on-chain. A
  // re-broadcast of a not-yet-mined transaction reuses the same value.
  let nonce = await publicClient.getTransactionCount({
    address: opts.account,
    blockTag: "latest",
  });

  const gen = candidates(signature, opts.strategy);

  while (probe < opts.maxAttempts) {
    const candidate = gen.next().value as Candidate;
    probe++;
    if (candidate.source === "boundary") boundaryAttempts++;
    else randomAttempts++;

    opts.onProbe?.(probe, candidate);

    const callData = targetCalldata(bounty.selector, candidate.argsEncoded);

    // Re-broadcast the SAME signed transaction while it will not mine. This is
    // idempotent by nonce; it is not the forbidden "build a new tx and try
    // again". A small cap stops an unreachable RPC from hanging the run.
    let outcome: AttemptOutcome | undefined;
    for (let rebroadcast = 0; rebroadcast < 3; rebroadcast++) {
      outcome = await fireAttempt(bounty, callData, nonce);
      if (outcome.kind !== "not-mined") break;
    }
    outcome = outcome!;

    opts.onResult?.({ probe, candidate, outcome });

    if (outcome.kind === "broke") {
      return {
        broke: true,
        winningProbe: probe,
        winningValue: candidate.values[0],
        winningHash: outcome.hash,
        reward: outcome.reward,
        attempts: probe,
        boundaryAttempts,
        randomAttempts,
      };
    }

    // "would-revert" spent no gas and consumed no nonce — do not advance it.
    // "miss" mined a transaction, so the nonce moved on.
    if (outcome.kind === "miss") nonce++;
    // "not-mined" after re-broadcasts: the nonce is still unconsumed; leave it,
    // and move to the next value (the stuck transaction, if it ever mines, is a
    // harmless non-breaking deposit).
    if (outcome.kind === "not-mined") {
      // Re-read the nonce in case it settled during the wait.
      nonce = await publicClient.getTransactionCount({
        address: opts.account,
        blockTag: "latest",
      });
    }
  }

  return {
    broke: false,
    attempts: probe,
    boundaryAttempts,
    randomAttempts,
  };
}
