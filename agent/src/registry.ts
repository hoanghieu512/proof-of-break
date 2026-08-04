/**
 * Reading the bounty board.
 *
 * Note what is NOT in this file: any target address, any function name, any
 * assumption about how many bounties exist. All of that arrives from the chain.
 * The only constant is the Registry address in config.ts.
 */

import { formatUnits, parseAbi } from "viem";
import { publicClient } from "./chain.js";
import { REGISTRY_ADDRESS } from "./config.js";

export const registryAbi = parseAbi([
  "function bountyCount() view returns (uint256)",
  "function totalEscrowed() view returns (uint256)",
  "function ONE_USDC() view returns (uint256)",
  "function getBounty(uint256) view returns ((address sponsor, address target, address checker, bytes4 selector, uint256 reward, bool paid, string functionSignature))",
]);

export const checkerAbi = parseAbi([
  "function checkInvariant() view returns (bool)",
  "function target() view returns (address)",
  "function description() view returns (string)",
]);

export interface Bounty {
  id: number;
  sponsor: `0x${string}`;
  target: `0x${string}`;
  checker: `0x${string}`;
  selector: `0x${string}`;
  reward: bigint;
  paid: boolean;
  functionSignature: string;
}

/** Arc's native USDC has 18 decimals. The ERC-20 view of it has 6. Do not mix. */
export const USDC_DECIMALS = 18;

export function usdc(amount: bigint): string {
  return `${formatUnits(amount, USDC_DECIMALS)} USDC`;
}

export async function bountyCount(): Promise<number> {
  const n = await publicClient.readContract({
    address: REGISTRY_ADDRESS,
    abi: registryAbi,
    functionName: "bountyCount",
  });
  return Number(n);
}

export async function totalEscrowed(): Promise<bigint> {
  return publicClient.readContract({
    address: REGISTRY_ADDRESS,
    abi: registryAbi,
    functionName: "totalEscrowed",
  });
}

export async function getBounty(id: number): Promise<Bounty> {
  const b = await publicClient.readContract({
    address: REGISTRY_ADDRESS,
    abi: registryAbi,
    functionName: "getBounty",
    args: [BigInt(id)],
  });
  return { id, ...b };
}

/** Reads every bounty, paid ones included, so they can be reported as excluded. */
export async function readBoard(): Promise<Bounty[]> {
  const n = await bountyCount();
  const out: Bounty[] = [];
  for (let i = 0; i < n; i++) out.push(await getBounty(i));
  return out;
}

export type CheckerVerdict =
  | { kind: "holds" }
  | { kind: "broken" }
  | { kind: "unusable"; reason: string };

/**
 * Ask a checker whether its invariant still holds.
 *
 * The three outcomes are deliberately distinct. "Broken" and "unusable" both
 * mean the bounty is not worth attacking, but for opposite reasons: one says
 * somebody already broke the target, the other says the referee cannot be
 * reached. Collapsing them into one failure would hide which it was.
 */
export async function askChecker(checker: `0x${string}`): Promise<CheckerVerdict> {
  try {
    const holds = await publicClient.readContract({
      address: checker,
      abi: checkerAbi,
      functionName: "checkInvariant",
    });
    return holds ? { kind: "holds" } : { kind: "broken" };
  } catch (e) {
    return { kind: "unusable", reason: shortError(e) };
  }
}

/**
 * Confirm the checker actually watches the target the bounty declared.
 *
 * The Registry enforces this when a bounty is opened, so it should always pass.
 * The agent checks anyway: it is about to spend gas on the strength of that
 * claim, and verifying costs one call.
 */
export async function checkerWatches(
  checker: `0x${string}`,
): Promise<`0x${string}` | null> {
  try {
    return await publicClient.readContract({
      address: checker,
      abi: checkerAbi,
      functionName: "target",
    });
  } catch {
    return null;
  }
}

export async function checkerDescription(
  checker: `0x${string}`,
): Promise<string | null> {
  try {
    return await publicClient.readContract({
      address: checker,
      abi: checkerAbi,
      functionName: "description",
    });
  } catch {
    return null;
  }
}

export function shortError(e: unknown): string {
  const msg = e instanceof Error ? e.message : String(e);
  return msg.split("\n")[0].slice(0, 120);
}
