/**
 * Proof of Break — agent, end to end.
 *
 * One command: scan the board, choose a bounty, generate inputs boundary-first,
 * fire them through the Registry, and collect the USDC when one breaks. No human
 * in the loop.
 *
 * This is the screen the demo video records, so the log is written to be read at
 * playback speed: what value is being tried, why that value, what happened, and
 * an unmistakable moment when a bounty falls.
 *
 * Stops on the first break. It does not roll on to the next bounty — run the
 * command again and Task 6's scan will skip the one just claimed.
 *
 * Exit codes:
 *   0  broke a bounty and got paid
 *   3  scanned, nothing worth attacking
 *   4  attacked, exhausted the attempt cap without breaking anything
 *   1  could not run
 */

import { formatUnits } from "viem";
import { agentAccount, elapsedSeconds, publicClient, stats } from "./chain.js";
import {
  arcTestnet,
  ATTACK_MAX_ATTEMPTS,
  loadEnv,
  REGISTRY_ADDRESS,
  STRATEGY,
} from "./config.js";
import { checkerDescription, getBounty, usdc } from "./registry.js";
import { explainRejection, scanBoard } from "./scan.js";
import { attackLoop } from "./loop.js";
import { describePlan } from "./signature.js";

const line = (c = "─") => console.log(c.repeat(78));
const big = (msg: string) => {
  line("━");
  console.log(`  ${msg}`);
  line("━");
};

async function main(): Promise<number> {
  loadEnv();
  const account = agentAccount();

  console.log();
  console.log("PROOF OF BREAK — agent (scan → choose → fuzz → claim)");
  line("═");
  console.log(`  chain      ${arcTestnet.name} (${arcTestnet.id})`);
  console.log(`  registry   ${REGISTRY_ADDRESS}`);
  console.log(`  agent      ${account.address}`);
  console.log(`  strategy   ${STRATEGY}`);
  console.log();
  console.log("  The registry address is the only thing this agent is told.");
  console.log("  Everything else — target, function, reward — is read from chain.");
  console.log();

  const balanceBefore = await publicClient.getBalance({ address: account.address });
  console.log(`  agent balance before   ${formatUnits(balanceBefore, 18)} USDC`);
  if (balanceBefore === 0n) {
    console.log("  ✗ no gas — cannot send anything. Fund the agent wallet.");
    return 1;
  }
  console.log();

  // ---- scan (Task 6) ----------------------------------------------------
  line();
  console.log("SCANNING THE BOARD");
  line();
  const scan = await scanBoard((a) => {
    if (a.viable) {
      console.log(`  ✓ #${a.bounty.id}  ${usdc(a.bounty.reward).padEnd(11)} ${a.bounty.functionSignature}`);
    } else {
      console.log(`  ✗ #${a.bounty.id}  ${usdc(a.bounty.reward).padEnd(11)} rejected: ${explainRejection(a.rejection!)}`);
    }
  });

  if (!scan.chosen) {
    console.log();
    console.log(`  No bounty worth attacking. ${scan.reason}.`);
    return 3;
  }

  const chosen = scan.chosen;
  console.log();
  console.log(`  → chose #${chosen.bounty.id} at ${usdc(chosen.bounty.reward)}: ${scan.reason}.`);
  console.log();

  const desc = await checkerDescription(chosen.bounty.checker);
  console.log(`  target   ${chosen.bounty.target}`);
  console.log(`  rule     ${desc ?? "(none)"}`);
  console.log(`  input    ${describePlan(chosen.signature)}`);
  console.log();

  // ---- attack -----------------------------------------------------------
  line();
  console.log(`FUZZING — ${STRATEGY}`);
  line();
  console.log("  Every attempt goes through the Registry: it checks the rule,");
  console.log("  performs the deposit, checks again, and pays on a true→false flip.");
  console.log();

  const result = await attackLoop(chosen.bounty, chosen.signature, {
    strategy: STRATEGY,
    maxAttempts: ATTACK_MAX_ATTEMPTS,
    account: account.address,
    onProbe: (probe, c) => {
      const src = c.source === "boundary" ? "boundary" : "random  ";
      const val = c.values[0];
      const pretty = val >= 1_000_000_000_000_000n ? `${formatUnits(val, 18)}e18-scale` : val.toString();
      process.stdout.write(`  probe ${String(probe).padStart(2)}  [${src}]  deposit(${shorten(val.toString())})`);
      if (c.boundaryReason) {
        process.stdout.write(`\n              why: ${c.boundaryReason}\n`);
      } else {
        process.stdout.write("\n");
      }
    },
    onResult: (r) => {
      if (r.outcome.kind === "would-revert") {
        console.log(`              → target rejects this input (would revert); no gas spent`);
      } else if (r.outcome.kind === "miss") {
        console.log(`              → mined, invariant held. rule still true. tx ${short(r.outcome.hash)}`);
      } else if (r.outcome.kind === "not-mined") {
        console.log(`              → not mined after re-broadcast; moving on`);
      } else if (r.outcome.kind === "broke") {
        console.log(`              → BROKE THE INVARIANT. tx ${short(r.outcome.hash)}`);
      }
    },
  });

  console.log();
  if (!result.broke) {
    console.log(`  Attempt cap of ${ATTACK_MAX_ATTEMPTS} reached without a break.`);
    console.log(`  (${result.boundaryAttempts} boundary, ${result.randomAttempts} random)`);
    return 4;
  }

  const balanceAfter = await publicClient.getBalance({ address: account.address });
  const claimed = await getBounty(chosen.bounty.id);

  console.log();
  big("BOUNTY CLAIMED — USDC IS IN THE AGENT WALLET");
  console.log();
  console.log(`  broke on probe   ${result.winningProbe}  (${result.winningValue} — one whole unit at 18 decimals)`);
  console.log(`  reward           ${usdc(chosen.bounty.reward)}`);
  console.log(`  tx               ${result.winningHash}`);
  console.log(`  explorer         ${arcTestnet.blockExplorers.default.url}/tx/${result.winningHash}`);
  console.log();
  console.log(`  agent balance before   ${formatUnits(balanceBefore, 18)} USDC`);
  console.log(`  agent balance after    ${formatUnits(balanceAfter, 18)} USDC`);
  console.log(`  net change             +${formatUnits(balanceAfter - balanceBefore, 18)} USDC (reward minus gas)`);
  console.log();
  console.log(`  bounty #${chosen.bounty.id} is now marked paid: ${claimed.paid}`);
  console.log(`  No human touched this. Run again and the scan will skip this bounty.`);
  console.log();
  reportRpc();
  return 0;
}

