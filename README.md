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

## Live on Arc Testnet — and an agent has claimed a bounty

The contracts are deployed, source-verified, and holding real escrow, and an
autonomous agent has broken bounties end to end with no human in the loop: it
scanned the board, chose the richest bounty, fuzzed the target
boundary-value-first, and broke the invariant on its 6th probe. It has now done
this **four times, on four separate targets**, unattended each time.

**The winning transaction** — the run filmed for the demo video, so the hash on
screen is the hash here:
[`0x475dce0a…b0e89a`](https://testnet.arcscan.app/tx/0x475dce0a13ccc4800f5c889abbb0a4f7e9378c497932357536d36fe3c3b0e89a)
— 1.5 USDC paid to the agent's own wallet, verifiable on Arcscan.

**Live board:** [proof-of-break.vercel.app](https://proof-of-break.vercel.app)
— read-only. It shows the board as the chain has it right now, the break, and
the boundary value list the agent used. No wallet, no writes.

**Registry — the only address you need:**

[`0xbBd50574b55CE9F7453882E2d3361b393AD3F99C`](https://testnet.arcscan.app/address/0xbBd50574b55CE9F7453882E2d3361b393AD3F99C)

Nine bounties were opened; **five remain open** (2.75 USDC) and **four have been
claimed by the agent** (6.0 USDC paid out):

| # | Reward | Status | Target | Callable function |
|---|---|---|---|---|
| 0 | 0.25 USDC | open | [`0xAa826060…Da853`](https://testnet.arcscan.app/address/0xAa826060033063142f6aD765D870b24Ec8EDa853) | `deposit(uint256)` |
| 1 | 0.50 USDC | open | [`0xf4E0AB42…4836d`](https://testnet.arcscan.app/address/0xf4E0AB422EE370D3C2DdCD77e9Cc2CEAE7E4836d) | `deposit(uint256)` |
| 2 | 0.75 USDC | open | [`0x7f0829dD…cc552`](https://testnet.arcscan.app/address/0x7f0829dD377A660e2f68B6f87AfEAAD9Eeccc552) | `deposit(uint256)` |
| 3 | 1.00 USDC | open | [`0xed91a4dC…9E391`](https://testnet.arcscan.app/address/0xed91a4dC9Ad6C036246943487840026faCC9E391) | `deposit(uint256)` |
| 4 | 1.50 USDC | **claimed** | [`0x41c0Ae1F…76a3C`](https://testnet.arcscan.app/address/0x41c0Ae1F750AC13d9e4e79B5Ab53b44F29076a3C) | `deposit(uint256)` |
| 5 | 0.25 USDC | open | [`0x26b40427…AAcb8`](https://testnet.arcscan.app/address/0x26b404270325FB212631EBaa8128c48c206AAcb8) | `deposit(uint256)` |
| 6 | 1.50 USDC | **claimed** | [`0x9c746aBb…c88CB9`](https://testnet.arcscan.app/address/0x9c746aBb3788e1Cdc2499B104C3E5A9b8Ac88CB9) | `deposit(uint256)` |
| 7 | 1.50 USDC | **claimed** | [`0xca18418E…388234`](https://testnet.arcscan.app/address/0xca18418E09D3bA3B184d5E01260912Db0c388234) | `deposit(uint256)` |
| 8 | 1.50 USDC | **claimed** (on camera) | [`0xA0cf432E…7513AC`](https://testnet.arcscan.app/address/0xA0cf432Efc3d8156a85e3F92ff9a37E62d7513AC) | `deposit(uint256)` |

Bounties 6, 7 and 8 were opened at the same reward on purpose, so that repeated
takes of the demo video would all show the same number on screen and stay
intercuttable. Each take spent one of them; #8 is the take that was kept.

Every checker address, the full deployment record, and what it all cost:
[docs/deployments/arc-testnet.md](docs/deployments/arc-testnet.md).

### Read the board yourself

No key needed, no permissions, nothing to install but Foundry:

```bash
cast call 0xbBd50574b55CE9F7453882E2d3361b393AD3F99C 'openBountyIds()(uint256[])' --rpc-url https://rpc.testnet.arc.network
```

```bash
cast call 0xbBd50574b55CE9F7453882E2d3361b393AD3F99C 'getBounty(uint256)((address,address,address,bytes4,uint256,bool,string))' 0 --rpc-url https://rpc.testnet.arc.network
```

That second call returns everything an attacker needs — target, checker, the
function it may call — which is exactly how the agent will find its work.

### Run the test suite

```bash
forge test
```

```bash
./scripts/verify-escrow.sh
```

The second one checks the claim that money can only leave the registry through a
payout, against the compiled bytecode and then against the tests that pin the
behavioural half.

### Measured, not assumed

- Native USDC on Arc is **18 decimals**, confirmed by transaction — `1 USDC = 1e18`
- A state-changing call costs **0.000654 USDC** (0.065¢)
- Deploying all 11 contracts and opening 5 bounties cost **0.13 USDC** in gas
- `eth_call` throttling is transient, not a fixed rate: it held completely flat over four minutes at 1.5, 1.0 and 0.6 req/s
- A transaction hash is **not** a promise of inclusion on Arc — confirm by receipt

Full numbers and the false trails along the way: [Day 1 report](docs/measurements/day1-report.md).

Done and verifiable today:
- Bounty escrow with on-chain invariant verification, deployed and source-verified on Arc Testnet
- A deliberately vulnerable target contract, with the bug documented in the source
- An autonomous agent that scans the board, picks its own work, fuzzes the target and claims the payout unattended — [transaction](https://testnet.arcscan.app/tx/0x475dce0a13ccc4800f5c889abbb0a4f7e9378c497932357536d36fe3c3b0e89a), repeated on four separate targets
- A read-only board at [proof-of-break.vercel.app](https://proof-of-break.vercel.app)

## Honest scope

This is a proof that the mechanism works end to end — not a platform. It covers the class of bugs expressible as on-chain invariants; economic and multi-transaction logic flaws are out of scope for this build.

### Known limitations, stated rather than discovered

**A bounty can be griefed into permanent limbo.** The registry only consults the checker when a bounty is opened and when someone makes an attempt. The target is an ordinary public contract, so anyone can call it directly without going through the registry. If a griefer breaks the invariant that way, no later attempt can ever produce the intact→broken transition a payout requires, and because there is no withdrawal function the escrowed USDC is stuck forever. This is cheap to do and nothing prevents it.

It is a deliberate trade. Adding a refund path would mean adding a way to take money out of the registry, and "nobody can withdraw, including the author" is the property the whole transparency argument rests on. v1 keeps the stronger property and accepts the griefing risk.

**Invariants must be checkable within one block's gas.** The checker recomputes the vault's total from every holder rather than trusting the target's own summary, so the cost grows with the number of holders and the registry pays it twice per attempt. Measured at 8,029 gas per holder, a claim stops fitting in an Arc block at roughly 3,700 holders — at which point a real, discovered bug becomes unclaimable. Properties requiring an unbounded scan of participants do not fit this mechanism. Numbers in [docs/measurements/task2-checker-gas.md](docs/measurements/task2-checker-gas.md).

**A sponsor can write a checker that never reports a break.** Checker source is public and verifiable on Arcscan, and an agent can read it before spending gas, but nothing in v1 forces a checker to be honest.

## Author

Senior test engineer (8+ yrs QA). The interesting problem here isn't the Solidity — it's defining invariants worth testing and designing verification that a machine can trust. That's the part I know.
