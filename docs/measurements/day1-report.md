# Day 1 — Toolchain + Kill Gate report

**Date:** 2026-08-01 (the kill-gate deadline itself)
**Verdict:** environment is ready. Kill gate passed.

---

## Scorecard

| # | Item | Result |
|---|---|---|
| 1 | Foundry usable | **PASS** |
| 2 | Contract deployed to Arc Testnet | **PASS** |
| 3 | Source verification on Arcscan | **PASS** |
| 4 | RPC load threshold measured | **PASS**, with one method-specific limit found |
| 5 | Gas cost per transaction in USDC | **PASS** |
| + | Native USDC decimals confirmed by real tx | **PASS** (design doc §9 risk closed) |

---

## 1. Foundry — PASS

Installed via Homebrew (`foundry 1.7.1`), not `curl | bash`.

Verified by using it, not by trusting the installer:

```
forge build   21 files compiled, solc 0.8.28
forge test    5 passed, 0 failed
              incl. testFuzz_SetValueRoundTrips — 256 fuzz runs
```

The fuzz run matters more than the other four: property-based fuzzing is the
capability Task 4 and Task 7 rest on, so it was exercised on Day 1 instead of
assumed.

`evm_version = "cancun"` — a conservative subset of Arc's Osaka baseline, which
also gives transient storage (`TSTORE`) for the Task 4 reentrancy guard.

## 2. Deployment — PASS

| | |
|---|---|
| Contract | `KillGateProbe` (throwaway probe, not product code) |
| Address | [`0x8850a83Fc38b87453aeB4EEDb23c10f370A3A9e5`](https://testnet.arcscan.app/address/0x8850a83Fc38b87453aeB4EEDb23c10f370A3A9e5) |
| Deploy tx | `0x373310d96342015f17fbb5330cac3f8cbbe6dbdf8c0fcdbe0a515c63ad6c692e` |
| Block | 54,747,696 |

Full path proven end to end: **compile → deploy → write state → read state back.**
`value()` returned `42` from the constructor, then `31337` after
`setValue(31337)` (tx `0xd13c92f1…f282e`).

One snag worth recording: `forge create --constructor-args 42 --broadcast` fails
with *"expected 1 but got 2"* because `--constructor-args` is variadic and
swallows the following flag. `--constructor-args` must come last.

## 3. Arcscan verification — PASS

Arcscan is **Blockscout v11.2.3**, so Foundry's Blockscout verifier works directly:

```
forge verify-contract <addr> src/KillGateProbe.sol:KillGateProbe \
  --verifier blockscout --verifier-url https://testnet.arcscan.app/api/ \
  --compiler-version 0.8.28 --num-of-optimizations 200 \
  --constructor-args $(cast abi-encode "constructor(uint256)" 42)
```

Result `Pass - Verified`; explorer API reports `is_verified: true`,
`v0.8.28+commit.7893614a`. **No API key is required** — Blockscout accepts any
non-empty string.

This removes a listed fallback: the plan's cut-list had "drop Arcscan
verification" as the first thing to sacrifice under time pressure. It costs
nothing, so keep it. It also makes the design doc's transparency claim (§8 —
"Checker code is public and verifiable") real rather than aspirational.

## 4. RPC load threshold — measured

Chain block time: **0.51 s**.

### Reads

| Method | Behaviour |
|---|---|
| `eth_blockNumber` | clean — 120/120 flat out; 160/160 paced at 8 req/s |
| `eth_getBalance` | clean — 60/60 flat out |
| `eth_estimateGas` | clean — 60/60 flat out |
| **`eth_call`** | **throttled — ~2.2 req/s sustainable** |

`eth_call` is the outlier and it reproduces: in an A/B alternation of four
rounds each (40 calls per round, no cooldown), `eth_blockNumber` scored 160/160
while `eth_call` scored 128/160, rejecting almost exactly 9 per round every time.

An earlier hypothesis — that the limiter prices methods by execution cost — was
tested and **disproved**: `eth_estimateGas` executes the EVM and is not
throttled, while `eth_chainId` returns a constant and was. The limit tracks the
specific method, not its cost. The mechanism behind that is not known and is not
guessed at here.

### Writes

Measured two ways, because the first way measured the wrong thing.

Submitting via `cast send` gave 25/25 accepted at 0.8 tx/s — but that number is
`cast` process startup (~1.2 s each), not the RPC. Re-measured with transactions
signed up front and fired as raw bytes:

| Rate | Submitted | Actually mined |
|---|---|---|
| 2 tx/s | 15/15 | 15/15 |
| 5 tx/s | 15/15 | 15/15 |
| 10 tx/s | 15/15 | 15/15 |
| ~27 tx/s | 29/60 | **5/60** |

**The critical finding is the last row.** At burst rate the RPC accepted 29
transactions and returned a hash for each, yet only 5 were ever mined. The rest
were dropped after acceptance. On Arc's public RPC, *a transaction hash is not
a promise of inclusion* — the agent must confirm by receipt, never by
submission success.

