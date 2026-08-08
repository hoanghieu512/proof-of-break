/**
 * The agent's run log — OFF-CHAIN data.
 *
 * READ THIS BEFORE ADDING ANYTHING HERE.
 *
 * Everything in this file is a record of what the agent printed during one run
 * on 2026-08-06. It is NOT read from the chain and cannot be. "It broke on the
 * 6th probe" is not a fact any contract stores; the chain only knows that one
 * transaction from the agent's wallet claimed bounty #4.
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
  /** RPC statistics the agent printed. Off-chain. */
  rpcCalls: number;
  elapsedSeconds: number;
  throttled: number;
  realErrors: number;
  strategy: string;
}

export const RUN_LOG: RunLog = {
  when: "2026-08-06",
  chosenBountyId: 4,
  chosenReward: "1.5",
  whyChosen:
    "it paid the most of the 6 bounties that survived the feasibility checks (next best was #3)",
  winningProbe: 6,
  winningValue: "1000000000000000000",
  winningValueLabel: "1e18 — one whole unit at 18 decimals",
  txHash:
    "0xcd29a7592a9fd5e31a37eba0b133961eecaee1e80bcee0fa8b3554c75c66126b",
  agentAddress: "0xd3e23bA15A06B1DF14eF6daC73cF76DC9e888888",
  balanceBefore: "41",
  balanceAfter: "42.490530",
  netChange: "+1.49",
  probesBefore: [
    { probe: 1, value: "0", outcome: "target rejects this input — no gas spent" },
    { probe: 2, value: "1", outcome: "mined, invariant held" },
    { probe: 3, value: "2", outcome: "mined, invariant held" },
    { probe: 4, value: "1000000", outcome: "mined, invariant held" },
    { probe: 5, value: "1000000000", outcome: "mined, invariant held" },
  ],
  rpcCalls: 67,
  elapsedSeconds: 46.5,
  throttled: 0,
  realErrors: 0,
  strategy: "boundary-first",
};
