#!/usr/bin/env bash
# Day-1 kill-gate measurement: how hard can we hit the public Arc RPC before
# it pushes back? The whole project assumes an agent can fire transactions in
# a tight loop, so this is measured, not assumed.
#
# Usage:
#   ./scripts/measure-rpc.sh reads  [CONTRACT_ADDRESS]
#   ./scripts/measure-rpc.sh writes CONTRACT_ADDRESS [COUNT]
#
# Adds no dependencies: curl + cast + jq only.

set -uo pipefail
cd "$(dirname "$0")/.."

set -a; source .env; set +a
RPC="${ARC_RPC_URL}"
OUT="${OUT_DIR:-docs/measurements}"
mkdir -p "$OUT"

# --- helpers ---------------------------------------------------------------

# Fire one JSON-RPC request, print "HTTP_CODE<TAB>BODY_FLAG".
# BODY_FLAG is "ok" or the JSON-RPC error message, so rate-limit responses that
# arrive as HTTP 200 with an error body are not silently counted as successes.
rpc_once() {
  local payload="$1"
  local resp code body
  resp=$(curl -s -m 30 -w '\n%{http_code}' -X POST "$RPC" \
           -H 'Content-Type: application/json' -d "$payload" 2>&1)
  code=$(printf '%s' "$resp" | tail -1)
  body=$(printf '%s' "$resp" | sed '$d')
  if [[ "$code" != "200" ]]; then
    printf '%s\tHTTP_%s: %s\n' "$code" "$code" "$(printf '%s' "$body" | head -c 160)"
  elif printf '%s' "$body" | jq -e '.error' >/dev/null 2>&1; then
    printf '%s\tRPC_ERROR: %s\n' "$code" "$(printf '%s' "$body" | jq -c '.error')"
  else
    printf '%s\tok\n' "$code"
  fi
}
export -f rpc_once
export RPC

# --- read burst ------------------------------------------------------------
# Sweeps concurrency levels. At each level fires a fixed number of requests as
# fast as the level allows, then reports achieved req/s and the failure count.

measure_reads() {
  local contract="${1:-}"
  local payload
  if [[ -n "$contract" ]]; then
    # eth_call on the probe's bumps() getter — matches what the agent will do
    # between attempts (read target state to evaluate the invariant).
    local selector
    selector=$(cast sig "bumps()")
    payload="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$contract\",\"data\":\"$selector\"},\"latest\"]}"
    echo "read workload: eth_call bumps() on $contract"
  else
    payload='{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}'
    echo "read workload: eth_blockNumber (no contract given)"
  fi

  local report="$OUT/rpc-reads.tsv"
  printf 'concurrency\trequests\tseconds\treq_per_sec\tok\tfailed\tfirst_error\n' > "$report"

  local n=60
  for c in 1 2 5 10 20 50 100; do
    local start end elapsed rate ok fail firsterr results
    start=$(python3 -c 'import time;print(time.time())')
    results=$(seq "$n" | xargs -P "$c" -I{} bash -c 'rpc_once "$0"' "$payload")
    end=$(python3 -c 'import time;print(time.time())')
    elapsed=$(python3 -c "print(f'{$end-$start:.2f}')")
    rate=$(python3 -c "print(f'{$n/($end-$start):.1f}')")
    ok=$(printf '%s\n' "$results" | grep -c $'\tok$')
    fail=$(( n - ok ))
    firsterr=$(printf '%s\n' "$results" | grep -v $'\tok$' | head -1 | cut -f2- | head -c 120)
    [[ -z "$firsterr" ]] && firsterr="-"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$c" "$n" "$elapsed" "$rate" "$ok" "$fail" "$firsterr" \
      | tee -a "$report"
  done
  echo "--> $report"
}

# --- write burst -----------------------------------------------------------
# Sends COUNT bump() transactions back-to-back with explicit sequential nonces
# and --async (do not wait for receipts), which is the fastest an agent could
# realistically submit. Then waits and checks how many actually got mined.