The nonce mechanics behind that were confirmed directly: after the burst, the
account nonce sat at 28 with nothing pending. Submitting the single missing
nonce-28 transaction caused the queued successors to cascade in (nonce 28 → 33,
`bumps` 25 → 30), so the losses were a mix of eviction and gap-stranding, not a
single cause.

### Error codes seen

| Code | Message | Trigger |
|---|---|---|
| `-32011` | request limit reached | `eth_call` above ~2.2 req/s; writes under burst |
| `-32005` | rate limit exceeded | high concurrency (≥50) |
| `-32003` | txpool is full | writes at ~27 tx/s |
| HTTP 403 | *(no body)* | `User-Agent: Python-urllib/*` |

### Endpoints

| Endpoint | 30 sequential calls | p50 |
|---|---|---|
| `rpc.testnet.arc.network` | 30/30 | 343 ms |
| `rpc.testnet.arc.io` | 30/30 | 359 ms |
| `rpc.blockdaemon.testnet.arc.io` | 30/30 | 543 ms |
| `rpc.quicknode.testnet.arc.io` | 30/30 | 670 ms |
| `rpc.drpc.testnet.arc.io` | 27/30 | 256 ms (fastest, only one to 429) |

Note the docs list `rpc.testnet.arc.io` as primary while the hackathon brief
gave `rpc.testnet.arc.network`. Both serve chain 5042002 and both work.

## 5. Gas cost in USDC — PASS

Native unit is 18 decimals, so `cost = gasUsed × effectiveGasPrice / 1e18`.
Gas price observed: 23.21 gwei (docs state a 20 gwei testnet floor).

| Operation | gasUsed | Cost (USDC) | Cost (¢) |
|---|---|---|---|
| Deploy `KillGateProbe` | 163,023 | 0.003784 | 0.378 |
| `setValue(uint256)` | 28,167 | 0.000654 | 0.065 |
| `bump()` | 28,371 | 0.000659 | 0.066 |

**Stated plainly so the deck does not overclaim:** 0.065¢ is a bare single
`SSTORE`. A real Proof-of-Break attempt is check → execute → check routed
through `BountyRegistry`, which will cost several times this. These numbers
establish **"sub-cent per attempt"**, which is the claim the design doc actually
makes (§4). They do not establish "0.065¢ per attempt", and that figure should
not appear in the pitch.

## 6. Native USDC decimals — PASS

Confirmed by transaction, not by documentation. Sent exactly `1e18` from
deployer to agent (tx `0xb0650d0f…0d31d`): agent balance moved
`20000000000000000000 → 21000000000000000000`, a delta of `1e18` reading as
`1.000000` at 18 decimals.

**Native gas unit = 18 decimals.** USDC's ERC-20 interface separately exposes 6
decimals over the same balance; that view is untested and only matters if a
later version moves bounty accounting to the ERC-20 path.

---

## Consequences for the build

1. **The atomic design is accidentally load-bearing for a second reason.** The
   only throttled read method is `eth_call`. An agent shaped as "read state →
   evaluate off-chain → fire" would hit a ~2.2 req/s wall. The design already
   routes check → execute → check into a single on-chain transaction (design
   doc §6), so the agent needs almost no `eth_call` at all. This was chosen for
   anti-frontrunning reasons, and it happens to dodge the rate limit too.

2. **Task 7 must confirm by receipt.** Given the 29-accepted / 5-mined result,
   the agent's success condition must be a mined receipt plus a balance
   increase — never a returned transaction hash.

3. **Pace the agent at ≤10 tx/s** and it stays inside clean territory with
   margin. The demo needs nowhere near that: boundary-value-first fuzzing (§7.3)
   should land in tens of attempts, not thousands.

4. **`PREVRANDAO` always returns 0 on Arc** — there is no on-chain randomness.
   Input generation must happen off-chain in the agent. This does not affect the
   current design but would have quietly broken an on-chain fuzzing approach.

5. **Keep Arcscan verification.** It is free and works, so the plan's first
   listed budget cut is unnecessary.

## Two traps that cost time, recorded so they do not recur

- **Arc's RPC returns HTTP 403 to `User-Agent: Python-urllib/*`** (an
  anti-scraper rule). Every other UA tested, including an empty one, gets 200.
- **This machine's Python has no CA bundle**, so every HTTPS call failed with
  `CERTIFICATE_VERIFY_FAILED` and looked exactly like a total network outage.
  The first measurement run reported "0/120 requests succeeded" and nearly
  became a finding about Arc. It was a local misconfiguration. `certifi` was
  already installed; binding the SSL context to it fixed it.

Both are the v1.4.1 lesson repeating: the predicted cause was wrong until the
actual error text was read.

## One-line conclusion

**The environment is ready to build on — deploy, verification, gas economics and
RPC headroom are all confirmed by measurement, and the two limits found
(`eth_call` throttling, acceptance ≠ inclusion) are both already accommodated by
the existing design.**
