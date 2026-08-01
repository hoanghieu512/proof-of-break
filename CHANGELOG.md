# Changelog

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
