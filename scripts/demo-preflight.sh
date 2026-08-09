#!/usr/bin/env bash
# Go / no-go check before recording a take of the demo video.
#
# Run this immediately before pressing record. Every take of the demo block
# spends a real bounty that cannot be recovered, so the point of this script is
# to fail BEFORE the camera is rolling rather than halfway through a take.
#
# It only reads. It changes nothing.
#
# Run: ./scripts/demo-preflight.sh

set -uo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

REGISTRY="${REGISTRY:-0xbBd50574b55CE9F7453882E2d3361b393AD3F99C}"
RPC="${ARC_RPC_URL}"
WEB="${WEB_URL:-https://proof-of-break.vercel.app}"
PACE=0.6   # stay under the measured eth_call ceiling

BLOCKERS=0
WARNINGS=0

ok()    { echo "  ok    $*"; }
warn()  { echo "  warn  $*"; WARNINGS=$((WARNINGS + 1)); }
block() { echo "  STOP  $*"; BLOCKERS=$((BLOCKERS + 1)); }

call() { sleep "$PACE"; cast call "$@" --rpc-url "$RPC" 2>/dev/null; }
usdc() { python3 -c "print(f'{$1/10**18:g}')"; }

echo
echo "PROOF OF BREAK — pre-flight for a recording take"
echo "════════════════════════════════════════════════════════════════"

# ---------------------------------------------------------------- tests ----
echo
echo "[1] local test suite"
if forge test >/dev/null 2>&1; then
  ok "forge test green"
else
  block "forge test is FAILING — do not record a broken build"
fi

# ---------------------------------------------------------------- board ----
echo
echo "[2] the board on Arc"
COUNT=$(call "$REGISTRY" 'bountyCount()(uint256)' | awk '{print $1}')
if [[ -z "${COUNT:-}" ]]; then
  block "cannot read the Registry — check the RPC before anything else"
  echo; echo "STOP — the chain is unreachable."; exit 1
fi
ok "registry answers; $COUNT bounties have been opened"

CLAIMABLE=0
TOP_REWARD=0
TOP_ID=""
SECOND_REWARD=0
declare -a CLAIMABLE_REWARDS=()

for (( i=0; i<COUNT; i++ )); do
  B=$(call "$REGISTRY" \
      'getBounty(uint256)((address,address,address,bytes4,uint256,bool,string))' "$i")
  PAID=$(printf '%s' "$B" | grep -o 'true\|false' | head -1)
  CHECKER=$(printf '%s' "$B" | sed -E 's/^\(([^,]*), ([^,]*), ([^,]*),.*/\3/' | tr -d ' ')
  REWARD=$(printf '%s' "$B" | sed -E 's/.*, ([0-9]+) \[.*/\1/')
  [[ "$PAID" == "true" ]] && continue

  HOLDS=$(call "$CHECKER" 'checkInvariant()(bool)' | awk '{print $1}')
  if [[ "$HOLDS" == "true" ]]; then
    CLAIMABLE=$((CLAIMABLE + 1))
    CLAIMABLE_REWARDS+=("$REWARD")
    if (( REWARD > TOP_REWARD )); then
      SECOND_REWARD=$TOP_REWARD
      TOP_REWARD=$REWARD
      TOP_ID=$i
    elif (( REWARD > SECOND_REWARD )); then
      SECOND_REWARD=$REWARD
    fi
  fi
done

echo "      claimable right now: $CLAIMABLE"
if (( CLAIMABLE == 0 )); then
  block "no claimable bounty — the agent will exit 3 and there is nothing to film"
elif (( CLAIMABLE == 1 )); then
  warn "only ONE claimable bounty. A fluffed take leaves nothing for a retry."
else
  ok "$CLAIMABLE claimable — room to fluff a take and go again"
fi

# ------------------------------------------------- same number every take ----
echo
echo "[3] will every take show the same reward?"
if (( CLAIMABLE >= 2 )); then
  TOP_COUNT=0
  for r in "${CLAIMABLE_REWARDS[@]}"; do [[ "$r" == "$TOP_REWARD" ]] && TOP_COUNT=$((TOP_COUNT + 1)); done
  echo "      the agent always picks the richest: #$TOP_ID at $(usdc "$TOP_REWARD") USDC"
  echo "      bounties tied at that amount: $TOP_COUNT"
  if (( TOP_COUNT >= 2 )); then
    ok "$TOP_COUNT takes will all show $(usdc "$TOP_REWARD") USDC — footage stays cuttable"
  else
    warn "only one bounty at the top amount. The next take will show $(usdc "$SECOND_REWARD") USDC instead, so takes will not intercut. Restock at $(usdc "$TOP_REWARD") first."
  fi
fi

# ----------------------------------------------------------- agent gas ----
echo
echo "[4] the agent's wallet"
BAL=$(cast balance "$AGENT_ADDRESS" --rpc-url "$RPC" 2>/dev/null)
echo "      balance: $(usdc "${BAL:-0}") USDC"
if [[ -z "${BAL:-}" ]] || (( $(python3 -c "print(1 if ${BAL:-0} < 10**18 else 0)") )); then
  block "agent has under 1 USDC — it cannot pay gas. Top up at faucet.circle.com"
else
  ok "enough gas for many attempts"
fi

# --------------------------------------------------------------- the web ----
echo
echo "[5] the live board (shown on camera in block 4)"
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$WEB" 2>/dev/null)
if [[ "$CODE" == "200" ]]; then
  ok "$WEB responds 200"
  if curl -s --max-time 20 "$WEB" | grep -q "The RPC did not answer"; then
    warn "the page loaded but is showing its RPC error banner — refresh it before filming"
  else
    ok "page is rendering the board, no error banner"
  fi
else
  block "$WEB returned $CODE"
fi

# --------------------------------------------------------------- verdict ----
echo
echo "════════════════════════════════════════════════════════════════"
if (( BLOCKERS > 0 )); then
  echo "NO-GO — $BLOCKERS blocker(s), $WARNINGS warning(s). Fix before recording."
  exit 1
elif (( WARNINGS > 0 )); then
  echo "GO, WITH CARE — $WARNINGS warning(s) above. Read them before pressing record."
  exit 0
else
  echo "GO — everything checks out."
  echo
  echo "  Remember: each take of the demo block spends one bounty permanently."
  echo "  Rehearse on anvil (./scripts/compare-strategies.sh) — it is free."
  exit 0
fi
