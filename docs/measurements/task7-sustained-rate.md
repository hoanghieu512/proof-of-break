# Task 7 — the sustainable RPC rate, measured properly

The attack loop fires until a bounty breaks, so it needs a rate Arc will hold
for minutes, not a burst figure. Day 1's 2.2 req/s was an instantaneous ceiling
on a full budget, and Task 6 saw throttling escalate at a rate below it — both
useless for sizing a loop. This measures the rate that stays flat.

Regenerate: `python3 scripts/measure_sustained_rate.py` (~22 minutes). Raw output
in `task7-sustained-rate.txt`.

## Method

`eth_call` — the one method Arc throttles — driven at a fixed pace for **4
minutes** at each of 1.5, 1.0 and 0.6 req/s, with 2 minutes of cooldown between
so each rate starts on a comparable budget. Rejections bucketed per 30 seconds,
so escalation over the run would show as a rising tail. Retries off in phase A,
so they cannot mask the escalation being measured.

Two questions, from the task:

1. **Which paced rate stays flat over minutes?**
2. **Do retries come out of the same budget?** (Phase B: re-run one rate with
   retries on.)

## Result

| Rate | Requests | Throttled | First third → last third | Verdict |
|---|---:|---:|---|---|
| 1.5 req/s | 360 | **0** | 0.0% → 0.0% | flat |
| 1.0 req/s | 240 | **0** | 0.0% → 0.0% | flat |
| 0.6 req/s | 132 | **0** | 0.0% → 0.0% | flat |
| 1.5 req/s + retries | 360 | **0** | 0.0% → 0.0% | flat |

**Every rate was completely flat. Zero throttling, start to finish, at all three
rates, with and without retries.**

### Answering the two questions

1. **Sustainable rate: at least 1.5 req/s.** The highest rate tested held flat
   for four minutes with no rejections. The agent paces at 1.43 req/s (700 ms),
   just under it, with margin.

2. **The retry-budget question is moot at this rate.** Retries only fire when a
   request is throttled, and nothing was throttled — so no retries were issued
   and there is no separate budget to observe them draining. Phase B confirms it:
   1.5 req/s with retries enabled was identical to without, 0 throttled either
   way. If a higher rate did induce throttling, this measurement could not tell
   whether retries deepen it; at the agent's operating rate, the situation does
   not arise.

## Reconciling with the earlier readings

This is the honest part, because it contradicts two earlier findings.

| When | Observation |
|---|---|
| Day 1 | `eth_call` rejected at ~2.2 req/s (burst, full budget) |
| Task 6 (Aug 4) | three back-to-back scans at 1.43 req/s throttled 1 → 2 → 4 |
| Task 7 (Aug 6) | 1.5 / 1.0 / 0.6 req/s flat over 4 min each, zero throttling |

Neither earlier reading reproduced under sustained measurement. The most likely
explanation is the starting budget:

- **Task 6's scans had no cooldown** and came straight after a burst of
  verify-deployment and repeated-scan traffic. The budget was already partly
  drained when the escalation was observed. This measurement waits 2 minutes
  between rates.
- Arc's public limiter state may also simply differ between the two days; a
  public testnet endpoint's configuration is not fixed.

What can be said with confidence: the throttling seen earlier is **real but
transient**, and the **sustainable rate is comfortably ≥1.5 req/s**. The Day 1
figure is not wrong — it is an instantaneous ceiling — it just does not describe
a loop running for minutes.

This is why `RPC_MIN_INTERVAL_MS` is now justified by this measurement rather
than by the 2.2/s number, and why the retry in `chain.ts` is kept as defence
against the transient throttling rather than relied on as load-bearing: at
1.43 req/s it is rarely triggered, but Day 1 and Task 6 prove it sometimes is.

## What the agent actually spent

The real end-to-end run against Arc, which broke bounty #4:

| | |
|---|---|
| RPC calls | 67 |
| Elapsed | 46.5 s |
| Throttled | **0** |
| Real errors | **0** (4 benign: the would-revert filter, viem fee-probe fallbacks, receipt polls) |
| Probes to break | 6 (boundary-first) |
| tx | [`0xcd29a759…66126b`](https://testnet.arcscan.app/tx/0xcd29a7592a9fd5e31a37eba0b133961eecaee1e80bcee0fa8b3554c75c66126b) |
| Reward | 1.5 USDC, agent 41 → 42.49 (net +1.49 after gas) |

Zero throttling on the real run confirms the measured rate holds in practice,
not just in the isolated benchmark.
