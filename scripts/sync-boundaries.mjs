#!/usr/bin/env node
/**
 * Generate web/src/data/boundaries.json from agent/src/boundaries.ts.
 *
 * WHY THIS EXISTS RATHER THAN A COPY-PASTE
 *
 * The boundary list is the thing a judge is most likely to read closely, so
 * there must be exactly one source of truth for it — agent/src/boundaries.ts,
 * where the agent actually reads it. But Vercel deploys with web/ as the root
 * directory, so the web app cannot import a file from agent/.
 *
 * So the list is generated into web/ and committed. Committing a build artefact
 * is a real cost, and the mitigation is `--check`: the web build runs this in
 * check mode first and fails if the two have drifted. A stale copy cannot ship
 * silently, which is the only failure mode that would actually matter.
 *
 *   node scripts/sync-boundaries.mjs          write the JSON
 *   node scripts/sync-boundaries.mjs --check  fail if it is out of date
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = join(root, "agent/src/boundaries.ts");
const OUT = join(root, "web/src/data/boundaries.json");

const rawSource = readFileSync(SRC, "utf8");

/**
 * Strip `//` comments that are not inside a string literal.
 *
 * Needed because the entries carry explanatory comments both before `value:`
 * and trailing it (`value: 1_000_000n, // 1e6`), and a naive match walks
 * straight past them. The first version of this script silently parsed 4 of the
 * 13 entries — which would have shipped a web page showing a third of the list.
 */
function stripComments(text) {
  return text
    .split("\n")
    .map((lineText) => {
      let inString = false;
      let quote = "";
      for (let i = 0; i < lineText.length; i++) {
        const ch = lineText[i];
        if (inString) {
          if (ch === "\\") i++;
          else if (ch === quote) inString = false;
        } else if (ch === '"' || ch === "'" || ch === "`") {
          inString = true;
          quote = ch;
        } else if (ch === "/" && lineText[i + 1] === "/") {
          return lineText.slice(0, i);
        }
      }
      return lineText;
    })
    .join("\n");
}

const stripped = stripComments(rawSource);

// Parse only inside the exported array literal. Without this the interface
// declaration's own `value: bigint;` field is counted as an entry, which is
// what the count guard caught on the second run.
const arrayStart = stripped.indexOf("UINT256_BOUNDARIES");
const openBracket = stripped.indexOf("[", arrayStart);
const closeBracket = stripped.indexOf("\n];", openBracket);
if (arrayStart === -1 || openBracket === -1 || closeBracket === -1) {
  console.error("sync-boundaries: could not locate the UINT256_BOUNDARIES array literal");
  process.exit(1);
}
const source = stripped.slice(openBracket, closeBracket);

// Pull each { value, label, why } entry out of the exported array. Parsing the
// literal rather than importing it keeps this a plain node script with no build
// step, and the shape is stable enough for a regex once comments are gone.
const entries = [];
const re = /\{\s*value:\s*([^,]+?),\s*label:\s*"((?:[^"\\]|\\.)*)",\s*why:\s*"((?:[^"\\]|\\.)*)",?\s*\}/gs;
let m;
while ((m = re.exec(source)) !== null) {
  const rawValue = m[1].trim();
  entries.push({
    // Keep the literal exactly as written in the source (e.g. "1_000_000n",
    // "(1n << 128n)") so the page can show the same expression a reader sees in
    // the TypeScript, and a decimal form for display.
    expression: rawValue,
    value: evaluateBigIntLiteral(rawValue).toString(),
    label: unescape(m[2]),
    why: unescape(m[3]),
  });
}

function unescape(s) {
  return s.replace(/\\"/g, '"').replace(/\\\\/g, "\\");
}

function evaluateBigIntLiteral(expr) {
  // Only bigint arithmetic appears in this list; evaluating it is safe because
  // the input is our own source file, and it keeps 2n ** 256n - 1n readable in
  // the TypeScript instead of being spelled out.
  // eslint-disable-next-line no-new-func
  return Function(`"use strict"; return (${expr});`)();
}

// Cross-check the parse against the number of `value:` keys actually present.
// A regex that silently matches a subset is the failure mode this script had on
// its first run, and a count mismatch is the cheapest way to catch it.
const declared = (source.match(/^\s*value:/gm) ?? []).length;
if (entries.length === 0 || entries.length !== declared) {
  console.error(
    `sync-boundaries: parsed ${entries.length} entries but the source declares ` +
      `${declared}. The source shape changed; fix the parser rather than shipping ` +
      `a partial list.`,
  );
  process.exit(1);
}

const payload = JSON.stringify({ generatedFrom: "agent/src/boundaries.ts", entries }, null, 2) + "\n";

if (process.argv.includes("--check")) {
  if (!existsSync(OUT)) {
    console.error("sync-boundaries: web/src/data/boundaries.json is missing. Run without --check.");
    process.exit(1);
  }
  const current = readFileSync(OUT, "utf8");
  if (current !== payload) {
    console.error(
      "sync-boundaries: boundaries.json is out of date with agent/src/boundaries.ts.\n" +
        "Run: node scripts/sync-boundaries.mjs",
    );
    process.exit(1);
  }
  console.log(`sync-boundaries: up to date (${entries.length} values)`);
} else {
  writeFileSync(OUT, payload);
  console.log(`sync-boundaries: wrote ${entries.length} values to web/src/data/boundaries.json`);
}
