/**
 * Proof of Break — agent, stage one: find work.
 *
 * Reads the bounty board from the Registry, throws out everything that cannot
 * be won, and picks the most valuable of what is left. Prints its reasoning at
 * every step, because a decision nobody can audit is not much of a decision.
 *
 * It does not attack anything. That is Task 7.
 *
 * Exit codes:
 *   0  picked a bounty
 *   3  scan completed, nothing worth attacking
 *   1  could not run (bad config, unreachable chain)
 */

import { formatUnits } from "viem";
import { agentAccount, elapsedSeconds, observedRate, publicClient, stats } from "./chain.js";
import { loadEnv, REGISTRY_ADDRESS, RPC_MIN_INTERVAL_MS, arcTestnet } from "./config.js";
import { checkerDescription, totalEscrowed, usdc } from "./registry.js";
import { explainRejection, scanBoard, type Assessment } from "./scan.js";
import { describePlan } from "./signature.js";

const line = (c = "─") => console.log(c.repeat(78));

function bountyLine(a: Assessment): string {
  const id = `#${a.bounty.id}`.padEnd(4);
  const reward = usdc(a.bounty.reward).padEnd(12);
  return `  ${id} ${reward} ${a.bounty.functionSignature.padEnd(20)} target ${a.bounty.target}`;
}

async function main(): Promise<number> {
  loadEnv();

  const account = agentAccount();

  console.log();
  console.log("PROOF OF BREAK — agent");
  line("═");
  console.log(`  chain      ${arcTestnet.name} (${arcTestnet.id})`);
  console.log(`  registry   ${REGISTRY_ADDRESS}`);
  console.log(`  agent      ${account.address}`);
  console.log(`  pacing     one RPC call per ${RPC_MIN_INTERVAL_MS}ms, under the`);
  console.log(`             measured eth_call ceiling of ~2.2/s on Arc`);
  console.log();
  console.log("  The registry address above is the only thing this agent is told.");
  console.log("  Targets, functions and rewards are all read from the chain.");
  console.log();

  const balance = await publicClient.getBalance({ address: account.address });
  console.log(`  agent balance  ${formatUnits(balance, 18)} USDC`);
  if (balance === 0n) {
    console.log("  ⚠  no gas. Task 7 will not be able to send anything.");
  }

  const escrow = await totalEscrowed();
  console.log(`  escrowed       ${usdc(escrow)} across the whole board`);
  console.log();

  line();
  console.log("READING THE BOARD");
  line();

  const result = await scanBoard((a) => {
    if (a.viable) {
      console.log(`✓ ${bountyLine(a).slice(2)}`);
    } else {
      console.log(`✗ ${bountyLine(a).slice(2)}`);
      console.log(
        `       rejected: ${explainRejection(a.rejection!)}${a.detail ? ` (${a.detail})` : ""}`,
      );
    }
  });

  const viable = result.assessments.filter((a) => a.viable);
  console.log();
  console.log(
    `  ${result.assessments.length} bounties on the board, ${viable.length} worth attacking`,
  );
  console.log();

  line();
  console.log("DECISION");
  line();

  if (!result.chosen) {
    console.log(`  No bounty selected.`);
    console.log(`  Reason: ${result.reason}.`);
    console.log();
    console.log("  Nothing to do, so nothing is done. Exiting.");
    reportRpc();
    return 3;
  }

  const c = result.chosen;
  console.log(`  Selected bounty #${c.bounty.id}`);
  console.log(`  Reward     ${usdc(c.bounty.reward)}`);
  console.log(`  Target     ${c.bounty.target}`);
  console.log(`  Checker    ${c.bounty.checker}`);
  console.log(`  Sponsor    ${c.bounty.sponsor}`);
  console.log();
  console.log(`  Why this one: ${result.reason}.`);
  console.log();

  const desc = await checkerDescription(c.bounty.checker);
  console.log("  The rule it has to break:");
  console.log(`    ${desc ?? "(checker did not describe itself)"}`);
  console.log();

  console.log("  What it will have to generate:");
  console.log(`    signature  ${c.signature.raw}`);
  console.log(`    ${describePlan(c.signature)}`);

  const selectorMatches =
    c.signature.selector.toLowerCase() === c.bounty.selector.toLowerCase();
  console.log(
    `    selector   ${c.bounty.selector} ` +
      (selectorMatches
        ? "(matches the one derived from the signature)"
        : `(MISMATCH — derived ${c.signature.selector})`),
  );
  if (!selectorMatches) {
    console.log("    ⚠  the Registry's selector disagrees with its own signature string.");
  }
  console.log();
  console.log(
    `  Explorer   ${arcTestnet.blockExplorers.default.url}/address/${c.bounty.target}`,
  );
  console.log();
  console.log("  Stopping here. Generating inputs and firing is Task 7.");

  reportRpc();
  return 0;
}

function reportRpc(): void {
  console.log();
  line();
  console.log("RPC COST OF THIS SCAN");
  line();
  const methods = Object.entries(stats.byMethod)
    .sort((a, b) => b[1] - a[1])
    .map(([m, n]) => `${m}=${n}`)
    .join("  ");
  console.log(`  calls        ${stats.calls}   (${methods})`);
  console.log(`  elapsed      ${elapsedSeconds().toFixed(1)}s`);
  console.log(`  rate         ${observedRate().toFixed(2)} calls/s`);
  console.log(`  throttled    ${stats.throttled}`);
  console.log(`  errors       ${stats.errors}  (a reverting checker counts here)`);
  console.log();
}

main()
  .then((code) => process.exit(code))
  .catch((e) => {
    console.error();
    console.error("agent could not run:");
    console.error(`  ${e instanceof Error ? e.message : String(e)}`);
    console.error();
    process.exit(1);
  });
