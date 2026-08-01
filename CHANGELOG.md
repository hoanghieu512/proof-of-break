# Changelog

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
