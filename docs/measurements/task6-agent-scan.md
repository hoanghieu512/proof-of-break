# Task 6 — what a scan of the board costs

Measured against the live Registry on Arc Testnet, 2026-08-04, with six bounties
open. Regenerate with `cd agent && npm run scan` and read the block at the end
of the output.

## Per scan

| | |
|---|---|
| RPC calls | **22** — 21 `eth_call`, 1 `eth_getBalance` |
| Wall clock | 16.8 – 23.2 s |
| Configured pace | one call per 700 ms (~1.43/s) |
| Observed rate | 0.95 – 1.31 calls/s |
| Errors reaching the agent | **0** |

### Where the 22 calls go

| Calls | What for |
|---:|---|
| 1 | `eth_getBalance` — the agent's own wallet |
| 1 | `totalEscrowed()` |
| 1 | `bountyCount()` |
| 6 | `getBounty(i)`, one per bounty, paid ones included so they can be reported |
| 6 | `checker.target()`, confirming each checker watches what its bounty claims |
| 6 | `checker.checkInvariant()`, the feasibility test |
| 1 | `checker.description()`, for the chosen bounty only |

That is `3n + 4` for `n` bounties. Fetching the description only for the winner
rather than for all six saves five calls, which at this pace is 3.5 seconds.

## The throttling result, which was not what the Day 1 figure predicted

Three scans, run back to back with a 12 second gap:

| Run | Calls | Elapsed | Observed rate | Throttled | Errors |
|---|---:|---:|---:|---:|---:|
| 1 | 22 | 16.8 s | 1.31/s | 1 | 0 |
| 2 | 22 | 18.4 s | 1.19/s | 2 | 0 |
| 3 | 22 | 23.2 s | 0.95/s | 4 | 0 |

Same work every time, and the rejections climb: 1, 2, 4.

Day 1 measured `eth_call` throttling at roughly 2.2 requests per second. The
agent runs at 1.43/s — a 35% margin — and is still throttled, increasingly so on
each repeat.

**So Arc's limit is not a fixed rate.** It behaves like a budget that drains over
a window and refills slowly. The 2.2/s figure was taken on a full bucket; three
scans inside a minute do not get one. The Day 1 number is not wrong, it is just
an instantaneous ceiling rather than a sustainable one, and the difference only
shows up under repeated use.

**Nothing was misread as a result.** Errors reaching the agent stayed at 0
across all three runs, and all three selected the same bounty. The retry in
`chain.ts` — three attempts with linear backoff, on the three rejection codes Arc
actually returns — absorbed every rejection. What throttling costs here is time,
not correctness.

That distinction matters because of what a misread would mean. A throttled
`checkInvariant()` call, if treated as a failure, would look like "this checker
will not answer" and the agent would skip a perfectly good bounty. Retrying is
what stops a network hiccup from being mistaken for a verdict.

## What this implies for Task 7

Task 7 fires attempts in a loop and reuses `RPC_MIN_INTERVAL_MS` for the firing
rate, so this is the constraint it inherits.

- **Budget the reads, not just the writes.** Each attempt costs at least one
  `eth_sendRawTransaction` plus a receipt poll. Receipt polling is the thing to
  watch — a tight poll loop is exactly the pattern that drains the budget.
- **Keep the retry.** It is doing the load-bearing work, not the interval.
- **Do not conclude a bounty is dead from one failed read.** The same rule that
  applies to the checker applies to the receipt.
- **The atomic design helps here by accident.** Because check→act→check happens
  on-chain inside one transaction, the agent does not need to read state between
  attempts. An agent that polled the target after every attempt would spend
  three or four times the read budget for the same work.

Raising `RPC_MIN_INTERVAL_MS` reduces how often the retry fires. It does not
remove the need for it, and the number was left at 700 ms rather than tuned
upward on a guess.