measure_writes() {
  local contract="$1"
  local count="${2:-20}"
  local report="$OUT/rpc-writes.tsv"

  local nonce
  nonce=$(cast nonce "$DEPLOYER_ADDRESS" --rpc-url "$RPC")
  echo "starting nonce: $nonce, sending $count bump() txs as fast as possible"

  printf 'idx\tnonce\tsubmit_ms\tstatus\ttx_or_error\n' > "$report"

  local start_all
  start_all=$(python3 -c 'import time;print(time.time())')

  local i hashes=()
  for (( i=0; i<count; i++ )); do
    local n=$(( nonce + i )) t0 t1 ms out rc
    t0=$(python3 -c 'import time;print(time.time())')
    out=$(cast send "$contract" "bump()" \
            --rpc-url "$RPC" \
            --private-key "$DEPLOYER_PRIVATE_KEY" \
            --nonce "$n" --async 2>&1)
    rc=$?
    t1=$(python3 -c 'import time;print(time.time())')
    ms=$(python3 -c "print(f'{($t1-$t0)*1000:.0f}')")
    if [[ $rc -eq 0 && "$out" == 0x* ]]; then
      printf '%s\t%s\t%s\tSUBMITTED\t%s\n' "$i" "$n" "$ms" "$out" | tee -a "$report"
      hashes+=("$out")
    else
      printf '%s\t%s\t%s\tREJECTED\t%s\n' "$i" "$n" "$ms" "$(printf '%s' "$out" | tr '\n' ' ' | head -c 200)" | tee -a "$report"
    fi
  done

  local end_all elapsed
  end_all=$(python3 -c 'import time;print(time.time())')
  elapsed=$(python3 -c "print(f'{$end_all-$start_all:.2f}')")
  echo "submitted ${#hashes[@]}/$count in ${elapsed}s -> $(python3 -c "print(f'{${#hashes[@]}/($end_all-$start_all):.1f}')") tx/s submission rate"

  # Receipts do not exist the instant a tx is accepted into the mempool, so
  # poll with a deadline instead of asking once and calling an unmined tx lost.
  echo "waiting for receipts (up to 120s)..."
  local mined=0 total_gas=0 first_block=0 last_block=0 h
  for h in "${hashes[@]}"; do
    local rcpt="" deadline=$(( SECONDS + 120 ))
    while (( SECONDS < deadline )); do
      rcpt=$(cast receipt "$h" --rpc-url "$RPC" --json 2>/dev/null)
      if [[ -n "$rcpt" ]] && printf '%s' "$rcpt" | jq -e '.blockNumber != null' >/dev/null 2>&1; then
        break
      fi
      rcpt=""
      sleep 2
    done
    if [[ -n "$rcpt" ]]; then
      local st gu bn
      st=$(printf '%s' "$rcpt" | jq -r '.status')
      gu=$(cast to-dec "$(printf '%s' "$rcpt" | jq -r '.gasUsed')")
      bn=$(cast to-dec "$(printf '%s' "$rcpt" | jq -r '.blockNumber')")
      (( first_block == 0 || bn < first_block )) && first_block=$bn
      (( bn > last_block )) && last_block=$bn
      if [[ "$st" == "0x1" ]]; then
        mined=$(( mined + 1 ))
        total_gas=$(( total_gas + gu ))
      fi
    fi
  done
  echo "mined OK: $mined/${#hashes[@]}"
  if (( mined > 0 )); then
    echo "avg gasUsed per bump(): $(( total_gas / mined ))"
    echo "spread across blocks : $first_block .. $last_block ($(( last_block - first_block + 1 )) blocks)"
    echo "txs per block        : $(python3 -c "print(f'{$mined/($last_block-$first_block+1):.1f}')")"
  fi
  echo "--> $report"
}

case "${1:-}" in
  reads)  measure_reads "${2:-}" ;;
  writes) [[ -n "${2:-}" ]] || { echo "need contract address"; exit 1; }
          measure_writes "$2" "${3:-20}" ;;
  *) echo "usage: $0 reads [CONTRACT] | writes CONTRACT [COUNT]"; exit 1 ;;
esac
