/**
 * The agent's run log — OFF-CHAIN data.
 *
 * READ THIS BEFORE ADDING ANYTHING HERE.
 *
 * Everything in this file is a record of what the agent printed during one run
 * on 2026-08-09 — the run that was filmed for the demo video, so that a judge
 * who reads the hash off the screen finds that same hash here. It is NOT read
 * from the chain and cannot be. "It broke on the 6th probe" is not a fact any
 * contract stores; the chain only knows that one transaction from the agent's
 * wallet claimed bounty #8.
 *
 * The agent prints its run statistics and never persists them, so when a run is
 * replaced here, any figure that came only from the console is dropped rather
 * than carried over. A number from a previous run sitting next to this run's
 * transaction hash would be the exact overclaim this file exists to prevent.
 * That is why the run-statistics fields are optional.
 *
 * The page must therefore label this section as run-log data and never blend it
 * into the live board. Every claim here that CAN be checked on chain carries the
 * transaction hash so a reader can go and check it, and the ones that cannot —
 * the probe count, the values tried before the winner — are marked as coming
 * from the log.
 *
 * Mixing measured-on-chain with reported-by-a-program, unlabelled, is exactly
 * the kind of quiet overclaim this project has avoided everywhere else.
 */

export interface RunLog {
  /** When the run happened. */
  when: string;
  /** Which bounty the agent chose, and why. From the agent's own output. */
  chosenBountyId: number;
  chosenReward: string;
  whyChosen: string;
  /** Which probe number broke it. Off-chain: the chain does not record this. */
  winningProbe: number;
  /** The value that broke it. Verifiable: it is in the transaction's calldata. */
  winningValue: string;
  winningValueLabel: string;
  /** On-chain and verifiable. */
  txHash: `0x${string}`;
  agentAddress: `0x${string}`;
  /** Balances the agent printed. Verifiable via the transaction and receipt. */
  balanceBefore: string;
  balanceAfter: string;
  netChange: string;
  /** The probes tried before the winner, in order. Off-chain. */
  probesBefore: { probe: number; value: string; outcome: string }[];
  /**
   * RPC statistics the agent printed. Off-chain and console-only, so these are
   * optional: a run whose console output was not captured omits them, and the
   * page omits the row rather than showing another run's figures.
   */
  rpcCalls?: number;
  elapsedSeconds?: number;
  throttled?: number;
  realErrors?: number;
  strategy: string;
}

export const RUN_LOG: RunLog = {
  when: "2026-08-09",
  chosenBountyId: 8,
  chosenReward: "1.5",
  whyChosen:
    "nothing on the board paid more — three bounties were tied at 1.5 USDC and it took one of them",
  winningProbe: 6,
  winningValue: "1000000000000000000",
  winningValueLabel: "1e18 — one whole unit at 18 decimals",
  txHash:
    "0x475dce0a13ccc4800f5c889abbb0a4f7e9378c497932357536d36fe3c3b0e89a",
  agentAddress: "0xd3e23bA15A06B1DF14eF6daC73cF76DC9e888888",
  // Read back from the chain at blocks 56144105 and 56144106, not from the log.
  balanceBefore: "45.463184",
  balanceAfter: "46.960995",
  netChange: "+1.497811",
  probesBefore: [
    { probe: 1, value: "0", outcome: "target rejects this input — no gas spent" },
    { probe: 2, value: "1", outcome: "mined, invariant held" },
    { probe: 3, value: "2", outcome: "mined, invariant held" },
    { probe: 4, value: "1000000", outcome: "mined, invariant held" },
    { probe: 5, value: "1000000000", outcome: "mined, invariant held" },
  ],
  // Console output of the filmed run was not captured. Left unset on purpose;
  // the previous run's 67 calls / 46.5s do not describe this transaction.
  strategy: "boundary-first",
};
