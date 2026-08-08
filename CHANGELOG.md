# Changelog

## v0.8.0 — 2026-08-06

A read-only web page: the Live Demo Link for CP3.

### Added
- `web/` — Next.js app showing three things: the bounty board read live from the
  Registry, the break an agent already performed, and the boundary value list it
  used. No wallet, no writes, no way to trigger the agent.
- `scripts/sync-boundaries.mjs` — generates `web/src/data/boundaries.json` from
  `agent/src/boundaries.ts`, keeping one source of truth. The build runs it in
  `--check` mode so a drifted copy cannot ship.

### The three constraints, and how each is enforced rather than intended
- **No RPC from the browser.** `web/src/lib/chain.ts` opens with
  `import "server-only"`, so a client component importing it fails the build.
  Verified in a browser: instrumenting setInterval/setTimeout/fetch and leaving
  the page idle for 20s gave zero of each, and the network tab shows no request
  to the RPC.
- **N viewers cost one read.** Measured through a counting proxy: a cold first
  load costs 13 RPC calls, and five further loads cost 0. One refresh click
  costs exactly 13 — one full board read, nothing more.
- **Provenance is labelled.** Three badges — live from chain, from run log,
  source code. Bounty status comes from the Registry; "broke on probe 6" is what
  the agent printed and is marked as such, with the transaction hash for the
  parts that can be checked.

### Verified end to end
Against a local chain: page shows `1 still claimable`, the agent claims it, the
page still shows the old value (nothing polls), a refresh click flips it to
`0 still claimable` and `claimed by an agent`. Against a dead RPC the page still
returns 200 with the full run log and boundary list, plus an explicit error
banner — never a blank screen.

### Two bugs caught while building
- The boundary generator silently parsed 4 of 13 entries; comments between
  fields defeated the regex. It now strips comments, parses only inside the
  array literal, and cross-checks the count against the `value:` keys, so an
  undercount fails loudly instead of shipping a third of the list.
- `revalidateTag` in Next 16 gives the caller the stale value. The refresh
  button now uses `updateTag`, so the person who clicked sees the new data —
  which is the entire point of the button.

## v0.7.0 — 2026-08-06

The agent runs end to end. It broke a bounty on Arc Testnet and got paid, with
no human in the loop.

### Added
- `agent/src/boundaries.ts` — the annotated boundary value list. A generic list
  for a uint256 amount, most-suspicious first, with a one-line reason for each
  value. It contains no target-specific knowledge; 1e18 is on it because "one
  whole unit at 18 decimals" is the most common amount in DeFi, not because the
  agent knows the bug is there.
- `agent/src/generator.ts` — candidate inputs, boundary-first or random-only.
  Randomness is drawn off-chain from the OS CSPRNG, because Arc's PREVRANDAO is
  always 0 — there is no on-chain randomness to draw.
- `agent/src/attack.ts`, `loop.ts`, `run.ts` — fire attempts through the
  Registry, decide success from mined state, stop on the first break.
- `npm run attack` — the single end-to-end command.
- `scripts/measure_sustained_rate.py`, `scripts/test-attack-scenarios.sh`,
  `scripts/compare-strategies.sh`.

### The public claim
The agent broke bounty #4 (1.5 USDC) on the 6th probe, deposit(1e18), tx
`0xcd29a7592a9fd5e31a37eba0b133961eecaee1e80bcee0fa8b3554c75c66126b`. Agent
balance 41 → 42.49 USDC. The full run: scan → choose the richest → fuzz → claim,
67 RPC calls, 0 throttled, 0 real errors.

### Measured first (the task required it before the loop)
A proper sustained-rate measurement replaced the Day 1 burst figure: eth_call
held completely flat — zero throttling — over four minutes at each of 1.5, 1.0
and 0.6 req/s, and again at 1.5 with retries on. So the sustainable rate is at
least 1.5 req/s, and the retry-budget question is moot because nothing throttled.
This contradicts Task 6's escalation (1→2→4), which is now attributed to a
partly-drained budget from uncooled prior traffic. The throttling is real but
transient; the retry stays as defence, not as a load-bearing crutch.
docs/measurements/task7-sustained-rate.md.

### The two-tier retry, which is the safety-critical part
Reads retry rate-limits freely. Writes never blindly retry: on Arc a returned
transaction hash does not mean the transaction mined (Day 1). So success is read
from mined state — the bounty's paid flag and the agent's balance — never from
the send response. A stuck send re-broadcasts the identical pre-signed bytes,
same nonce, which cannot double-execute. This closes the trap where a first send
breaks the bounty, its response is lost, and a naive retry hits the now-paid
bounty, reverts, and is misread as failure. test-attack-scenarios.sh proves the
paid-bounty attempt is filtered, not misread.

### The control, reproducible offline
STRATEGY=random-only vs boundary-first. compare-strategies.sh runs both on a
local chain: boundary-first breaks a real vault on probe 6, and the same
generator drawn 10,000 times hits the winning value 0 times — reproducing
docs/measurements/task1-findability.md live, without spending on Arc.

