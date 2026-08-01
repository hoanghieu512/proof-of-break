#!/usr/bin/env python3
"""Day-1 kill-gate: characterise the Arc public RPC rate limit.

The project assumes an agent can fire attempts in a loop. The first crude
sweep showed 429s even at ~2.5 req/s, so this measures properly:

  1. burst capacity  - from cold, how many back-to-back calls land before the
                       first rejection
  2. sustainable rate - paced request rates, measured failure rate at each
  3. recovery        - after exhausting the budget, how long until it heals
  4. endpoint compare - the public endpoints are not necessarily equal

Standard library only; adds no dependencies.
"""

import json
import os
import ssl
import statistics
import sys
import time
import urllib.error
import urllib.request
from collections import Counter

TIMEOUT = 30

# This Python has no usable CA bundle of its own on macOS, so every HTTPS call
# fails with CERTIFICATE_VERIFY_FAILED and looks exactly like a network outage.
# Bind the context to a bundle that exists, or the measurement measures nothing.
def _ssl_context():
    candidates = []
    try:
        import certifi
        candidates.append(certifi.where())
    except ImportError:
        pass
    candidates += ["/etc/ssl/cert.pem", "/usr/local/etc/ca-certificates/cert.pem"]
    for path in candidates:
        if path and os.path.exists(path):
            return ssl.create_default_context(cafile=path)
    raise RuntimeError("no CA bundle found; refusing to measure over an unverified channel")


SSL_CTX = _ssl_context()

ENDPOINTS = {
    "arc.network": "https://rpc.testnet.arc.network",
    "arc.io": "https://rpc.testnet.arc.io",
    "blockdaemon": "https://rpc.blockdaemon.testnet.arc.io",
    "drpc": "https://rpc.drpc.testnet.arc.io",
    "quicknode": "https://rpc.quicknode.testnet.arc.io",
}

PAYLOAD = json.dumps(
    {"jsonrpc": "2.0", "id": 1, "method": "eth_blockNumber", "params": []}
).encode()


def call(url):
    """Return (ok: bool, label: str, latency_s: float)."""
    t0 = time.monotonic()
    # Arc's public RPC returns 403 for the default "Python-urllib/x.y" agent
    # (a WAF anti-scraper rule). Any other UA is accepted. Identify honestly.
    req = urllib.request.Request(
        url,
        data=PAYLOAD,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "proof-of-break-measure/0.1",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=SSL_CTX) as r:
            body = json.loads(r.read())
        dt = time.monotonic() - t0
        if "error" in body:
            return False, f"rpc:{body['error'].get('code')}", dt
        return True, "ok", dt
    except urllib.error.HTTPError as e:
        dt = time.monotonic() - t0
        code = None
        try:
            code = json.loads(e.read()).get("error", {}).get("code")
        except Exception:
            pass
        return False, f"http:{e.code}/{code}", dt
    except Exception as e:  # timeout, connection reset, DNS
        return False, f"exc:{type(e).__name__}", time.monotonic() - t0


def cooldown(seconds, why):
    print(f"    (cooling down {seconds}s so {why})", flush=True)
    time.sleep(seconds)


def burst_capacity(url, cap=120):
    """From cold: how many sequential calls succeed before the first failure."""
    print("\n=== 1. BURST CAPACITY (sequential, as fast as possible) ===")
    first_fail = None
    labels = Counter()
    t0 = time.monotonic()
    for i in range(cap):
        ok, label, _ = call(url)
        labels[label] += 1
        if not ok and first_fail is None:
            first_fail = i
            print(f"    first rejection at request #{i + 1} "
                  f"(t={time.monotonic() - t0:.2f}s) -> {label}")
    elapsed = time.monotonic() - t0
    ok_n = labels["ok"]
    print(f"    {ok_n}/{cap} ok in {elapsed:.2f}s "
          f"({cap / elapsed:.1f} req/s attempted, {ok_n / elapsed:.1f} req/s landed)")
    print(f"    outcomes: {dict(labels)}")
    return first_fail, ok_n, elapsed


