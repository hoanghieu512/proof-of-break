#!/usr/bin/env bash
# Puts the agent through every filtering path, on a local chain.
#
# The rejection branches cannot be exercised against Arc without destroying real
# bounties: proving "already broken" is rejected means breaking one permanently,
# and proving "already paid" is rejected means spending a claim. On a throwaway
# chain all four states can be built in seconds and thrown away.
#
# Builds a board with:
#   #0  healthy, 0.50 USDC     → viable, but not the richest
#   #1  griefed after opening  → rejected: invariant already broken
#   #2  healthy, 1.50 USDC     → viable and richest, must be the one chosen
#   #3  claimed after opening  → rejected: already paid
#
# Then runs the agent and checks it reached the right conclusion, and separately
# runs it against an empty Registry to prove it exits cleanly with nothing to do.
#
# Run: ./scripts/test-agent-scenarios.sh

set -uo pipefail
cd "$(dirname "$0")/.."

RPC="http://127.0.0.1:8545"
# Anvil's first prefunded account. Printed by anvil on every start and published
# in its docs; a fixture, not a secret, and it controls nothing off this chain.
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
echo "  chain id $CHAIN_ID"

deploy() {
  forge create "$1" --rpc-url "$RPC" --private-key "$KEY" --broadcast "${@:2}" \
    2>/dev/null | awk '/Deployed to:/ {print $3}'
}

send() { cast send "$@" --rpc-url "$RPC" --private-key "$KEY" --json >/dev/null 2>&1; }

echo "deploying the board..."
REGISTRY=$(deploy src/BountyRegistry.sol:BountyRegistry)
EMPTY_REGISTRY=$(deploy src/BountyRegistry.sol:BountyRegistry)
echo "  registry        $REGISTRY"
echo "  empty registry  $EMPTY_REGISTRY"

open_bounty() {  # $1 = reward in wei -> echoes "vault checker"
  local vault checker
  vault=$(deploy src/DemoVault.sol:DemoVault)
  checker=$(deploy src/VaultChecker.sol:VaultChecker --constructor-args "$vault")
  send "$REGISTRY" 'openBounty(address,address,string)(uint256)' \
    "$vault" "$checker" "deposit(uint256)" --value "$1"
  echo "$vault $checker"
}

read -r V0 C0 <<<"$(open_bounty 500000000000000000)"    # 0.50 USDC, stays healthy
read -r V1 C1 <<<"$(open_bounty 900000000000000000)"    # 0.90 USDC, about to be griefed
read -r V2 C2 <<<"$(open_bounty 1500000000000000000)"   # 1.50 USDC, the right answer
read -r V3 C3 <<<"$(open_bounty 700000000000000000)"    # 0.70 USDC, about to be claimed
echo "  four bounties opened"

# #1: somebody calls the target directly. The boundary value 1e18 trips the
# planted bug, and after this no attempt can ever produce the required
# intact->broken transition. This is the griefing vector from the README.
send "$V1" 'deposit(uint256)' 1000000000000000000
BROKEN=$(cast call "$C1" 'checkInvariant()(bool)' --rpc-url "$RPC")
[[ "$BROKEN" == "false" ]] && echo "  #1 griefed (checker now reports false)" \
  || { echo "setup failed: #1 is not broken"; exit 1; }

# #3: claimed properly, through the Registry, so it is marked paid.
send "$REGISTRY" 'attempt(uint256,bytes)(bool)' 3 \
  "$(cast calldata 'deposit(uint256)' 1000000000000000000)"
PAID=$(cast call "$REGISTRY" \
  'getBounty(uint256)((address,address,address,bytes4,uint256,bool,string))' 3 \
  --rpc-url "$RPC" | grep -o 'true\|false' | head -1)
[[ "$PAID" == "true" ]] && echo "  #3 claimed (bounty marked paid)" \
  || { echo "setup failed: #3 is not paid"; exit 1; }

echo
echo "=============================================================="
echo "SCENARIO A — a board with every rejection reason on it"
echo "=============================================================="
OUT=$(cd agent && CHAIN_ID="$CHAIN_ID" CHAIN_NAME="Anvil" ARC_RPC_URL="$RPC" \
  REGISTRY="$REGISTRY" npm run --silent scan 2>&1)
CODE=$?
echo "$OUT"
echo

echo "checks:"
[[ $CODE -eq 0 ]] && pass "exit code 0 (a bounty was chosen)" || fail "exit code $CODE, expected 0"

grep -q "Selected bounty #2" <<<"$OUT" \
  && pass "chose #2, the richest viable bounty" \
  || fail "did not choose #2"

grep -q "1.5 USDC" <<<"$OUT" \
  && pass "reward rendered with 18 decimals (1.5 USDC)" \
  || fail "reward not rendered correctly"

grep -A1 '#1 ' <<<"$OUT" | grep -q "invariant is already false" \
  && pass "#1 rejected for an already-broken invariant" \
  || fail "#1 not rejected with the broken-invariant reason"

# The two rejections must be distinguishable, not just both present.
grep -A1 '#1 ' <<<"$OUT" | grep -q "checker will not answer" \
  && fail "#1 confused an already-broken invariant with an unreachable checker" \
  || pass "broken-invariant and unusable-checker are reported as different things"

grep -A1 '#3 ' <<<"$OUT" | grep -q "already claimed" \
  && pass "#3 rejected as already paid" \
  || fail "#3 not rejected as already paid"

grep -q "4 bounties on the board, 2 worth attacking" <<<"$OUT" \
  && pass "counted 2 viable out of 4" \
  || fail "viable count wrong"

grep -q "next best is #0" <<<"$OUT" \
  && pass "named the runner-up, so the ranking is visible" \
  || fail "did not name a runner-up"

grep -q "arg0: uint256 — all generatable" <<<"$OUT" \
  && pass "worked out the argument type from the signature alone" \
  || fail "did not derive the argument type"

grep -q "matches the one derived from the signature" <<<"$OUT" \
  && pass "cross-checked the selector against the signature string" \
  || fail "selector cross-check missing"

echo
echo "=============================================================="
echo "SCENARIO B — an empty board"
echo "=============================================================="
OUT2=$(cd agent && CHAIN_ID="$CHAIN_ID" CHAIN_NAME="Anvil" ARC_RPC_URL="$RPC" \
  REGISTRY="$EMPTY_REGISTRY" npm run --silent scan 2>&1)
CODE2=$?
echo "$OUT2"
echo

echo "checks:"
[[ $CODE2 -eq 3 ]] && pass "exit code 3 (scanned, nothing to do)" || fail "exit code $CODE2, expected 3"
grep -q "No bounty selected" <<<"$OUT2" && pass "said so plainly" || fail "no clear statement"
grep -q "nobody has opened a bounty" <<<"$OUT2" \
  && pass "gave the specific reason" || fail "no reason given"
grep -qE "agent could not run|Uncaught|at Object\.|node:internal" <<<"$OUT2" \
  && fail "output shows an uncaught failure" \
  || pass "exited without throwing"

echo
echo "=============================================================="
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS — every filtering path behaves as designed."
  exit 0
else
  echo "FAIL — $FAILURES check(s) failed."
  exit 1
fi
