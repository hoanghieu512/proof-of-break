/**
 * The control half of the strategy comparison.
 *
 * Draws N random uint256 values from the SAME generator the agent uses, and
 * counts how many equal a target value passed in. Reused rather than
 * reimplemented so this measures the agent's actual randomness, not a stand-in.
 *
 * The target value is DISCOVERED by the boundary-first run in
 * compare-strategies.sh — it breaks a real vault on anvil and reports the value
 * that did it. So this harness is never told where the bug is; it is told which
 * value the boundary strategy already proved breaks the target, and asked how
 * often blind random draws would have produced it.
 *
 * That is the apples-to-apples comparison: same generator, same unknown target,
 * only the strategy differs. Firing 10,000 real transactions to show the same
 * thing would take many minutes and change nothing about the result, which is a
 * property of the draw, not of the chain.
 *
 * Usage: TARGET_VALUE=<decimal> DRAWS=10000 tsx src/compare-random.ts
 */

import { randomUint256 } from "./generator.js";

const target = BigInt(process.env.TARGET_VALUE ?? "1000000000000000000");
const draws = Number(process.env.DRAWS ?? "10000");

let hits = 0;
let firstHit = -1;
for (let i = 0; i < draws; i++) {
  if (randomUint256() === target) {
    hits++;
    if (firstHit === -1) firstHit = i + 1;
  }
}

console.log(`  random-only: ${draws.toLocaleString()} draws, ${hits} hit the target value`);
if (hits === 0) {
  console.log(`  the target sits at 1 point in a 2^256 space; the expected number of`);
  console.log(`  draws to reach it is astronomically larger than ${draws.toLocaleString()}`);
} else {
  console.log(`  first hit at draw ${firstHit} (vanishingly unlikely; check the target value)`);
}

// Exit non-zero if random unexpectedly hit — that would mean the comparison is
// not measuring what it claims.
process.exit(hits === 0 ? 0 : 1);
