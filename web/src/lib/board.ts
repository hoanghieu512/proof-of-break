import "server-only";

/**
 * The bounty board, read from chain and cached.
 *
 * Cached with a tag so that N simultaneous viewers cost ONE set of RPC reads,
 * not N. The refresh button invalidates the tag; nothing else does, and there
 * is no interval anywhere in this app.
 */

import { unstable_cache } from "next/cache";
import { formatUnits } from "viem";
import {
  checkerAbi,
  publicClient,
  REGISTRY_ADDRESS,
  registryAbi,
} from "./chain";

export const BOARD_TAG = "board";

/** Bounded staleness. Not a poll — nothing fetches unless someone loads a page. */
const CACHE_TTL_SECONDS = 60;

export interface BoardBounty {
  id: number;
  reward: string;          // formatted, 18 decimals
  rewardWei: string;
  target: `0x${string}`;
  checker: `0x${string}`;
  functionSignature: string;
  selector: `0x${string}`;
  paid: boolean;
  /** Only meaningful when not paid: has someone broken the target directly? */
  invariantHolds: boolean | null;
}

export interface Board {
  ok: true;
  bounties: BoardBounty[];
  totalEscrowedWei: string;
  totalEscrowed: string;
  openCount: number;
  claimableCount: number;
  readAt: string;
}

export interface BoardError {
  ok: false;
  message: string;
  readAt: string;
}

async function readBoard(): Promise<Board | BoardError> {
  try {
    const count = Number(
      await publicClient.readContract({
        address: REGISTRY_ADDRESS,
        abi: registryAbi,
        functionName: "bountyCount",
      }),
    );

    const totalEscrowedWei = await publicClient.readContract({
      address: REGISTRY_ADDRESS,
      abi: registryAbi,
      functionName: "totalEscrowed",
    });

    const bounties: BoardBounty[] = [];
    for (let i = 0; i < count; i++) {
      const b = await publicClient.readContract({
        address: REGISTRY_ADDRESS,
        abi: registryAbi,
        functionName: "getBounty",
        args: [BigInt(i)],
      });

      // Only ask the checker about bounties still open. A paid one is settled;
      // its invariant is broken by definition and asking wastes a call.
      let invariantHolds: boolean | null = null;
      if (!b.paid) {
        try {
          invariantHolds = await publicClient.readContract({
            address: b.checker,
            abi: checkerAbi,
            functionName: "checkInvariant",
          });
        } catch {
          invariantHolds = null; // checker unreachable; shown as unknown
        }
      }

      bounties.push({
        id: i,
        reward: formatUnits(b.reward, 18),
        rewardWei: b.reward.toString(),
        target: b.target,
        checker: b.checker,
        functionSignature: b.functionSignature,
        selector: b.selector,
        paid: b.paid,
        invariantHolds,
      });
    }

    return {
      ok: true,
      bounties,
      totalEscrowedWei: totalEscrowedWei.toString(),
      totalEscrowed: formatUnits(totalEscrowedWei, 18),
      openCount: bounties.filter((b) => !b.paid).length,
      claimableCount: bounties.filter((b) => !b.paid && b.invariantHolds === true).length,
      readAt: new Date().toISOString(),
    };
  } catch (e) {
    // The page must still render. A blank screen tells a visitor nothing; an
    // explicit "the RPC did not answer" tells them the site works and the
    // endpoint does not.
    return {
      ok: false,
      message: e instanceof Error ? e.message.split("\n")[0] : String(e),
      readAt: new Date().toISOString(),
    };
  }
}

export const getBoard = unstable_cache(readBoard, ["pob-board"], {
  tags: [BOARD_TAG],
  revalidate: CACHE_TTL_SECONDS,
});
