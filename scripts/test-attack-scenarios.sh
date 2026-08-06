#!/usr/bin/env bash
# Exercises the end-to-end attack on a local chain: break, get paid, stop, and
# on a re-run skip the bounty just claimed. Also confirms the dangerous case the
# two-tier retry exists for — an attempt against an already-paid bounty — is
# filtered rather than misread as failure.
#
# On Arc these paths would each cost a real, unrecoverable bounty. On anvil they
# are free and repeatable.
#
# Run: ./scripts/test-attack-scenarios.sh

set -uo pipefail
cd "$(dirname "$0")/.."

RPC="http://127.0.0.1:8545"
KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
FAILURES=0

pass() { echo "  ok  : $*"; }
fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

ANVIL_PID=""
cleanup() { [[ -n "$ANVIL_PID" ]] && kill "$ANVIL_PID" 2>/dev/null; }
trap cleanup EXIT

echo "starting a local chain..."
anvil --silent --port 8545 &
ANVIL_PID=$!
for _ in $(seq 1 40); do
  cast chain-id --rpc-url "$RPC" >/dev/null 2>&1 && break
  sleep 0.5
done
cast chain-id --rpc-url "$RPC" >/dev/null 2>&1 || { echo "anvil did not start"; exit 1; }
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")

deploy() {
  forge create "$1" --rpc-url "$RPC" --private-key "$KEY" --broadcast "${@:2}" \
    2>/dev/null | awk '/Deployed to:/ {print $3}'
}
send() { cast send "$@" --rpc-url "$RPC" --private-key "$KEY" --json >/dev/null 2>&1; }

echo "deploying two bounties (0.5 and 1.5 USDC)..."
REGISTRY=$(deploy src/BountyRegistry.sol:BountyRegistry)
for reward in 500000000000000000 1500000000000000000; do
  V=$(deploy src/DemoVault.sol:DemoVault)
  C=$(deploy src/VaultChecker.sol:VaultChecker --constructor-args "$V")
  send "$REGISTRY" 'openBounty(address,address,string)(uint256)' "$V" "$C" "deposit(uint256)" --value "$reward"
done
set -a; source .env; set +a
cast rpc anvil_setBalance "$AGENT_ADDRESS" 0x3635C9ADC5DEA00000 --rpc-url "$RPC" >/dev/null 2>&1
echo "  registry $REGISTRY, agent funded"

run_attack() {
  (cd agent && CHAIN_ID="$CHAIN_ID" CHAIN_NAME="Anvil" ARC_RPC_URL="$RPC" \
    REGISTRY="$REGISTRY" STRATEGY=boundary-first npm run --silent attack 2>&1)
}

echo
echo "=============================================================="
echo "RUN 1 — should break the richer bounty (#1, 1.5 USDC) and stop"
echo "=============================================================="
OUT1=$(run_attack); CODE1=$?
echo "$OUT1" | grep -E 'chose #|broke on probe|reward|bounty #.* is now marked paid|BROKE THE'
echo
[[ $CODE1 -eq 0 ]] && pass "exit 0 (claimed)" || fail "exit $CODE1"
grep -q "chose #1" <<<"$OUT1" && pass "chose the richer bounty #1" || fail "did not choose #1"
grep -q "broke on probe   6" <<<"$OUT1" && pass "broke on probe 6" || fail "did not break on probe 6"
# Stopped after one: it must not have gone on to mention #0 as broken.
BREAKS=$(grep -c "BROKE THE INVARIANT" <<<"$OUT1")
[[ "$BREAKS" -eq 1 ]] && pass "stopped after a single break (did not roll on to #0)" \
  || fail "broke $BREAKS bounties in one run; must stop after one"

echo
echo "=============================================================="
echo "RUN 2 — scan must skip the paid #1 and attack #0 instead"
echo "=============================================================="
OUT2=$(run_attack); CODE2=$?
echo "$OUT2" | grep -E 'rejected: already|chose #|broke on probe'
echo
[[ $CODE2 -eq 0 ]] && pass "exit 0 (claimed the second)" || fail "exit $CODE2"
grep -q "#1 .*already claimed" <<<"$OUT2" && pass "#1 skipped as already claimed" \
  || fail "#1 not skipped"
grep -q "chose #0" <<<"$OUT2" && pass "moved on to #0" || fail "did not choose #0"

echo
echo "=============================================================="
echo "RUN 3 — nothing left; must exit cleanly, not hang or throw"
echo "=============================================================="
OUT3=$(run_attack); CODE3=$?
echo "$OUT3" | grep -E 'rejected: already|No bounty worth'
echo
[[ $CODE3 -eq 3 ]] && pass "exit 3 (scanned, nothing to do)" || fail "exit $CODE3, expected 3"
grep -q "No bounty worth attacking" <<<"$OUT3" && pass "said so plainly" || fail "no clear message"
grep -qE "agent could not run|Uncaught|node:internal" <<<"$OUT3" && fail "threw" || pass "did not throw"

echo
echo "=============================================================="
echo "SAFETY — an attempt at an already-paid bounty is filtered, not misread"
echo "=============================================================="
# This is the exact hazard the two-tier retry guards against: if a first send
# broke a bounty but its response was lost, a naive retry hits a now-paid bounty
# and reverts, and a naive agent reads that as "I failed". Confirm the direct
# on-chain behaviour: attempting a paid bounty reverts (so estimateGas reverts,
# so the agent filters it as would-revert rather than a failed break).
BROKEN_ID=1
CALLDATA=$(cast calldata 'deposit(uint256)' 1000000000000000000)
if cast estimate "$REGISTRY" 'attempt(uint256,bytes)' "$BROKEN_ID" "$CALLDATA" \
     --rpc-url "$RPC" --from "$AGENT_ADDRESS" >/dev/null 2>&1; then
  fail "attempt on a paid bounty did NOT revert — the retry hazard is real here"
else
  pass "attempt on a paid bounty reverts, so the agent filters it (never misread as failure)"
fi

echo
echo "=============================================================="
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS — break, get paid, stop, skip-on-rerun, and the retry hazard is closed."
  exit 0
else
  echo "FAIL — $FAILURES check(s) failed."
  exit 1
fi
