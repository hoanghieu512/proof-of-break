#!/usr/bin/env node
/**
 * Run the boundary-list drift check when the source is reachable.
 *
 * The generator and its source live at the repo root (scripts/ and agent/), but
 * Vercel deploys with web/ as the root directory and may not include files
 * outside it. So the check is conditional rather than mandatory:
 *
 *   - locally, and on any build that has the whole repo, it runs and a drifted
 *     boundaries.json fails the build
 *   - on a build that only has web/, it says so plainly and continues, because
 *     failing a deploy over a file that is not there would be a worse outcome
 *     than shipping a JSON that was verified when it was committed
 *
 * The committed JSON is only ever written by the generator, so the window for
 * drift is between editing agent/src/boundaries.ts and committing — which the
 * local build closes.
 */

import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const webDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const generator = join(webDir, "..", "scripts", "sync-boundaries.mjs");
const source = join(webDir, "..", "agent", "src", "boundaries.ts");

if (!existsSync(generator) || !existsSync(source)) {
  console.log(
    "check-boundaries: agent/src/boundaries.ts is not in this build context; " +
      "skipping the drift check and using the committed boundaries.json.",
  );
  process.exit(0);
}

const result = spawnSync(process.execPath, [generator, "--check"], {
  stdio: "inherit",
});
process.exit(result.status ?? 1);
