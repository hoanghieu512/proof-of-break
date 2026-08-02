#!/usr/bin/env bash
# Confirms a deployment actually exists on Arc, by reading it back from the
# chain rather than trusting what the deploy script printed.
#
# Two Day-1 findings shape this:
#
#   1. A transaction hash is not a promise of inclusion. Everything here is
#      checked against mined state — code at the address, values in storage.
#   2. eth_call is rate-limited at roughly 2.2 req/s while eth_blockNumber and
#      eth_getBalance are not (docs/measurements/day1-report.md). Every read
#      below is an eth_call, so they are paced.
#
# Run: REGISTRY=0x... ./scripts/verify-deployment.sh

set -uo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

REGISTRY="${REGISTRY:?set REGISTRY=0x...}"
RPC="${ARC_RPC_URL}"
PACE="${PACE:-0.6}" # seconds between eth_calls -> ~1.6 req/s, under the limit
FAILURES=0

fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ok  : $*"; }

# One paced eth_call.
call() {
  sleep "$PACE"
  cast call "$@" --rpc-url "$RPC" 2>/dev/null
}

echo "Verifying deployment at $REGISTRY on chain $(cast chain-id --rpc-url "$RPC")"
echo

echo "[1] the Registry is really deployed"
CODE_SIZE=$(cast codesize "$REGISTRY" --rpc-url "$RPC" 2>/dev/null)
echo "      runtime code size: ${CODE_SIZE:-0} bytes"
if [[ "${CODE_SIZE:-0}" -gt 0 ]]; then
  pass "there is contract code at this address"
else
  fail "no code at $REGISTRY — the deployment did not land"
  exit 1
fi

echo "[2] units"
ONE_USDC=$(call "$REGISTRY" 'ONE_USDC()(uint256)' | awk '{print $1}')
if [[ "$ONE_USDC" == "1000000000000000000" ]]; then
  pass "ONE_USDC = 1e18, matching Arc's 18-decimal native USDC"
else
  fail "ONE_USDC reads $ONE_USDC, expected 1000000000000000000"
fi

echo "[3] the bounty board"
COUNT=$(call "$REGISTRY" 'bountyCount()(uint256)' | awk '{print $1}')
OPEN_IDS=$(call "$REGISTRY" 'openBountyIds()(uint256[])')
echo "      bountyCount   : $COUNT"
echo "      openBountyIds : $OPEN_IDS"
if [[ "${COUNT:-0}" -gt 1 ]]; then
  pass "more than one bounty exists, so an agent has a choice to make"
else
  fail "expected several bounties, found ${COUNT:-0}"
fi

echo "[4] escrow accounting agrees with the chain"
ESCROW=$(call "$REGISTRY" 'totalEscrowed()(uint256)' | awk '{print $1}')
sleep "$PACE"
BALANCE=$(cast balance "$REGISTRY" --rpc-url "$RPC")
echo "      totalEscrowed : $ESCROW"
echo "      balance       : $BALANCE"
if [[ "$ESCROW" == "$BALANCE" ]]; then
  pass "books match the on-chain balance exactly"
else
  fail "books say $ESCROW, chain says $BALANCE"
fi

echo "[5] every bounty, read individually"
TOTAL_FROM_BOUNTIES=0
TARGETS=()
CHECKERS=()
for (( i=0; i<COUNT; i++ )); do
  B=$(call "$REGISTRY" \
        'getBounty(uint256)((address,address,address,bytes4,uint256,bool,string))' "$i")
  TARGET=$(printf '%s' "$B" | sed -E 's/^\(([^,]*), ([^,]*), ([^,]*), ([^,]*), ([^ ]*).*/\2/')
  CHECKER=$(printf '%s' "$B" | sed -E 's/^\(([^,]*), ([^,]*), ([^,]*), ([^,]*), ([^ ]*).*/\3/')
  REWARD=$(printf '%s' "$B" | sed -E 's/.*, ([0-9]+) \[.*/\1/')
  PAID=$(printf '%s' "$B" | grep -o 'true\|false' | head -1)
  printf '      #%s target=%s checker=%s reward=%s paid=%s\n' \
    "$i" "$TARGET" "$CHECKER" "$REWARD" "$PAID"

  # Each bounty must have its own target. Sharing one would mean a single
  # griefing call could kill several bounties at once.
  if [[ ${#TARGETS[@]} -gt 0 ]] && printf '%s\n' "${TARGETS[@]}" | grep -qix "$TARGET"; then
    fail "target $TARGET is used by more than one bounty"
  fi
  TARGETS+=("$TARGET")
  CHECKERS+=("$CHECKER")

  [[ "$PAID" == "false" ]] && TOTAL_FROM_BOUNTIES=$((TOTAL_FROM_BOUNTIES + REWARD))
done

if [[ "$TOTAL_FROM_BOUNTIES" == "$ESCROW" ]]; then
  pass "the individual rewards sum to totalEscrowed"
else
  fail "rewards sum to $TOTAL_FROM_BOUNTIES but totalEscrowed is $ESCROW"
fi

# The Registry enforces this at open time, but reading it back is what turns
# "the code should prevent it" into "it did not happen here".
echo "[6] each checker actually watches its own bounty's target"
for (( i=0; i<${#TARGETS[@]}; i++ )); do
  WATCHED=$(call "${CHECKERS[$i]}" 'target()(address)' | awk '{print $1}')
  if [[ "$(printf '%s' "$WATCHED" | tr 'A-Z' 'a-z')" == "$(printf '%s' "${TARGETS[$i]}" | tr 'A-Z' 'a-z')" ]]; then
    pass "bounty $i: checker watches ${TARGETS[$i]}"
  else
    fail "bounty $i: checker watches $WATCHED but the bounty declares ${TARGETS[$i]}"
  fi
done

# A bounty whose invariant is already broken can never be claimed and its
# funding is gone. This is the griefing vector, so check whether it has been
# used rather than assuming it has not.
echo "[7] every bounty is still claimable"
CLAIMABLE=0
for (( i=0; i<${#CHECKERS[@]}; i++ )); do
  HOLDS=$(call "${CHECKERS[$i]}" 'checkInvariant()(bool)' | awk '{print $1}')
  if [[ "$HOLDS" == "true" ]]; then
    pass "bounty $i: invariant intact, still winnable"
    CLAIMABLE=$((CLAIMABLE + 1))
  else
    fail "bounty $i: invariant already broken — this bounty is dead and its funding is stuck"
  fi
done
echo "      claimable bounties: $CLAIMABLE / ${#CHECKERS[@]}"

echo
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS — deployment confirmed against mined chain state."
  exit 0
else
  echo "FAIL — $FAILURES check(s) failed."
  exit 1
fi