## v0.6.0 — 2026-08-04

The agent finds its own work. It does not attack yet; that is Task 7.

### Added
- `agent/` — TypeScript + viem. `npm run scan` reads the bounty board from the
  Registry on Arc Testnet, discards everything that cannot be won, picks the
  most valuable of the rest, and prints why.
- `scripts/test-agent-scenarios.sh` — builds a board on a local chain containing
  every rejection reason plus an empty board, and checks the agent's conclusion
  for each. 14 assertions.
- `docs/measurements/task6-agent-scan.md` — what a scan costs and what the
  throttling actually does.

### The autonomy constraint
The agent is told one thing: the Registry address. Targets, function signatures,
rewards and how many bounties exist are all read at runtime. `grep` over
`agent/src` finds exactly one address literal and no function names.

Selection is feasibility first, money second. Sorting by reward and then finding
the richest bounty unwinnable would waste the run. Rejections are reported
distinctly — "invariant already broken" and "checker will not answer" both mean
do not attack, but hiding which is which would hide whether the target was
griefed or the referee is unreachable.

### Measured
A scan of six bounties costs 22 RPC calls (`3n + 4`) and 17–23 seconds at the
configured pace.

Three consecutive scans were throttled 1, then 2, then 4 times for identical
work. Day 1 measured `eth_call` at ~2.2 req/s and the agent runs at 1.43 req/s,
so a 35% margin is not enough: Arc's limit behaves like a budget draining over a
window, and the Day 1 figure was an instantaneous ceiling measured on a full
bucket. Errors reaching the agent stayed at 0 throughout — the retry absorbed
every rejection. `RPC_MIN_INTERVAL_MS` was left at 700 ms rather than tuned
upward on a guess, since the retry is what carries the load.

### Fixed
- `ARC_RPC_URL` from `.env` was resolved at module load, before `loadEnv()` ran
  in `main()`, so the file's value was silently ignored. It worked only because
  the fallback string was identical — an accident that would have held until the
  agent was pointed at a different chain.

## v0.5.0 — 2026-08-01

Live on Arc Testnet.

### Deployed
- `BountyRegistry` at `0xbBd50574b55CE9F7453882E2d3361b393AD3F99C`, plus five
  `DemoVault` + `VaultChecker` pairs and five open bounties holding 4.00 USDC.
- All 11 contracts source-verified on Arcscan (`is_verified: true`, confirmed
  per address against the explorer API).
- Cost: 16 transactions, 5,705,988 gas, **0.132950 USDC**. Deployer left with
  14.788664 USDC; the agent wallet is untouched at 21.000000 USDC.
- Full record: `docs/deployments/arc-testnet.md`.

### Added
- `script/Deploy.s.sol` — deploys the system and opens the board. Run with
  `--slow` so each transaction is confirmed by receipt before the next is sent.
- `script/OpenBounty.s.sol` — restock one fresh vault + bounty without
  redeploying the Registry. Needed because every claim consumes a bounty and any
  passer-by can kill one permanently by calling `deposit(1e18)` on its target.
- `scripts/verify-deployment.sh` — reads the deployment back from mined state,
  paced under the measured `eth_call` limit. Also reports how many bounties are
  still claimable, which is the number to check before recording a demo.

### Notes
- Five bounties with different rewards rather than one: spares against griefing,
  and something for the agent in Task 6 to actually choose between.
- `forge script --verify` printed `Fail - Unable to verify` for several
  contracts and `All (11) contracts were verified!` at the end. Blockscout
  matches on bytecode, so verifying one `DemoVault` verifies its four
  duplicates and the explicit resubmission then reports failure. Arcscan's API
  is the authority; the forge summary is not.

## v0.4.0 — 2026-08-01

The mechanism. Try, judge and pay, atomically.

### Added
- `BountyRegistry.attempt(bountyId, callData)` — asks the checker, performs the
  agent's action on the target, asks again, and pays the caller on an
  intact→broken transition inside the one transaction. No gap between the break
  and the payout means nothing to front-run.
- `test/BountyRegistryAttempt.t.sol` — 20 tests, most of them attacks.
- `test/mocks/HostileMocks.sol` — reentrant targets, a checker that sabotages
  itself mid-attempt, a return-data bomb, a claimant that refuses payment.
- `test/BountyRegistryInvariant.t.sol` — 12,800 random calls per invariant
  across multiple bounties, actors and griefers.

### Defences
- **Contract-wide reentrancy lock**, not per-function. A hostile target must be
  unable to re-enter `openBounty` as well as `attempt`.
- **A checker that cannot answer reverts the attempt.** Never read as "broken".
  Treating silence as proof would let a hostile target mint a payout by simply
  making its own checker fail.
- **Return data is discarded at the EVM level.** The target call is written in
  assembly with a zero-length output area, so a target cannot inflate the cost
  of every attempt by returning megabytes.
