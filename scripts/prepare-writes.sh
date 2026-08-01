#!/usr/bin/env bash
# Pre-sign N bump() transactions with sequential nonces so the throughput test
# measures the RPC rather than local signing overhead.
#
# Usage: ./scripts/prepare-writes.sh CONTRACT [COUNT] [OUTFILE]

set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

CONTRACT="${1:?need contract address}"
COUNT="${2:-60}"
OUT="${3:-/private/tmp/claude-501/-Users-lavopavden-Dev-projects-Proof-of-Break/368aeb35-6837-4719-976f-4639c54d12de/scratchpad/signed-txs.txt}"

NONCE=$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$ARC_RPC_URL")
echo "signing $COUNT txs from nonce $NONCE ..."
: > "$OUT"

for (( i=0; i<COUNT; i++ )); do
  cast mktx "$CONTRACT" "bump()" \
    --rpc-url "$ARC_RPC_URL" \
    --private-key "$DEPLOYER_PRIVATE_KEY" \
    --nonce $(( NONCE + i )) >> "$OUT"
done

echo "wrote $(wc -l < "$OUT") signed txs to $OUT"