def paced(url, rate, duration=20.0):
    """Issue requests at a fixed rate; report the failure rate."""
    interval = 1.0 / rate
    n = int(duration * rate)
    labels = Counter()
    lats = []
    start = time.monotonic()
    for i in range(n):
        target = start + i * interval
        now = time.monotonic()
        if target > now:
            time.sleep(target - now)
        ok, label, dt = call(url)
        labels[label] += 1
        if ok:
            lats.append(dt)
    elapsed = time.monotonic() - start
    ok_n = labels["ok"]
    p50 = statistics.median(lats) if lats else float("nan")
    return {
        "rate": rate, "sent": n, "ok": ok_n, "failed": n - ok_n,
        "pct_ok": 100.0 * ok_n / n if n else 0.0,
        "elapsed": elapsed, "p50_ms": p50 * 1000,
        "labels": dict(labels),
    }


def sustainable_rate(url):
    print("\n=== 2. SUSTAINABLE RATE (paced, 20s per step) ===")
    print(f"    {'rate':>6} {'sent':>5} {'ok':>5} {'fail':>5} {'ok%':>6} {'p50ms':>7}  errors")
    rows = []
    for rate in (0.5, 1, 2, 3, 5, 8):
        cooldown(15, "each step starts from a comparable budget")
        r = paced(url, rate)
        rows.append(r)
        errs = {k: v for k, v in r["labels"].items() if k != "ok"} or "-"
        print(f"    {r['rate']:>6} {r['sent']:>5} {r['ok']:>5} {r['failed']:>5} "
              f"{r['pct_ok']:>5.0f}% {r['p50_ms']:>7.0f}  {errs}", flush=True)
    return rows


def recovery(url):
    """Exhaust the budget, then poll slowly to see how fast it heals."""
    print("\n=== 3. RECOVERY AFTER EXHAUSTION ===")
    fails = 0
    for _ in range(80):
        ok, _, _ = call(url)
        if not ok:
            fails += 1
    print(f"    drained with 80 rapid calls ({fails} rejected)")
    t0 = time.monotonic()
    for probe in range(40):
        time.sleep(2)
        ok, label, _ = call(url)
        if ok:
            print(f"    healed after {time.monotonic() - t0:.1f}s "
                  f"({probe + 1} probes at 2s spacing)")
            return time.monotonic() - t0
    print("    still rejecting after 80s")
    return None


def compare_endpoints():
    print("\n=== 4. ENDPOINT COMPARISON (30 sequential calls each, cold) ===")
    print(f"    {'endpoint':<14} {'ok':>6} {'req/s':>7} {'p50ms':>7}  errors")
    results = {}
    for name, url in ENDPOINTS.items():
        labels = Counter()
        lats = []
        t0 = time.monotonic()
        for _ in range(30):
            ok, label, dt = call(url)
            labels[label] += 1
            if ok:
                lats.append(dt)
        elapsed = time.monotonic() - t0
        p50 = statistics.median(lats) * 1000 if lats else float("nan")
        errs = {k: v for k, v in labels.items() if k != "ok"} or "-"
        print(f"    {name:<14} {labels['ok']:>4}/30 {30 / elapsed:>7.1f} {p50:>7.0f}  {errs}",
              flush=True)
        results[name] = {"ok": labels["ok"], "rate": 30 / elapsed,
                         "p50_ms": p50, "errors": errs}
        cooldown(10, "the next endpoint is not judged on this one's backlog")
    return results


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else ENDPOINTS["arc.network"]
    print(f"target: {target}")
    print(f"started: {time.strftime('%Y-%m-%d %H:%M:%SZ', time.gmtime())}")

    burst = burst_capacity(target)
    cooldown(20, "the sustained-rate test is not polluted by the burst test")
    rows = sustainable_rate(target)
    cooldown(20, "recovery starts from a known state")
    heal = recovery(target)
    cooldown(20, "endpoint comparison starts clean")
    eps = compare_endpoints()

    print("\n=== SUMMARY ===")
    good = [r for r in rows if r["pct_ok"] >= 99]
    if good:
        best = max(good, key=lambda r: r["rate"])
        print(f"highest rate with >=99% success: {best['rate']} req/s")
    else:
        best = max(rows, key=lambda r: r["pct_ok"])
        print(f"no rate reached 99% success; best was {best['rate']} req/s "
              f"at {best['pct_ok']:.0f}%")
    print(f"burst before first rejection: {burst[0]}")
    print(f"recovery: {heal}")
