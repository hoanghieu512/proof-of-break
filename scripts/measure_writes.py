#!/usr/bin/env python3
"""Find the real eth_sendRawTransaction ceiling on Arc's public RPC.

The first write measurement reported 0.8 tx/s with zero rejections, but that
number measured `cast send` process startup, not the RPC. To measure the RPC,
transactions are signed up front and then fired as raw bytes with nothing in
the hot path but the HTTP request.

Reads pre-signed transactions from a file (one 0x-prefixed raw tx per line,
in nonce order) produced by prepare-writes.sh.
"""

import json
import ssl
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from measure_rpc import _ssl_context  # noqa: E402

SSL_CTX = _ssl_context()
URL = "https://rpc.testnet.arc.network"


def send_raw(raw):
    payload = json.dumps({
        "jsonrpc": "2.0", "id": 1,
        "method": "eth_sendRawTransaction", "params": [raw],
    }).encode()
    req = urllib.request.Request(
        URL, data=payload,
        headers={"Content-Type": "application/json",
                 "User-Agent": "proof-of-break-measure/0.1"})
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=30, context=SSL_CTX) as r:
            body = json.loads(r.read())
        dt = time.monotonic() - t0
        if "error" in body:
            msg = body["error"].get("message", "")[:60]
            return False, f"rpc:{body['error'].get('code')}:{msg}", dt
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


if __name__ == "__main__":
    path = sys.argv[1]
    concurrency = int(sys.argv[2]) if len(sys.argv) > 2 else 20

    raws = [l.strip() for l in open(path) if l.strip().startswith("0x")]
    print(f"loaded {len(raws)} pre-signed transactions")
    print(f"firing all of them at concurrency {concurrency}")

    t0 = time.monotonic()
    with ThreadPoolExecutor(max_workers=concurrency) as ex:
        results = list(ex.map(send_raw, raws))
    elapsed = time.monotonic() - t0

    labels = Counter(r[1] if not r[0] else "ok" for r in results)
    ok = labels["ok"]
    print(f"\nsubmitted {ok}/{len(raws)} accepted in {elapsed:.2f}s")
    print(f"submission rate: {len(raws) / elapsed:.1f} tx/s attempted, "
          f"{ok / elapsed:.1f} tx/s accepted")
    print(f"outcomes: {dict(labels)}")
    lat = sorted(r[2] for r in results)
    if lat:
        print(f"latency p50 {lat[len(lat) // 2] * 1000:.0f}ms  "
              f"p95 {lat[int(len(lat) * 0.95)] * 1000:.0f}ms  "
              f"max {lat[-1] * 1000:.0f}ms")
