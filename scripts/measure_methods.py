#!/usr/bin/env python3
"""Resolve a contradiction in the Day-1 RPC measurements.

A curl sweep using eth_call saw HTTP 429 "request limit reached" at ~2.5 req/s.
A Python sweep using eth_blockNumber saw 0 failures all the way to 8 req/s.
Both cannot be the whole truth. The hypothesis is that Arc's limiter prices
methods differently — eth_call executes EVM work, eth_blockNumber reads a
counter — so the budget is per-cost, not per-request.

This matters directly: the agent reads target state (eth_call) and submits
attempts (eth_sendRawTransaction). If eth_call is the scarce one, the agent's
loop has to be shaped around it.
"""

import json
import ssl
import statistics
import sys
import time
import urllib.error
import urllib.request
from collections import Counter

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from measure_rpc import _ssl_context  # noqa: E402

SSL_CTX = _ssl_context()
URL = "https://rpc.testnet.arc.network"
PROBE = "0x8850a83Fc38b87453aeB4EEDb23c10f370A3A9e5"
BUMPS_SELECTOR = "0x7e469e54"  # bumps(), from `cast sig 'bumps()'`

METHODS = {
    "eth_blockNumber": {"method": "eth_blockNumber", "params": []},
    "eth_chainId": {"method": "eth_chainId", "params": []},
    "eth_getBalance": {
        "method": "eth_getBalance",
        "params": ["0x6BA70dfb557EC0C4B7805b9728201aCC81111111", "latest"],
    },
    "eth_call": {
        "method": "eth_call",
        "params": [{"to": PROBE, "data": BUMPS_SELECTOR}, "latest"],
    },
    "eth_estimateGas": {
        "method": "eth_estimateGas",
        "params": [{"to": PROBE, "data": BUMPS_SELECTOR}],
    },
}


def call(spec):
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, **spec}).encode()
    req = urllib.request.Request(
        URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "proof-of-break-measure/0.1",
        },
    )
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=30, context=SSL_CTX) as r:
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
    except Exception as e:
        return False, f"exc:{type(e).__name__}", time.monotonic() - t0


def flat_out(name, spec, n=60):
    """Sequential, no pacing — the exact shape that failed under curl."""
    labels, lats = Counter(), []
    t0 = time.monotonic()
    first_fail = None
    for i in range(n):
        ok, label, dt = call(spec)
        labels[label] += 1
        if ok:
            lats.append(dt)
        elif first_fail is None:
            first_fail = i + 1
    el = time.monotonic() - t0
    errs = {k: v for k, v in labels.items() if k != "ok"} or "-"
    p50 = statistics.median(lats) * 1000 if lats else float("nan")
    print(f"    {name:<17} {labels['ok']:>3}/{n}  {n / el:>5.1f} req/s  "
          f"p50 {p50:>5.0f}ms  first_fail@{str(first_fail):<5} {errs}", flush=True)
    return labels["ok"], n, errs


if __name__ == "__main__":
    print(f"target: {URL}")
    print(f"started: {time.strftime('%Y-%m-%d %H:%M:%SZ', time.gmtime())}")
    print("\n=== METHOD COST COMPARISON (60 sequential calls, flat out) ===")
    print(f"    {'method':<17} {'ok':>6}  {'rate':>11}  {'latency':>10}  first failure")
    results = {}
    for name, spec in METHODS.items():
        results[name] = flat_out(name, spec)
        print("    (cooling down 20s)", flush=True)
        time.sleep(20)

    print("\n=== VERDICT ===")
    for name, (ok, n, errs) in results.items():
        status = "clean" if ok == n else f"THROTTLED ({n - ok}/{n} rejected) {errs}"
        print(f"    {name:<17} {status}")
