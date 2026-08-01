#!/usr/bin/env bash
# Verifies what can be verified about how money leaves BountyRegistry.
#
# Until v0.3.0 the claim was simple and fully static: the runtime bytecode
# contained no CALL, so the contract held no instruction capable of sending
# value. v0.4.0 ends that. `attempt` must call an arbitrary target and must pay
# a winning agent, so there are now exactly two CALL sites. The old claim is
# retired here rather than quietly left standing.
#
# THE CLAIM NOW BEING CHECKED
#
#   Value can enter only through openBounty, and can leave only through the
#   payout inside attempt, which fires only when a checker reported the
#   invariant intact before the agent's action and broken after it, in the same
#   transaction.
#
# WHAT IS STATICALLY CHECKABLE  (part A)
#   - only two functions can change state at all
#   - only openBounty can receive value
#   - no receive() or fallback(), so value cannot arrive unattached
#   - no SELFDESTRUCT, DELEGATECALL, CALLCODE, CREATE or CREATE2
#   - exactly two CALL sites exist, so a third cannot appear unnoticed
#
# WHAT IS NOT  (part B)
#   Static inspection cannot show that those two CALLs are the target call and
#   the payout, that the payout is bounded by the bounty's own reward, or that
#   it is gated on a true->false transition. Those are behavioural properties.
#   They are pinned by tests, so this script runs those tests and reports the
#   result instead of pretending the bytecode establishes it.
#
# Run: ./scripts/verify-escrow.sh

set -uo pipefail
cd "$(dirname "$0")/.."

CONTRACT="src/BountyRegistry.sol:BountyRegistry"
FAILURES=0

fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ok  : $*"; }

echo "=============================================================="
echo "PART A — static properties of the compiled contract"
echo "=============================================================="

ABI=$(forge inspect "$CONTRACT" abi --json)

echo "[A1] functions that can change state"
MUTATORS=$(printf '%s' "$ABI" | jq -r '
  [.[] | select(.type=="function")
       | select(.stateMutability!="view" and .stateMutability!="pure")
       | .name] | sort | join(",")')
echo "      found: ${MUTATORS:-<none>}"
if [[ "$MUTATORS" == "attempt,openBounty" ]]; then
  pass "exactly openBounty and attempt; everything else is read-only"
else
  fail "expected 'attempt,openBounty', got '${MUTATORS:-<none>}'"
fi

echo "[A2] functions that can receive value"
PAYABLE=$(printf '%s' "$ABI" | jq -r '
  [.[] | select(.type=="function") | select(.stateMutability=="payable") | .name]
  | sort | join(",")')
echo "      found: ${PAYABLE:-<none>}"
if [[ "$PAYABLE" == "openBounty" ]]; then
  pass "value can only enter through openBounty"
else
  fail "expected 'openBounty', got '${PAYABLE:-<none>}'"
fi

echo "[A3] receive() / fallback()"
SINKS=$(printf '%s' "$ABI" | jq -r '[.[] | select(.type=="receive" or .type=="fallback") | .type] | join(",")')
if [[ -z "$SINKS" ]]; then
  pass "neither exists; value cannot arrive unattached to a bounty"
else
  fail "found: $SINKS"
fi

echo "[A4] value-moving opcodes in runtime bytecode"
BYTECODE=$(forge inspect "$CONTRACT" deployedBytecode)
MNEMONICS=$(cast disassemble "$BYTECODE" 2>/dev/null | awk '{print $2}')

if [[ -z "$MNEMONICS" ]]; then
  fail "could not disassemble runtime bytecode"
else
  for OP in SELFDESTRUCT DELEGATECALL CALLCODE CREATE CREATE2; do
    N=$(printf '%s\n' "$MNEMONICS" | grep -cx "$OP" || true)
    if [[ "$N" == "0" ]]; then
      pass "no $OP"
    else
      fail "$N x $OP present"
    fi
  done

  NCALL=$(printf '%s\n' "$MNEMONICS" | grep -cx 'CALL' || true)
  NSTATIC=$(printf '%s\n' "$MNEMONICS" | grep -cx 'STATICCALL' || true)
  echo "      CALL=$NCALL  STATICCALL=$NSTATIC"
  # Two, and only two: the agent's action against the target, and the payout.
  # A third appearing is a change to how value can move and must be reviewed.
  if [[ "$NCALL" == "2" ]]; then
    pass "exactly 2 CALL sites (target action + payout), as designed"
  else
    fail "expected exactly 2 CALL sites, found $NCALL — review every one"
  fi
  if [[ "$NSTATIC" -ge 3 ]]; then
    pass "$NSTATIC STATICCALL sites; checker calls cannot modify state by construction"
  else
    fail "expected at least 3 STATICCALL sites, found $NSTATIC"
  fi
fi

echo
echo "=============================================================="
echo "PART B — behavioural properties, checked by test"
echo "=============================================================="
echo "Static inspection cannot establish these. Running the tests that can."
echo

BEHAVIOURAL_TESTS=(
  "test_BreakingTheInvariantPaysTheCallerAndClosesTheBounty"
  "test_OnlyTheAttackedBountyIsAffected"
  "test_HarmlessActionPaysNobody"
  "test_AnInvariantBrokenBeforehandPaysNobody"
  "test_APaidBountyCannotBePaidAgain"
  "test_CallingAFunctionTheBountyDidNotDeclareIsRefused"
  "test_TargetReenteringAttemptIsBlockedAndStealsNothing"
  "test_TargetReenteringOpenBountyIsBlocked"
  "test_ACheckerSabotagedMidAttemptDoesNotProduceAPayout"
  "test_ACheckerThatBurnsAllGasDoesNotProduceAPayout"
  "test_AClaimantThatRefusesPaymentRevertsTheWholeAttempt"
)

echo "[B1] money-flow behaviour"
for T in "${BEHAVIOURAL_TESTS[@]}"; do
  if forge test --match-test "^${T}$" >/dev/null 2>&1; then
    pass "$T"
  else
    fail "$T"
  fi
done

echo "[B2] escrow invariants under random action sequences"
if forge test --match-contract BountyRegistryInvariantTest >/dev/null 2>&1; then
  pass "balance always covers unpaid bounties; nothing created or destroyed"
else
  fail "invariant suite did not pass"
fi

echo
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS — value enters only via openBounty and leaves only via the payout"
  echo "       in attempt, gated on a same-transaction true->false transition."
  exit 0
else
  echo "FAIL — $FAILURES check(s) failed."
  exit 1
fi
