# Arc Testnet deployment — v0.5.0

Deployed 2026-08-01. Chain 5042002. Every address below was confirmed against
mined chain state by `scripts/verify-deployment.sh`, not taken from a
transaction hash — on Arc a hash is not a promise of inclusion
([Day 1](../measurements/day1-report.md)).

## The one address that matters

```
BountyRegistry  0xbBd50574b55CE9F7453882E2d3361b393AD3F99C
```

https://testnet.arcscan.app/address/0xbBd50574b55CE9F7453882E2d3361b393AD3F99C

Everything else is discoverable from it. An agent reads the board here and
learns each bounty's target, checker and callable function without being told
any of them — that is the point of the design, so the agent must never hard-code
the addresses below.

## Bounties

Six, each with its own target. Rewards deliberately differ so that an agent
choosing its own work has something to choose between.

| # | Reward | Status | Target (DemoVault) | Checker (VaultChecker) |
|---|---|---|---|---|
| 0 | 0.25 USDC | open | [`0xAa826060…Da853`](https://testnet.arcscan.app/address/0xAa826060033063142f6aD765D870b24Ec8EDa853) | [`0xbE731dE9…B59c0`](https://testnet.arcscan.app/address/0xbE731dE980a0527127c07e0301ca1550aC9B59c0) |
| 1 | 0.50 USDC | open | [`0xf4E0AB42…4836d`](https://testnet.arcscan.app/address/0xf4E0AB422EE370D3C2DdCD77e9Cc2CEAE7E4836d) | [`0x5BE2b7f6…93d83`](https://testnet.arcscan.app/address/0x5BE2b7f66bBd17b2fAb2535aEb2628373d593d83) |
| 2 | 0.75 USDC | open | [`0x7f0829dD…cc552`](https://testnet.arcscan.app/address/0x7f0829dD377A660e2f68B6f87AfEAAD9Eeccc552) | [`0xe72D8f60…4B53A`](https://testnet.arcscan.app/address/0xe72D8f60c4CDE26DD7A550bF9984b7FC6744B53A) |
| 3 | 1.00 USDC | open | [`0xed91a4dC…9E391`](https://testnet.arcscan.app/address/0xed91a4dC9Ad6C036246943487840026faCC9E391) | [`0x316fD688…E8276`](https://testnet.arcscan.app/address/0x316fD68879f15A050eB5E9Ff7C7a85881D1E8276) |
| 4 | 1.50 USDC | **claimed** | [`0x41c0Ae1F…76a3C`](https://testnet.arcscan.app/address/0x41c0Ae1F750AC13d9e4e79B5Ab53b44F29076a3C) | [`0x4c81A597…78921`](https://testnet.arcscan.app/address/0x4c81A597C76C676cfed89B7C2d30c44856b78921) |
| 5 | 0.25 USDC | open | [`0x26b40427…AAcb8`](https://testnet.arcscan.app/address/0x26b404270325FB212631EBaa8128c48c206AAcb8) | [`0x44858607…7211B`](https://testnet.arcscan.app/address/0x44858607A5793672729c716107115e7042a7211B) |

All six declare `deposit(uint256)` as the callable function and hold the same
invariant: the sum of every holder's balance equals `totalIssued`.

Total escrowed: **4.25 USDC** (`4250000000000000000` wei — Arc's native USDC has
18 decimals). Five bounties remain open (**2.75 USDC**); bounty #4 was claimed by
the agent — see below.

## The agent's first claim

On 2026-08-06 the agent (Task 7) broke bounty #4 with no human intervention: it
scanned the board, chose #4 as the richest, fuzzed the target boundary-value-
first, and broke the invariant on the 6th probe with a deposit of exactly `1e18`.

| | |
|---|---|
| Winning tx | [`0xcd29a759…66126b`](https://testnet.arcscan.app/tx/0xcd29a7592a9fd5e31a37eba0b133961eecaee1e80bcee0fa8b3554c75c66126b) |
| From → to | agent `0xd3e2…8888` → Registry, status success |
| Reward | 1.5 USDC |
| Agent balance | 41 → 42.490530 USDC (net +1.49 after gas) |
| RPC cost | 67 calls, 46.5 s, **0 throttled, 0 real errors** |

The winning value was reached by a generic boundary list with no knowledge of
the target — `1e18` is on that list because "one whole unit at 18 decimals" is
the most common amount in DeFi, not because the agent was told where the bug was.

Bounty 5 was added later by `script/OpenBounty.s.sol`, which is what makes the
restock path in the runbook a tested claim rather than an untested one. It cost
0.272197 USDC in total: 0.25 escrowed plus 0.022197 in gas.

## Verification

All 13 contracts report `is_verified: true` on Arcscan, confirmed by querying
the explorer API per address. (11 from the initial deployment, plus the vault
and checker added with bounty 5.)

Worth recording because it is misleading: `forge script --verify` printed
`Fail - Unable to verify` for several contracts and then `All (11) contracts
were verified!` at the end. Both halves are explicable — Blockscout matches on
bytecode, so verifying the first `DemoVault` verifies every later one
automatically, and the explicit submission for a duplicate then reports failure
even though the contract is verified. Forge reports each submission; Arcscan
holds the truth. Do not trust the forge summary line either way; query the API.

## Cost of the initial deployment

| | |
|---|---|
| Transactions | 16 |
| Total gas | 5,705,988 |
| Gas price | 23.30 gwei |
| Gas cost | **0.132950 USDC** |
| Escrowed into bounties | 4.000000 USDC |
| Total spend | **4.132950 USDC** |

Balances as of the last check:

| Wallet | Balance |
|---|---|
| Deployer `0x6BA70dfb…11111` | 34.516467 USDC (topped up from the faucet, then 0.272 spent on bounty 5) |
| Agent `0xd3e23bA1…88888` | 41.000000 USDC (topped up from the faucet; untouched by the system) |
| Registry (escrow) | 4.250000 USDC |

The agent wallet is untouched by design — it must fund its own attempts and
receive its own reward in Task 7.

## Restocking

A bounty is consumed by a successful claim, and dies permanently if anyone calls
`deposit(1e18)` on its target directly (the griefing vector in the README).
Either way, add a fresh one without redeploying the Registry:

```bash
REGISTRY=0xbBd50574b55CE9F7453882E2d3361b393AD3F99C REWARD_WEI=500000000000000000 forge script script/OpenBounty.s.sol:OpenBounty --rpc-url $ARC_RPC_URL --broadcast --slow --verify --verifier blockscout --verifier-url https://testnet.arcscan.app/api/
```

Then confirm it landed:

```bash
REGISTRY=0xbBd50574b55CE9F7453882E2d3361b393AD3F99C ./scripts/verify-deployment.sh
```

That script also reports how many bounties are still claimable, which is the
number to check before recording a demo.