function short(h: string): string {
  return `${h.slice(0, 10)}…${h.slice(-6)}`;
}
function shorten(s: string): string {
  return s.length > 24 ? `${s.slice(0, 12)}…${s.slice(-6)}` : s;
}

function reportRpc(): void {
  line();
  console.log("RPC COST");
  line();
  console.log(
    `  calls ${stats.calls}   elapsed ${elapsedSeconds().toFixed(1)}s   ` +
      `throttled ${stats.throttled}   real errors ${stats.errors}`,
  );
  const benignMethods = new Set([
    "eth_estimateGas",
    "eth_fillTransaction",
    "eth_getTransactionReceipt",
  ]);
  const benign = Object.entries(stats.errorsByMethod)
    .filter(([m]) => benignMethods.has(m))
    .reduce((n, [, v]) => n + v, 0);
  if (benign > 0) {
    console.log(
      `  (${benign} expected: the would-revert filter, fee-probe fallbacks and ` +
        `receipt polls — not failures)`,
    );
  }
  if (process.env.DEBUG_RPC) {
    console.log(`  errorsByMethod: ${JSON.stringify(stats.errorsByMethod)}`);
  }
  console.log();
}

main()
  .then((code) => process.exit(code))
  .catch((e) => {
    console.error();
    console.error("agent could not run:");
    console.error(`  ${e instanceof Error ? e.message : String(e)}`);
    process.exit(1);
  });
