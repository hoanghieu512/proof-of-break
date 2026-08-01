# Task 1 — how findable is the planted bug?

The plan's acceptance criterion for Task 1 expected a Foundry fuzz test to show
that random input "rarely hits" the boundary bug, as the comparison that makes
the agent's boundary-first strategy look good.

Measured instead of assumed, and the expectation only half survives.

## The bug

`DemoVault.deposit` grants a 1% bonus at `amount >= 1e18` but only counts it in
`totalIssued` at `amount > 1e18`. At exactly `1e18` the books drift by `1e16`
(0.01 units). One call, one exact value out of 2^256.

## Three search strategies, measured

| Strategy | Result |
|---|---|
| Uniform random over `[1, 2e18]` | 0 hits in 10,000 draws |
| **Foundry's fuzzer**, 20,000 runs | **found it — seed 1 in 305 runs, seed 2 in 92, seed 3 in 28 (and 21 on a rerun)** |
| Boundary value list (16 entries) | found it on probe **6** |

Reproduce the middle row:

```
POB_RUN_FUZZ_REACH=true forge test --match-contract FuzzerReach \
  --fuzz-runs 20000 --fuzz-seed 3
```

## Why the fuzzer wins so easily

Foundry's fuzzer is not uniform random. It seeds a dictionary from constants
found in the code under test, and `LARGE_DEPOSIT_THRESHOLD = 1e18` is a public
constant sitting in plain sight. The fuzzer is effectively handed the boundary
value, which is exactly the input the bug needs. In other words, a modern fuzzer
already performs a form of boundary value analysis.

## What this means for the pitch

**Do not claim the agent finds bugs that fuzzers cannot.** On this target that
claim is measurably false, and a judge who runs `forge test --fuzz-runs 20000`
will find out in under a minute. Claiming it and being caught costs more than
the claim was ever worth.

The design doc already frames this correctly (§8, *"Sao không dùng forge test /
Echidna cho rẻ?"*): the differentiator is **who is doing the testing and under
what incentive**, not raw search efficiency —

- internal fuzzing tests the invariants the development team thought of, in the
  development team's own environment, while someone is paying attention;
- this system opens an invariant to unknown third parties, pays them in USDC on
  success, and keeps running after the audit engagement ends.

The honest framing of the numbers above is: *the bug is machine-findable by
several strategies, which is the point — a machine can judge it and pay for it
without a human in the loop.* Boundary-first search reaching it in 6 probes
rather than 28–305 is a genuine efficiency difference and can be stated as such,
but it is a footnote, not the thesis.

## Consequence for Task 7

The agent's boundary list should be presented as *engineering judgement about
where bugs live*, not as a claimed advantage over fuzzing. Keeping the list in
its own readable file (plan Task 7) still matters — it is the visible artefact
of the QA skill the submission is built on.

## Deliberately not changed

The obvious way to make the fuzzer's job harder is to stop declaring the
threshold as a public constant, so it never enters the dictionary. That was
rejected: the plan requires the agent to hit the bug reliably and forbids
hiding it, and a target whose boundary cannot be discovered from public state
would be a worse demo and a dishonest one.
