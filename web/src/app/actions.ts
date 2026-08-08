"use server";

import { updateTag } from "next/cache";
import { BOARD_TAG } from "@/lib/board";

/**
 * The only thing on this site that causes an RPC read beyond the first page
 * load. It runs when somebody clicks refresh, and at no other time — there is
 * no interval, no polling, no revalidation on focus.
 *
 * `updateTag`, not `revalidateTag`. In Next 16 the latter expires the entry but
 * gives the *current* request the stale value, so the person who clicked
 * refresh would still be looking at old data — precisely the thing a refresh
 * button exists to prevent. `updateTag` gives read-your-own-writes.
 */
export async function refreshBoard(): Promise<void> {
  updateTag(BOARD_TAG);
}
