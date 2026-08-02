#!/usr/bin/env bash
# Runs the test suite once and prints a screenshot-friendly summary.
#
# `forge test` prints the grand total but buries it under hundreds of lines.
# `forge test --summary` prints a clean per-suite table but no grand total.
# This runs the suite once and prints both, plus the one line that preempts the
# obvious question about the skipped test.
#
# Run: ./scripts/test-summary.sh

set -uo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

echo "running the suite (this takes about a minute — invariant tests dominate)..."
forge test --summary >"$OUT" 2>&1
STATUS=$?

clear 2>/dev/null || true

FORGE_VERSION=$(forge --version | head -1 | sed -E 's/forge Version: ([^ ]+).*/\1/')

echo
echo "  Proof of Break — test suite"
echo "  ────────────────────────────────────────────────────────────"
echo

python3 - "$OUT" <<'PY'
import re, sys

lines = open(sys.argv[1], errors="replace").read().splitlines()

# The per-suite table is the one whose header names the Test Suite column.
start = next((i for i, l in enumerate(lines) if "Test Suite" in l and "Passed" in l), None)
if start is None:
    print("  could not find the summary table; run `forge test` directly")
    sys.exit(1)

start -= 1  # include the top border
end = next(i for i in range(start, len(lines)) if lines[i].startswith("╰"))

passed = failed = skipped = 0
for line in lines[start:end + 1]:
    print("  " + line)
    cells = [c.strip() for c in line.split("|")]
    if len(cells) >= 5 and cells[2].isdigit():
        passed += int(cells[2])
        failed += int(cells[3])
        skipped += int(cells[4])

print()
verdict = "ALL GREEN" if failed == 0 else f"{failed} FAILING"
print(f"  {verdict}   {passed} passed   {failed} failed   {skipped} skipped")
PY

echo
echo "  The one skipped test is FuzzerReach — an opt-in experiment that is"
echo "  meant to fail. It measures whether Foundry's own fuzzer can reach the"
echo "  planted bug (it can, in 21–305 runs). A test designed to fail has no"
echo "  business making the suite red on every run."
echo
echo "  forge $FORGE_VERSION · solc 0.8.28 · Arc Testnet (chain 5042002)"
echo

exit $STATUS
