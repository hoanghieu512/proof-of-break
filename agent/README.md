# Agent

Reads the Proof of Break bounty board on Arc Testnet, decides which bounty is
worth attacking, and says why.

**It does not attack anything yet.** Generating inputs and firing them is Task 7.

## Run it

```bash
npm install
```

```bash
npm run scan
```

Needs `AGENT_PRIVATE_KEY` in the repo-root `.env`. Nothing else is required —
the Registry address has a default, and everything past that is read from the
chain.

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

## Tests

```bash
./scripts/test-agent-scenarios.sh
```

Builds a board on a local chain containing every rejection reason, plus an empty
board, and checks the agent reaches the right conclusion for each. Run from the
repo root.

The rejection paths cannot be tested against Arc without destroying real
bounties — proving "already broken" is rejected means breaking one permanently.

## Layout

```
src/config.ts      every knob, including the one pacing value Task 7 reuses
src/chain.ts       paced, counted, retrying RPC transport + the agent's wallet
src/registry.ts    reading the board and asking checkers questions
src/signature.ts   turning "deposit(uint256)" into a plan
src/scan.ts        filter, rank, choose
src/index.ts       the report
```
