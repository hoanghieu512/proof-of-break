#!/usr/bin/env bash
# The head-to-head the pitch rests on: boundary-first finds the bug almost at
# once, random search effectively never does. Same agent, same generator, same
# total ignorance of the target — only the strategy differs.
#
# Runs on a local chain so the control (thousands of random draws) costs nothing
# and finishes in seconds. Reproduces the numbers in
# docs/measurements/task1-findability.md live, on demand.
#
#   boundary-first : real attacks against a real vault on anvil, until it breaks
#   random-only    : the SAME generator drawn 10,000 times, counting hits on the
#                    value the boundary run just proved breaks the target
#
# Run: ./scripts/compare-strategies.sh

set -uo pipefail
cd "$(dirname "$0")/.."

RPC="http://127.0.0.1:8545"
KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
DRAWS="${DRAWS:-10000}"
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

echo "deploying a single bounty..."
REGISTRY=$(deploy src/BountyRegistry.sol:BountyRegistry)
VAULT=$(deploy src/DemoVault.sol:DemoVault)
CHECKER=$(deploy src/VaultChecker.sol:VaultChecker --constructor-args "$VAULT")
cast send "$REGISTRY" 'openBounty(address,address,string)(uint256)' \
  "$VAULT" "$CHECKER" "deposit(uint256)" --value 1000000000000000000 \
  --rpc-url "$RPC" --private-key "$KEY" --json >/dev/null 2>&1
echo "  registry $REGISTRY   bounty 0 @ 1.0 unit"

# Fund the agent's own wallet on this throwaway chain so it can pay gas.
set -a; source .env; set +a
cast rpc anvil_setBalance "$AGENT_ADDRESS" 0x3635C9ADC5DEA00000 --rpc-url "$RPC" >/dev/null 2>&1
echo "  funded agent $AGENT_ADDRESS"

echo
echo "=============================================================="
echo "BOUNDARY-FIRST — real attacks on anvil"
echo "=============================================================="
OUT=$(cd agent && CHAIN_ID="$CHAIN_ID" CHAIN_NAME="Anvil" ARC_RPC_URL="$RPC" \
  REGISTRY="$REGISTRY" STRATEGY=boundary-first npm run --silent attack 2>&1)
CODE=$?
echo "$OUT"
echo

echo "checks:"
[[ $CODE -eq 0 ]] && pass "broke a bounty and got paid (exit 0)" || fail "exit $CODE, expected 0"

PROBE=$(grep -oE 'broke on probe +[0-9]+' <<<"$OUT" | grep -oE '[0-9]+' | head -1)
WINNING=$(grep -oE 'broke on probe +[0-9]+ +\([0-9]+' <<<"$OUT" | grep -oE '[0-9]+$' | head -1)
echo "  boundary reached the bug on probe: ${PROBE:-?}, winning value: ${WINNING:-?}"

[[ -n "$PROBE" && "$PROBE" -le 8 ]] \
  && pass "boundary-first found it early (probe $PROBE ≤ 8)" \
  || fail "boundary-first did not find it early"

[[ "$WINNING" == "1000000000000000000" ]] \
  && pass "the breaking value is 1e18, one whole unit at 18 decimals" \
  || fail "unexpected breaking value: $WINNING"

echo
echo "=============================================================="
echo "RANDOM-ONLY — $DRAWS draws from the same generator"
echo "=============================================================="
if [[ -z "$WINNING" ]]; then
  fail "no winning value discovered; cannot run the control"
else
  OUT2=$(cd agent && TARGET_VALUE="$WINNING" DRAWS="$DRAWS" \
    npx --no-install tsx src/compare-random.ts 2>&1)
  CODE2=$?
  echo "$OUT2"
  echo
  echo "checks:"
  [[ $CODE2 -eq 0 ]] && pass "random-only hit the value 0 times in $DRAWS draws" \
    || fail "random-only unexpectedly hit the value"
fi

echo
echo "=============================================================="
echo "VERDICT"
echo "=============================================================="
echo "  boundary-first : found the bug on probe ${PROBE:-?}"
echo "  random-only    : 0 hits in $DRAWS draws"
echo "  same agent, same generator, same blind target — only the strategy differs."
echo
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS — the comparison reproduces docs/measurements/task1-findability.md."
  exit 0
else
  echo "FAIL — $FAILURES check(s) failed."
  exit 1
fi
