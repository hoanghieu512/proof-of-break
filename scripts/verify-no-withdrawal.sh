#!/usr/bin/env bash
# Proves, against the compiled artefact rather than the source, that
# BountyRegistry has no way to move money out.
#
# The claim in design doc §8 is that not even the author can withdraw. That is
# only worth stating if it is checkable, so this checks it four ways:
#
#   1. exactly one state-changing function exists, and it is openBounty
#   2. openBounty is the only payable entry point
#   3. there is no receive() or fallback()
#   4. the runtime bytecode contains no SELFDESTRUCT, DELEGATECALL or CALLCODE,
#      and no plain CALL — value can only leave via one of those
#
# Run: ./scripts/verify-no-withdrawal.sh

set -uo pipefail
cd "$(dirname "$0")/.."

CONTRACT="src/BountyRegistry.sol:BountyRegistry"
FAILURES=0

fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ok  : $*"; }

echo "Verifying $CONTRACT has no withdrawal path"
echo

ABI=$(forge inspect "$CONTRACT" abi --json)

# --- 1. state-changing functions -----------------------------------------
echo "[1] state-changing functions"
MUTATORS=$(printf '%s' "$ABI" | jq -r '
  [.[] | select(.type=="function")
       | select(.stateMutability!="view" and .stateMutability!="pure")
       | .name] | sort | join(",")')
echo "      found: ${MUTATORS:-<none>}"
if [[ "$MUTATORS" == "openBounty" ]]; then
  pass "openBounty is the only function that can change state"
else
  fail "expected exactly 'openBounty', got '${MUTATORS:-<none>}'"
fi

# --- 2. payable entry points ---------------------------------------------
echo "[2] payable entry points"
PAYABLE=$(printf '%s' "$ABI" | jq -r '
  [.[] | select(.type=="function") | select(.stateMutability=="payable") | .name]
  | sort | join(",")')
echo "      found: ${PAYABLE:-<none>}"
if [[ "$PAYABLE" == "openBounty" ]]; then
  pass "only openBounty accepts value"
else
  fail "expected exactly 'openBounty', got '${PAYABLE:-<none>}'"
fi

# --- 3. receive / fallback -----------------------------------------------
echo "[3] receive() / fallback()"
SINKS=$(printf '%s' "$ABI" | jq -r '[.[] | select(.type=="receive" or .type=="fallback") | .type] | join(",")')
if [[ -z "$SINKS" ]]; then
  pass "no receive() and no fallback(); stray value cannot even be parked here"
else
  fail "found: $SINKS"
fi

# --- 4. value-moving opcodes ---------------------------------------------
echo "[4] value-moving opcodes in runtime bytecode"
# Disassemble the deployed (runtime) bytecode specifically — constructor code
# is irrelevant because it no longer exists once the contract is live.
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

  # STATICCALL is expected: the checker is consulted twice while opening a
  # bounty, and STATICCALL cannot transfer value. A plain CALL is the only
  # remaining instruction that could, and there should be none at all.
  NCALL=$(printf '%s\n' "$MNEMONICS" | grep -cx 'CALL' || true)
  NSTATIC=$(printf '%s\n' "$MNEMONICS" | grep -cx 'STATICCALL' || true)
  echo "      CALL=$NCALL  STATICCALL=$NSTATIC"
  if [[ "$NCALL" == "0" ]]; then
    pass "no CALL opcode — the contract has no instruction capable of sending value"
  else
    fail "$NCALL x CALL present — inspect each one"
  fi
fi

echo
if [[ $FAILURES -eq 0 ]]; then
  echo "PASS — no withdrawal path exists in the compiled contract."
  exit 0
else
  echo "FAIL — $FAILURES check(s) failed."
  exit 1
fi
