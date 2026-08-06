#!/usr/bin/env python3
"""Find the rate Arc's RPC will hold for minutes, not for a burst.

WHY THIS EXISTS

Day 1 measured eth_call at ~2.2 req/s. Task 6 ran the agent at 1.43 req/s — a
35% margin — and was still throttled, increasingly: three consecutive scans of
identical work were rejected 1, then 2, then 4 times. So 2.2/s is an
instantaneous ceiling measured on a full bucket, and it is useless for sizing a
loop that runs until it breaks something.

Task 7 fires transactions until a bounty falls. That loop needs a rate that is
still flat after several minutes, which is a different measurement.

TWO QUESTIONS, TWO PHASES

  A. Which paced rate stays flat over minutes?
     Run each rate for several minutes with retries OFF, and bucket the
     rejections by time. A rate is flat if the rejection count in the last third
     of the run is no worse than in the first third. Retries are off on purpose:
     they would mask the very escalation being measured.

  B. Do retries count against the same budget?
     Re-run one rate with retries ON. If the budget counts raw requests, the
     extra retry traffic should make throttling worse than phase A at the same
     nominal rate. If throttling is unchanged, retries are free and the loop can
     lean on them.

Run: python3 scripts/measure_sustained_rate.py
"""

import json
import ssl
import sys
import time
import urllib.error
import urllib.request
from collections import Counter

# ----------------------------------------------------------------- setup ----

def _ssl_context():
    """This machine's Python has no CA bundle; without one every call fails."""
    import os
    candidates = []
    try:
        import certifi
        candidates.append(certifi.where())
    except ImportError:
        pass
    candidates += ["/etc/ssl/cert.pem", "/usr/local/etc/ca-certificates/cert.pem"]
    for p in candidates:
        if p and os.path.exists(p):
            return ssl.create_default_context(cafile=p)
    raise RuntimeError("no CA bundle found")


SSL_CTX = _ssl_context()
URL = "https://rpc.testnet.arc.network"
REGISTRY = "0xbBd50574b55CE9F7453882E2d3361b393AD3F99C"
BOUNTY_COUNT_SELECTOR = "0x3e362c96"  # bountyCount(), from `cast sig`

# eth_call specifically: it is the only read method Arc throttles, and it is
# what the agent actually uses.
PAYLOAD = {
    "method": "eth_call",
    "params": [{"to": REGISTRY, "data": BOUNTY_COUNT_SELECTOR}, "latest"],
}

WINDOW_S = 30           # bucket size for spotting escalation
RUN_S = 240             # 4 minutes per rate — long enough for a bucket to drain
COOLDOWN_S = 120        # let the budget refill between rates
RATES = [1.5, 1.0, 0.6]


def call() -> tuple[bool, str]:
    """One eth_call. Returns (ok, label). Never retries."""
    body = json.dumps({"jsonrpc": "2.0", "id": 1, **PAYLOAD}).encode()
    req = urllib.request.Request(
        URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "proof-of-break-measure/0.1",  # Arc 403s Python-urllib
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30, context=SSL_CTX) as r:
            payload = json.loads(r.read())
        if "error" in payload:
            return False, f"rpc:{payload['error'].get('code')}"
        return True, "ok"
    except urllib.error.HTTPError as e:
        code = None
        try:
            code = json.loads(e.read()).get("error", {}).get("code")
        except Exception:
            pass
        return False, f"http:{e.code}/{code}"
    except Exception as e:
        return False, f"exc:{type(e).__name__}"


def is_throttle(label: str) -> bool:
    return any(c in label for c in ("429", "-32011", "-32005", "-32003"))


