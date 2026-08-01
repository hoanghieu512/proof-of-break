# Task 2 — VaultChecker gas, and the ceiling it puts on the design

`VaultChecker` cannot trust the target's own summary, so it walks every holder
and adds the balances up itself. That correctness decision has a price, the
price grows with the number of holders, and the Registry pays it twice per claim
attempt. This records what it actually costs and where it stops working.

Regenerate with:

```
forge test --match-test test_GasScalesLinearlyWithHolders -vv
```

## Measured

Arc block gas limit: **30,000,000** (read from the chain, 2026-08-01).

| Holders | First check (cold) | Both checks (cold + warm) |
|---:|---:|---:|
| 1 | 12,127 | 16,256 |
| 10 | 66,218 | 88,438 |
| 50 | 306,639 | 409,280 |
| 100 | 607,200 | 810,402 |
| 250 | 1,509,119 | 2,014,240 |
| 500 | 3,013,097 | 4,022,196 |

Marginal cost per additional holder:

- first check, cold storage: **6,014 gas**
- the pair the Registry actually makes: **8,029 gas**

## Two corrections that changed the answer

Both are recorded because either one alone would have produced a confidently
wrong ceiling.

**Warm storage made it look 3× cheaper.** The first measurement wrote all the
holder balances moments before reading them, so every slot was warm and cost
100 gas instead of the cold 2,100 (EIP-2929). That reported 2,014 gas per
holder. A real claim transaction touches those slots for the first time.
`vm.cool()` resets them, and the honest figure is 6,014 — three times higher, so
the safe holder count is three times lower than the naive measurement claimed.

**Doubling the cold cost made it look 1.5× more expensive.** The Registry calls
the checker twice, but the second call re-reads slots the first call just
warmed, so it is much cheaper. `2 × 6,014 = 12,028` overstates it; the measured
pair is `8,029`. Estimating from the doubled figure would have put the ceiling
at ~2,494 holders instead of the real ~3,736.

## The ceiling

Using the measured pair cost of 8,029 gas per holder, and ignoring the
Registry's own overhead and the agent's action against the target (both of which
only make this worse):

| | Holders |
|---|---:|
| Claim transaction fills an entire Arc block | **~3,736** |
| Half a block — a sane practical ceiling | **~1,868** |
| Comfortable, no thought required | **< 500** (4.0M gas, 13% of a block) |

At the demo's scale — a handful of holders — a claim costs on the order of
16k–90k gas for the checking, which is noise next to the ~0.000654 USDC measured
for a simple state write on Day 1.

## Why this matters beyond gas billing

The failure mode is not "claims get expensive". It is worse than that:

> Past roughly 3,700 holders, a claim transaction cannot fit in a block at all.
> The bug is real, the agent found it, and **nobody can be paid**. The bounty
> becomes permanently unclaimable, and since v1 has no withdrawal function
> (design doc §7, §9), the money is stuck there forever.

So holder count is not a performance parameter of this design; it is a
correctness parameter of the escrow.

## Not fixed in v1, and why

The scope is a demo target with a handful of holders, and the plan for Task 2
asks to know and state this limit rather than engineer around it.

The real fix is to restate the invariant so it is O(1) to verify. A vault could
maintain a running `sumOfCredited` updated on every deposit and withdrawal; the
checker then compares two storage words in constant time and the holder count
stops mattering. That moves the cost onto depositors, off the claim path, and
out of the escrow's correctness. It also changes what is being checked — the
checker would be verifying the vault's own accumulator rather than deriving the
total independently, which reintroduces exactly the trust problem
`VaultChecker` was written to avoid. Resolving that tension properly (a
Merkle commitment over balances, say) is beyond v1.

**Stated limitation for the README:** this mechanism verifies invariants whose
evaluation is bounded by block gas. Properties requiring an unbounded scan of
participants do not fit, and a bounty declared over one can become unclaimable
as the target grows.
