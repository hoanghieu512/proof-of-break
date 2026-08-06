# Agent

Reads the Proof of Break bounty board on Arc Testnet, picks a bounty, fuzzes it
boundary-value-first, fires each attempt through the Registry, and collects the
USDC when one breaks. No human in the loop.

## Run it

```bash
npm install
```

The whole thing — scan, choose, fuzz, claim:

```bash
npm run attack
```

Or just the scan-and-choose half (Task 6), no transactions sent:

```bash
npm run scan
```

Needs `AGENT_PRIVATE_KEY` in the repo-root `.env`, funded with a little USDC for
gas. Nothing else is required — the Registry address has a default, and
everything past that is read from the chain.

Exit codes: `0` broke a bounty and got paid · `3` scanned, nothing worth
attacking · `4` attacked, hit the cap without breaking · `1` could not run.

## The two strategies

The agent runs one of two input strategies, chosen by environment, never by the
agent itself:

```bash
npm run attack                    # boundary-first (default)
STRATEGY=random-only npm run attack
```

They exist to reproduce the head-to-head the pitch rests on: boundary search
finds the planted bug on the 6th probe, random search effectively never does.
Same agent, same generator, same total ignorance of the target — only the
strategy differs. Run the comparison, offline on a local chain, with:

```bash
./scripts/compare-strategies.sh
```

Exit codes: `0` picked a bounty · `3` scanned but nothing worth attacking ·
`1` could not run.

## What "autonomous" means here, concretely

The agent is given exactly one piece of information: **the Registry address.**

It is not told which contracts exist, what functions they expose, how many
bounties there are, or what any of them pay. It reads all of that at runtime,
which is why `grep` over `src/` finds precisely one address literal and no
function names.

That is the line between an agent and a script following orders, and it is what
the Agentic Economy track is looking at.

## How it decides

Feasibility first, money second. The order is deliberate: sorting by reward and
*then* discovering the richest bounty is unwinnable would waste the run.

A bounty is thrown out if:

| Reason | Why it cannot be won |
|---|---|
| already paid | a bounty pays at most once |
| invariant already broken | no action can produce the intact→broken transition a payout requires |
| checker will not answer | nothing could ever judge a claim |
| checker watches a different contract | the bounty's own claim about itself is false |
| signature not generatable | the agent cannot produce arguments of those types |

The first two are reported as different things on purpose. Both mean "do not
attack", but one says somebody already broke the target and the other says the
referee is unreachable — collapsing them would hide which.

Only what survives gets sorted by reward. Ties go to the lower id, so the
decision is reproducible.

## Working out what to generate

A bounty declares one function, written the way Solidity writes it:
`deposit(uint256)`. That string is the whole briefing.

`signature.ts` parses it into argument types, decides whether it can produce
values of those types, and derives the 4-byte selector locally. That derived
selector is compared against the one the Registry stored — if a bounty's
signature string and selector disagree, something is wrong with the bounty and
the agent says so.

## Pacing

Every read is an `eth_call`, and Arc's public RPC throttles that method at about
**2.2 requests per second** while leaving `eth_blockNumber`, `eth_getBalance` and
`eth_estimateGas` alone (measured on Day 1 —
`docs/measurements/day1-report.md`).

So every RPC call goes through one serialised queue with a minimum gap, set by
`RPC_MIN_INTERVAL_MS` in `src/config.ts`. That is the only place the number
lives, and Task 7 uses the same one for firing attempts.

The transport also counts calls and retries the three rejection codes Arc
actually returns (`-32011`, `-32005`, `-32003`) with backoff, so a throttled read
is retried rather than misread as "this bounty is broken".

## Firing safely — the two-tier retry

Reads and writes are treated completely differently, because they fail
differently.

**Reads** (`eth_call`) have no side effects, so the transport retries a
rate-limited read freely — the identical request, re-sent.

**Writes** are never blindly retried. On Arc a transaction hash coming back does
**not** mean the transaction was mined (measured on Day 1: at burst rate, 29 of
60 accepted, 5 mined). So `attack.ts` never decides success from the send
response. It signs once, broadcasts, and then reads the answer from **mined
state** — the bounty's `paid` flag and the agent's balance. If a send fails or a
transaction does not mine, the one thing it does is re-broadcast the *identical
pre-signed transaction* — same nonce, same bytes, deduplicated by the network,
incapable of double-executing. It never builds a fresh transaction to try again.

This closes a specific trap: if a first send broke the bounty but its response
was lost, a naive retry would hit a now-paid bounty, revert, and be misread as
"I failed". Here the truth is always read from the chain, so a lost response
cannot become a false negative. `scripts/test-attack-scenarios.sh` exercises it.

## Boundary values

`src/boundaries.ts` is the file that matters most, and the one to read for the
QA thinking. It is a generic boundary list for a `uint256` amount — the values a
tester tries first against *any* quantity, before knowing anything about the
contract. It does not and cannot contain the target's actual bug threshold; the
agent has no source for the target. The planted bug sits at `1e18`, which is on
the list because "one whole unit at 18 decimals" is the most common amount in
DeFi, not because anyone told the agent where the bug was. Each value carries a
one-line reason.

## Tests

```bash
./scripts/test-agent-scenarios.sh      # scan/choose paths (Task 6)
./scripts/test-attack-scenarios.sh     # break, get paid, stop, skip-on-rerun
./scripts/compare-strategies.sh        # boundary-first vs random, reproduced offline
```

Each builds a board on a throwaway local chain. The attack and rejection paths
cannot be tested against Arc without destroying real bounties — proving "already
broken" is rejected means breaking one permanently, and each successful attack
spends a real, unrecoverable claim.

## Layout

```
src/config.ts      every knob, including the one pacing value shared by all calls
src/chain.ts       paced, counted, retrying RPC transport + the agent's wallet
src/registry.ts    reading the board and asking checkers questions
src/signature.ts   turning "deposit(uint256)" into a plan
src/boundaries.ts  the annotated boundary value list — the QA showpiece
src/generator.ts   candidate inputs, boundary-first or random-only
src/attack.ts      firing one attempt, deciding success from mined state
src/loop.ts        generate → fire → stop on the first break
src/run.ts         the end-to-end command (npm run attack), written for the camera
src/scan.ts        filter, rank, choose
src/index.ts       the scan-only report (npm run scan)
src/compare-random.ts  the control half of the strategy comparison
```