- **Only the declared selector may be fired**, checked before the target is
  touched. Effects before interactions; the payout is bounded by the bounty's
  own reward; a bounty pays at most once.
- The registry refuses to be named as its own target or checker.

### Changed
- `scripts/verify-no-withdrawal.sh` → `scripts/verify-escrow.sh`. The old script
  asserted the runtime bytecode contained no `CALL`, which was true until this
  release and is now false by necessity: `attempt` must call the target and must
  pay the winner. Rather than leave a stale claim standing, the script now
  checks the refined proposition — value enters only via `openBounty` and leaves
  only via the payout — and is explicit that the second half is behavioural and
  therefore verified by test rather than by disassembly. There are exactly 2
  `CALL` sites and 3 `STATICCALL` sites.

### Known limitation, accepted
- Anyone can break a target directly without going through the registry. No
  later attempt can then produce the required transition, and with no
  withdrawal function the bounty is stuck permanently. Cheap to do, nothing
  prevents it. Kept in preference to adding any withdrawal path. Recorded in
  the README.

## v0.3.0 — 2026-08-01

The escrow. Opening and holding only — attack and payout are Task 4.

### Added
- `src/BountyRegistry.sol` — anyone can open a bounty by declaring a target, a
  checker, and the single function signature agents may fire, funding it with
  native USDC in the same call. Open bounties are enumerable by anyone.
- `test/BountyRegistry.t.sol` — 22 tests.
- `scripts/verify-no-withdrawal.sh` — proves the no-withdrawal claim against the
  compiled artefact: one state-changing function, one payable function, no
  receive/fallback, and no SELFDESTRUCT, DELEGATECALL, CALLCODE or CALL in the
  runtime bytecode. Only 2 STATICCALLs, both to the checker.
- `scripts/read-bounties-locally.sh` — reads the board over JSON-RPC from a
  local anvil node, as an agent would.

### Closed
- **Checker/target mismatch.** A sponsor could declare target A while supplying
  a checker welded to target B, leaving a funded bounty that could never be
  claimed. `openBounty` now asks the checker which contract it watches and
  refuses any mismatch. `IChecker.target()` already existed for this.
- **Bounties that are dead on arrival.** Opening over an already-broken
  invariant, a target with no code, or a malformed signature is refused. With
  no withdrawal function, an unclaimable bounty is destroyed money, not an
  inconvenience.

### Notes
- `ONE_USDC = 1e18`. Arc's native USDC has 18 decimals, not the 6 of its ERC-20
  form. Funding with `1e6` would escrow a trillionth of a dollar and no test
  would fail, so the unit is asserted explicitly.

## v0.2.0 — 2026-08-01

The arbiter.

### Added
- `src/IChecker.sol` — the interface every checker must satisfy. `checkInvariant()`
  takes no arguments and is `view`: the target is bound at deployment so no
  caller can redirect it, and `view` compiles to STATICCALL so the EVM itself
  forbids any state write during a check.
- `src/VaultChecker.sol` — checks that the sum of every holder's balance equals
  `totalIssued`. Recomputes the total by walking `holderAt`/`balanceOf` rather
  than calling `DemoVault.sumOfBalances()`, because the target is the party
  under suspicion.
- `test/VaultChecker.t.sol` — 12 tests, including a `LyingVault` whose summary
  function always reports a balanced ledger; the checker is not fooled.
- `docs/measurements/task2-checker-gas.md` — gas by holder count and the
  resulting ceiling.

### Known limitation
- Checking is O(holders) and the Registry pays it twice per claim. Measured at
  8,029 gas per holder for the pair, a claim stops fitting in an Arc block at
  roughly 3,700 holders. Past that a real, found bug becomes unclaimable and —
  since v1 has no withdrawal — the bounty is stuck permanently. Not solved in
  v1; documented instead.

## v0.1.0 — 2026-08-01

First contract of the project.

### Added
- `src/DemoVault.sol` — the practice target: a ledger-only vault carrying a
  deliberate, fully documented boundary-value bug. `deposit` grants a 1% bonus
  at `amount >= 1e18` but only counts it as issued at `amount > 1e18`, so a
  single call with exactly `1e18` leaves the books short by `1e16`.
- `test/DemoVault.t.sol` — 16 tests covering correct behaviour under ordinary
  traffic, the exact drift at the boundary, input validation, and two fuzz
  properties.
- `test/FuzzerReach.t.sol` — opt-in experiment measuring whether Foundry's own
  fuzzer reaches the boundary unaided. It does. Skipped by default.
- `docs/measurements/task1-findability.md` — the resulting numbers and what
  they mean for how the project may describe itself.

### Notes
- Foundry's fuzzer finds the planted bug in 21–305 runs because the threshold is
  a public constant and therefore enters its dictionary. The claim "the agent
  finds what fuzzers cannot" is not supportable and must stay out of the deck.

## Pre-release — 2026-08-01

- Foundry toolchain, Arc Testnet environment probe, and Day-1 kill gate
  measurements. See `docs/measurements/day1-report.md`.
