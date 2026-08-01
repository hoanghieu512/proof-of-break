#!/usr/bin/env bash
# Converts a tx hash into its real cost in USDC on Arc.
#
# Arc's native gas unit has 18 decimals even though the ERC-20 view of USDC
# shows 6. So cost_in_USDC = gasUsed * effectiveGasPrice / 1e18.
# The project's whole economic claim is "sub-cent per attempt" — this prints
# the number that claim has to survive.
#
# Usage: ./scripts/tx-cost.sh 0xTXHASH

set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

TX="${1:?need a tx hash}"
RCPT=$(cast receipt "$TX" --rpc-url "$ARC_RPC_URL" --json)

GAS_USED=$(cast to-dec "$(printf '%s' "$RCPT" | jq -r '.gasUsed')")
GAS_PRICE=$(cast to-dec "$(printf '%s' "$RCPT" | jq -r '.effectiveGasPrice')")
STATUS=$(printf '%s' "$RCPT" | jq -r '.status')
BLOCK=$(cast to-dec "$(printf '%s' "$RCPT" | jq -r '.blockNumber')")

WEI=$(python3 -c "print($GAS_USED * $GAS_PRICE)")

python3 - "$TX" "$STATUS" "$BLOCK" "$GAS_USED" "$GAS_PRICE" "$WEI" <<'PY'
import sys
tx, status, block, gas_used, gas_price, wei = sys.argv[1:7]
gas_used, gas_price, wei = int(gas_used), int(gas_price), int(wei)
usdc = wei / 10**18
print(f"tx           : {tx}")
print(f"status       : {'success' if status in ('0x1','1') else 'FAILED ' + status}")
print(f"block        : {block}")
print(f"gasUsed      : {gas_used:,}")
print(f"gasPrice     : {gas_price/10**9:.2f} gwei")
print(f"cost (wei18) : {wei:,}")
print(f"cost (USDC)  : {usdc:.9f}")
print(f"cost (US ct) : {usdc*100:.6f} cents")
print(f"sub-cent?    : {'YES' if usdc < 0.01 else 'NO'}")
print(f"1,000 attempts would cost: {usdc*1000:.6f} USDC")
PY
