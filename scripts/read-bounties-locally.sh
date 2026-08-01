#!/usr/bin/env bash
# Demonstrates that the bounty board is readable from outside the chain, over
# ordinary JSON-RPC, by a caller holding no privileges and no prior knowledge.
#
# This is the entry point an autonomous agent uses in Task 6: it learns the
# target, the checker and the function signature from the Registry alone.
#
# Runs against a local anvil node, so it proves the read path without spending
# anything on Arc. Task 5 repeats it against Arc Testnet.
#
# Run: ./scripts/read-bounties-locally.sh

set -uo pipefail
cd "$(dirname "$0")/.."

RPC="http://127.0.0.1:8545"
# Anvil's first prefunded account. This key is printed by anvil on every start
# and is published in its documentation — it is a test fixture, not a secret,
# and it controls nothing outside this throwaway local chain.
KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

ANVIL_PID=""
cleanup() { [[ -n "$ANVIL_PID" ]] && kill "$ANVIL_PID" 2>/dev/null; }
trap cleanup EXIT

echo "starting a local chain..."
anvil --silent --port 8545 &
ANVIL_PID=$!

for _ in $(seq 1 30); do
  cast chain-id --rpc-url "$RPC" >/dev/null 2>&1 && break
  sleep 0.5
done
cast chain-id --rpc-url "$RPC" >/dev/null 2>&1 || { echo "anvil did not come up"; exit 1; }
echo "  chain id $(cast chain-id --rpc-url "$RPC")"

deploy() {
  forge create "$1" --rpc-url "$RPC" --private-key "$KEY" --broadcast "${@:2}" \
    2>/dev/null | awk '/Deployed to:/ {print $3}'
}

echo "deploying..."
VAULT=$(deploy src/DemoVault.sol:DemoVault)
CHECKER=$(deploy src/VaultChecker.sol:VaultChecker --constructor-args "$VAULT")
REGISTRY=$(deploy src/BountyRegistry.sol:BountyRegistry)
echo "  DemoVault      $VAULT"
echo "  VaultChecker   $CHECKER"
echo "  BountyRegistry $REGISTRY"

ONE_USDC=$(cast call "$REGISTRY" 'ONE_USDC()(uint256)' --rpc-url "$RPC" | awk '{print $1}')
REWARD=$(python3 -c "print(5 * $ONE_USDC)")
echo
echo "opening a 5 USDC bounty (ONE_USDC = $ONE_USDC, so reward = $REWARD)"
cast send "$REGISTRY" 'openBounty(address,address,string)(uint256)' \
  "$VAULT" "$CHECKER" "deposit(uint256)" \
  --value "$REWARD" --rpc-url "$RPC" --private-key "$KEY" --json \
  | jq -r '"  tx \(.transactionHash)  status \(.status)"'

echo
echo "=== reading the board as an outsider (eth_call only, no key) ==="
echo "bountyCount    : $(cast call "$REGISTRY" 'bountyCount()(uint256)' --rpc-url "$RPC")"
echo "openBountyIds  : $(cast call "$REGISTRY" 'openBountyIds()(uint256[])' --rpc-url "$RPC")"
echo
echo "getBounty(0):"
cast call "$REGISTRY" \
  'getBounty(uint256)((address,address,address,bytes4,uint256,bool,string))' 0 \
  --rpc-url "$RPC"
echo
echo "escrowStatus (held, owed):"
cast call "$REGISTRY" 'escrowStatus()(uint256,uint256)' --rpc-url "$RPC"
echo
echo "registry balance on chain: $(cast balance "$REGISTRY" --rpc-url "$RPC")"
echo
echo "Everything an agent needs — target, checker, function signature — came"
echo "from the Registry alone."