def paced_run(rate: float, seconds: int, retry: bool) -> dict:
    """Fire at `rate` req/s for `seconds`, bucketing outcomes per window."""
    interval = 1.0 / rate
    start = time.monotonic()
    buckets: list[dict] = []
    labels = Counter()
    sent_total = 0       # includes retries
    issued_total = 0     # logical requests, excluding retries

    i = 0
    while True:
        target = start + i * interval
        now = time.monotonic()
        if target > now:
            time.sleep(target - now)
        if time.monotonic() - start >= seconds:
            break

        w = int((time.monotonic() - start) // WINDOW_S)
        while len(buckets) <= w:
            buckets.append({"sent": 0, "throttled": 0, "ok": 0})

        issued_total += 1
        attempts = 0
        while True:
            ok, label = call()
            sent_total += 1
            attempts += 1
            buckets[w]["sent"] += 1
            labels[label] += 1
            if ok:
                buckets[w]["ok"] += 1
                break
            if is_throttle(label):
                buckets[w]["throttled"] += 1
                if retry and attempts < 3:
                    time.sleep(2.0 * attempts)
                    continue
            break
        i += 1

    return {
        "rate": rate,
        "issued": issued_total,
        "sent": sent_total,
        "buckets": buckets,
        "labels": dict(labels),
        "elapsed": time.monotonic() - start,
    }


def escalating(buckets: list[dict]) -> tuple[bool, float, float]:
    """Compare the rejection rate of the first third against the last third."""
    n = len(buckets)
    if n < 3:
        return False, 0.0, 0.0
    k = max(1, n // 3)
    head = buckets[:k]
    tail = buckets[-k:]

    def frac(bs):
        sent = sum(b["sent"] for b in bs)
        thr = sum(b["throttled"] for b in bs)
        return (thr / sent) if sent else 0.0

    h, t = frac(head), frac(tail)
    # Treat it as escalating only if the tail is meaningfully worse, so a single
    # stray rejection at the end does not flip the verdict.
    return (t > h + 0.02), h, t


def report(res: dict, retry: bool) -> None:
    thr = sum(b["throttled"] for b in res["buckets"])
    ok = sum(b["ok"] for b in res["buckets"])
    esc, head, tail = escalating(res["buckets"])
    print(f"    issued {res['issued']}  sent {res['sent']}  ok {ok}  throttled {thr}")
    print(
        "    per-window throttled: "
        + " ".join(str(b["throttled"]) for b in res["buckets"])
    )
    print(f"    first third {head * 100:.1f}% rejected, last third {tail * 100:.1f}%")
    print(f"    verdict: {'ESCALATING' if esc else 'flat'}")
    errs = {k: v for k, v in res["labels"].items() if k != "ok"}
    if errs:
        print(f"    outcomes: {errs}")


if __name__ == "__main__":
    print(f"target : {URL}")
    print(f"method : eth_call (the one Arc throttles)")
    print(f"started: {time.strftime('%Y-%m-%d %H:%M:%SZ', time.gmtime())}")
    print(f"each rate runs {RUN_S}s, bucketed per {WINDOW_S}s, {COOLDOWN_S}s between")

    print("\n=== PHASE A — which rate stays flat, retries OFF ===")
    phase_a: dict[float, dict] = {}
    for idx, rate in enumerate(RATES):
        if idx > 0:
            print(f"  (cooling down {COOLDOWN_S}s so the budget refills)", flush=True)
            time.sleep(COOLDOWN_S)
        print(f"\n  {rate} req/s:", flush=True)
        res = paced_run(rate, RUN_S, retry=False)
        phase_a[rate] = res
        report(res, retry=False)

    flat = [r for r in RATES if not escalating(phase_a[r]["buckets"])[0]]
    best = max(flat) if flat else None

    print("\n=== PHASE B — do retries come out of the same budget? ===")
    probe = best if best is not None else RATES[-1]
    print(f"  re-running {probe} req/s with retries ON, same duration")
    print(f"  (cooling down {COOLDOWN_S}s first)", flush=True)
    time.sleep(COOLDOWN_S)
    res_b = paced_run(probe, RUN_S, retry=True)
    report(res_b, retry=True)

    a = phase_a[probe]
    a_thr = sum(b["throttled"] for b in a["buckets"])
    b_thr = sum(b["throttled"] for b in res_b["buckets"])
    overhead = res_b["sent"] - res_b["issued"]

    print("\n=== SUMMARY ===")
    for rate in RATES:
        esc, h, t = escalating(phase_a[rate]["buckets"])
        thr = sum(b["throttled"] for b in phase_a[rate]["buckets"])
        print(
            f"  {rate:>4} req/s  throttled {thr:>3}  "
            f"{h * 100:>5.1f}% → {t * 100:>5.1f}%  {'ESCALATING' if esc else 'flat'}"
        )
    print(f"\n  highest flat rate: {best if best is not None else 'none of those tested'}")
    print(f"  retry overhead at {probe} req/s: {overhead} extra requests")
    print(f"  throttled without retry {a_thr}, with retry {b_thr}")
    if b_thr > a_thr + max(2, a_thr * 0.5):
        print("  -> retries DO come out of the same budget; retrying makes it worse")
    else:
        print("  -> no evidence retries are charged separately at this rate")
