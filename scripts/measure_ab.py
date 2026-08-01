#!/usr/bin/env python3
"""Separate 'which method' from 'when in time' as the cause of Arc RPC 429s.

The method-cost hypothesis died: eth_chainId (returns a constant) throttled
while eth_estimateGas (runs the EVM) did not. But the pass/fail pattern
alternated perfectly with test order, which is what a token bucket looks like
when each round drains it and the gap between rounds only partly refills it.

Design: alternate the two methods round by round with no cooldown.
  - If failures follow the METHOD, it is method-dependent.
  - If failures follow the ROUND NUMBER, it is a shared time-based budget and
    the method is irrelevant.

Whichever wins, the agent needs backoff. The point is to know what we are
backing off from, and to state it honestly in the report.
"""

import json
import ssl
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

A = ("eth_blockNumber", {"method": "eth_blockNumber", "params": []})
B = ("eth_call", {"method": "eth_call",
                  "params": [{"to": PROBE, "data": "0x7e469e54"}, "latest"]})


def call(spec):
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, **spec}).encode()
    req = urllib.request.Request(
        URL, data=payload,
        headers={"Content-Type": "application/json",
                 "User-Agent": "proof-of-break-measure/0.1"})
    try:
        with urllib.request.urlopen(req, timeout=30, context=SSL_CTX) as r:
            body = json.loads(r.read())
        return "error" not in body
    except urllib.error.HTTPError as e:
        return False
    except Exception:
        return False


def round_of(spec, n=40):
    ok = sum(1 for _ in range(n) if call(spec))
    return ok, n


if __name__ == "__main__":
    print(f"target: {URL}")
    print(f"started: {time.strftime('%Y-%m-%d %H:%M:%SZ', time.gmtime())}")
    print("\n=== A/B ALTERNATION, no cooldown, 40 calls per round ===")
    print(f"    {'round':>5} {'method':<17} {'ok':>7} {'elapsed':>8}  {'cumulative_s':>12}")

    t_start = time.monotonic()
    by_method = Counter()
    by_method_total = Counter()
    rows = []
    for rnd in range(8):
        name, spec = A if rnd % 2 == 0 else B
        t0 = time.monotonic()
        ok, n = round_of(spec)
        el = time.monotonic() - t0
        cum = time.monotonic() - t_start
        by_method[name] += ok
        by_method_total[name] += n
        rows.append((rnd, name, ok, n))
        flag = "" if ok == n else f"  <-- {n - ok} rejected"
        print(f"    {rnd:>5} {name:<17} {ok:>3}/{n} {el:>7.1f}s {cum:>11.1f}s{flag}",
              flush=True)

    print("\n=== VERDICT ===")
    for name in (A[0], B[0]):
        tot, okc = by_method_total[name], by_method[name]
        print(f"    {name:<17} {okc}/{tot} ok ({100 * okc / tot:.0f}%)")

    clean_rounds = [r for r in rows if r[2] == r[3]]
    bad_rounds = [r for r in rows if r[2] != r[3]]
    print(f"\n    clean rounds : {[r[0] for r in clean_rounds]}")
    print(f"    throttled    : {[r[0] for r in bad_rounds]}")
    a_bad = sum(1 for r in bad_rounds if r[1] == A[0])
    b_bad = sum(1 for r in bad_rounds if r[1] == B[0])
    print(f"\n    throttled rounds by method: {A[0]}={a_bad}, {B[0]}={b_bad}")
    if bad_rounds and (a_bad == 0) != (b_bad == 0):
        print("    -> failures track the METHOD")
    elif bad_rounds:
        print("    -> failures hit BOTH methods; it is a shared time-based budget")
    else:
        print("    -> no throttling observed at all this run; limit is not "
              "reproducible from the client side")
