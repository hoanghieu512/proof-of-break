/**
 * Scan the board, throw out what cannot be won, pick the best of the rest.
 *
 * Order matters and is deliberate: feasibility first, money second. Sorting by
 * reward and then discovering the richest bounty is unwinnable would waste the
 * whole run. A bounty is only compared on value once it is known to be worth
 * comparing at all.
 */

import { askChecker, checkerWatches, type Bounty, readBoard } from "./registry.js";
import { parseSignature, type ParsedSignature } from "./signature.js";

export type Rejection =
  | "already-paid"
  | "invariant-already-broken"
  | "checker-unusable"
  | "checker-watches-wrong-target"
  | "signature-unusable";

export interface Assessment {
  bounty: Bounty;
  signature: ParsedSignature;
  viable: boolean;
  rejection?: Rejection;
  detail?: string;
}

export interface ScanResult {
  assessments: Assessment[];
  chosen?: Assessment;
  reason: string;
}

const REJECTION_TEXT: Record<Rejection, string> = {
  "already-paid": "already claimed by somebody else; a bounty pays at most once",
  "invariant-already-broken":
    "invariant is already false, so no action can produce the intact→broken transition a payout requires",
  "checker-unusable": "checker will not answer, so no claim could ever be judged",
  "checker-watches-wrong-target":
    "checker watches a different contract than the bounty declares",
  "signature-unusable": "cannot generate arguments for this function signature",
};

export function explainRejection(r: Rejection): string {
  return REJECTION_TEXT[r];
}

export async function scanBoard(
  onProgress?: (a: Assessment) => void,
): Promise<ScanResult> {
  const board = await readBoard();
  const assessments: Assessment[] = [];

  for (const bounty of board) {
    const signature = parseSignature(bounty.functionSignature);
    const assess = (rejection?: Rejection, detail?: string): Assessment => ({
      bounty,
      signature,
      viable: !rejection,
      rejection,
      detail,
    });

    // Cheapest disqualifiers first — these cost no RPC calls at all.
    if (bounty.paid) {
      const a = assess("already-paid");
      assessments.push(a);
      onProgress?.(a);
      continue;
    }

    if (!signature.supported) {
      const a = assess(
        "signature-unusable",
        signature.unsupported.join(", ") || "no arguments to vary",
      );
      assessments.push(a);
      onProgress?.(a);
      continue;
    }

    // The Registry refuses a mismatch at open time, so this should always pass.
    // Verifying anyway costs one call and the agent is about to spend gas on
    // the strength of it.
    const watched = await checkerWatches(bounty.checker);
    if (watched === null) {
      const a = assess("checker-unusable", "target() reverted");
      assessments.push(a);
      onProgress?.(a);
      continue;
    }
    if (watched.toLowerCase() !== bounty.target.toLowerCase()) {
      const a = assess("checker-watches-wrong-target", `checker watches ${watched}`);
      assessments.push(a);
      onProgress?.(a);
      continue;
    }

    const verdict = await askChecker(bounty.checker);
    if (verdict.kind === "unusable") {
      const a = assess("checker-unusable", verdict.reason);
      assessments.push(a);
      onProgress?.(a);
      continue;
    }
    if (verdict.kind === "broken") {
      const a = assess("invariant-already-broken");
      assessments.push(a);
      onProgress?.(a);
      continue;
    }

    const a = assess();
    assessments.push(a);
    onProgress?.(a);
  }

  const viable = assessments.filter((a) => a.viable);

  if (viable.length === 0) {
    return {
      assessments,
      reason:
        board.length === 0
          ? "the board is empty; nobody has opened a bounty on this Registry"
          : "every bounty on the board failed the feasibility checks",
    };
  }

  // Only now does money enter the decision.
  const ranked = [...viable].sort((x, y) =>
    y.bounty.reward === x.bounty.reward
      ? x.bounty.id - y.bounty.id // stable: prefer the older bounty on a tie
      : y.bounty.reward > x.bounty.reward
        ? 1
        : -1,
  );

  const chosen = ranked[0];
  const runnerUp = ranked[1];

  const reason =
    runnerUp === undefined
      ? `it is the only bounty that survived the feasibility checks`
      : `it pays the most of the ${viable.length} bounties that survived the ` +
        `feasibility checks (next best is #${runnerUp.bounty.id})`;

  return { assessments, chosen, reason };
}
