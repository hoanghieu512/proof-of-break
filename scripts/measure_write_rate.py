#!/usr/bin/env python3
"""Find the write rate Arc's public RPC will actually honour.

The burst test established the ceiling badly: at ~27 tx/s the RPC accepted 29
of 60 transactions and then mined only 5 of them. Acceptance is not inclusion.

So this test measures both, at paced rates, submitting strictly in nonce order
so a rejection cannot strand later transactions behind a gap:

  submitted -> RPC returned a hash
  mined     -> the account nonce actually advanced past it

The number the agent should be paced at is the highest rate where those two
agree.

Usage: measure_write_rate.py SIGNED_TX_FILE ADDRESS
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


def rpc(method, params):
    payload = json.dumps({"jsonrpc": "2.0", "id": 1,
                          "method": method, "params": params}).encode()
    req = urllib.request.Request(
        URL, data=payload,
        headers={"Content-Type": "application/json",
                 "User-Agent": "proof-of-break-measure/0.1"})
    try:
        with urllib.request.urlopen(req, timeout=30, context=SSL_CTX) as r:
            body = json.loads(r.read())
        if "error" in body:
            # Do not truncate below full nonce values — a cut-off
            # "tx nonce 33" reads as "tx nonce 3" and sends you hunting the
            # wrong bug. This cost real time on Day 1.
            return False, f"rpc:{body['error'].get('code')}:{body['error'].get('message','')[:80]}"
        return True, body["result"]
    except urllib.error.HTTPError as e:
        code = None
        try:
            code = json.loads(e.read()).get("error", {}).get("code")
        except Exception:
            pass
        return False, f"http:{e.code}/{code}"
    except Exception as e:
        return False, f"exc:{type(e).__name__}"


def nonce_of(addr, block="latest"):
    ok, res = rpc("eth_getTransactionCount", [addr, block])
    return int(res, 16) if ok else None


def paced_batch(raws, rate, addr):
    interval = 1.0 / rate
    start_nonce = nonce_of(addr)
    labels = Counter()
    t0 = time.monotonic()
    for i, raw in enumerate(raws):
        target = t0 + i * interval
        now = time.monotonic()
        if target > now:
            time.sleep(target - now)
        ok, res = rpc("eth_sendRawTransaction", [raw])
        labels["ok" if ok else res] += 1
    elapsed = time.monotonic() - t0

    # Give the chain time to include them (block time ~0.5s).
    deadline = time.monotonic() + 60
    target_nonce = start_nonce + labels["ok"]
    while time.monotonic() < deadline:
        if nonce_of(addr) >= target_nonce:
            break
        time.sleep(2)
    end_nonce = nonce_of(addr)

    submitted = labels["ok"]
    mined = end_nonce - start_nonce
    errs = {k: v for k, v in labels.items() if k != "ok"} or "-"
    print(f"    {rate:>5} tx/s  submitted {submitted:>2}/{len(raws)}  "
          f"mined {mined:>2}/{len(raws)}  "
          f"({elapsed:.1f}s)  {errs}", flush=True)
    return rate, submitted, mined, len(raws)


if __name__ == "__main__":
    path, addr = sys.argv[1], sys.argv[2]
    raws = [l.strip() for l in open(path) if l.strip().startswith("0x")]
    print(f"loaded {len(raws)} pre-signed txs for {addr}")
    print("\n=== PACED WRITE RATE (nonce order, submitted vs actually mined) ===")

    rows = []
    idx = 0
    for rate in (2, 5, 10):
        batch = raws[idx:idx + 15]
        idx += 15
        if not batch:
            break
        rows.append(paced_batch(batch, rate, addr))
        time.sleep(10)

    print("\n=== VERDICT ===")
    good = [r for r in rows if r[1] == r[3] and r[2] == r[3]]
    if good:
        best = max(good, key=lambda r: r[0])
        print(f"    highest rate where submitted == mined == sent: {best[0]} tx/s")
    else:
        print("    no tested rate had submitted == mined == sent")
    for rate, sub, mined, sent in rows:
        note = "clean" if sub == mined == sent else "LOSS"
        print(f"    {rate:>5} tx/s  sent {sent}  submitted {sub}  mined {mined}  {note}")
