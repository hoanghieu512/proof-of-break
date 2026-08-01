# Proof of Break

**Autonomous agents get paid in USDC for breaking smart contracts.**

> Work in progress — Programmable Money Hackathon (Arc x Encode). Track: Agentic Economy.

## The problem

Smart contract security today is human-gated. A developer pays an audit firm tens of thousands of dollars for a point-in-time review, or posts a bounty and waits weeks while humans triage written reports. Both are slow, expensive, and stop the moment the engagement ends.

The industry has long described a better shape — a contract that validates a vulnerability proof itself and pays the bounty automatically, with no human in the middle. It hasn't been built, for two reasons: proving a bug programmatically is hard, and on a live contract, exploiting the bug is worth more than reporting it.

## The mechanism

This project targets **staging contracts on testnet**, which dissolves the second problem entirely: an exploit on testnet is worth nothing, so the only rational move is to claim the bounty.

- A developer deploys a contract to Arc Testnet and funds a USDC bounty pool, declaring one or more **invariants** — properties that must always hold.
- Autonomous agents hold their own wallets and hammer the target with transactions, checking after each one whether an invariant still holds.
- When an agent breaks an invariant, it calls the bounty contract. The contract verifies the violation on-chain and pays out immediately.

No arbitrator. No report. No 30-day review queue. If a bug can be expressed as an invariant, a machine can judge it — and pay for it.

## Why Arc

Fuzzing means thousands of attempts. That economic model only closes when two conditions hold at once:

- **Sub-cent gas**, so each attempt is effectively free
- **Gas denominated in a stable unit** (USDC), so the cost of an attempt and the value of a payout don't drift apart mid-campaign

Arc is the first chain where both are true by design.

## Status

Early build. Toolchain is up and the environment kill gate has been cleared: a
contract compiles, deploys, executes and verifies its source on Arc Testnet,
and the gas economics have been measured rather than assumed.

- Probe contract: [`0x8850a83F…A3A9e5`](https://testnet.arcscan.app/address/0x8850a83Fc38b87453aeB4EEDb23c10f370A3A9e5) (source verified)
- Measured cost of a state-changing call: **0.000654 USDC** (0.065¢)
- Native USDC on Arc confirmed at 18 decimals by transaction, not by docs

Full numbers and the two false trails along the way: [Day 1 report](docs/measurements/day1-report.md).

Planned for final submission (9 Aug):
- Bounty escrow contract with on-chain invariant verification, deployed on Arc Testnet
- A deliberately vulnerable target contract
- An autonomous agent that fuzzes the target, detects the violation, and claims the payout unattended
- End-to-end demo video

## Honest scope

This is a proof that the mechanism works end to end — not a platform. It covers the class of bugs expressible as on-chain invariants; economic and multi-transaction logic flaws are out of scope for this build.

## Author

Senior test engineer (8+ yrs QA). The interesting problem here isn't the Solidity — it's defining invariants worth testing and designing verification that a machine can trust. That's the part I know.
