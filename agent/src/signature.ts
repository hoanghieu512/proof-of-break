/**
 * Working out what to generate, from nothing but a string.
 *
 * A bounty declares the one function an agent may fire, written the way Solidity
 * writes it: "deposit(uint256)". That string is the entire briefing. From it the
 * agent has to derive the argument types, decide whether it can produce values
 * of those types at all, and build the call.
 *
 * This is the piece that lets the agent attack a contract nobody told it about.
 */

import { keccak256, toHex } from "viem";

export interface ParsedSignature {
  raw: string;
  name: string;
  argTypes: string[];
  /** Selector derived locally from the string, for cross-checking the chain. */
  selector: `0x${string}`;
  /** Types this agent knows how to produce values for. */
  supported: boolean;
  unsupported: string[];
}

/** Types the generator in Task 7 will be able to produce. */
function isSupportedType(t: string): boolean {
  if (/^uint(8|16|24|32|40|48|56|64|72|80|88|96|104|112|120|128|136|144|152|160|168|176|184|192|200|208|216|224|232|240|248|256)?$/.test(t)) return true;
  if (/^int(8|16|24|32|40|48|56|64|72|80|88|96|104|112|120|128|136|144|152|160|168|176|184|192|200|208|216|224|232|240|248|256)?$/.test(t)) return true;
  if (t === "address" || t === "bool" || t === "bytes" || t === "string") return true;
  if (/^bytes([1-9]|[12][0-9]|3[0-2])$/.test(t)) return true;
  return false;
}

export function parseSignature(raw: string): ParsedSignature {
  const trimmed = raw.trim();
  const open = trimmed.indexOf("(");
  const close = trimmed.lastIndexOf(")");

  if (open <= 0 || close !== trimmed.length - 1) {
    return {
      raw: trimmed,
      name: trimmed,
      argTypes: [],
      selector: "0x00000000",
      supported: false,
      unsupported: ["signature is not parseable"],
    };
  }

  const name = trimmed.slice(0, open);
  const inner = trimmed.slice(open + 1, close).trim();
  const argTypes = inner === "" ? [] : splitTopLevel(inner);

  // Canonical form drops argument names and spaces; the selector is derived
  // from that, which is why it can be computed offline and compared with what
  // the Registry stored.
  const canonical = `${name}(${argTypes.join(",")})`;
  const selector = keccak256(toHex(canonical)).slice(0, 10) as `0x${string}`;

  const unsupported = argTypes.filter((t) => !isSupportedType(t));

  return {
    raw: trimmed,
    name,
    argTypes,
    selector,
    supported: argTypes.length > 0 && unsupported.length === 0,
    unsupported,
  };
}

/** Splits on commas that are not inside nested parentheses (tuple types). */
function splitTopLevel(s: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let current = "";
  for (const ch of s) {
    if (ch === "(") depth++;
    if (ch === ")") depth--;
    if (ch === "," && depth === 0) {
      parts.push(current.trim());
      current = "";
    } else {
      current += ch;
    }
  }
  if (current.trim() !== "") parts.push(current.trim());
  return parts;
}

/** Human-readable statement of what the agent would have to produce. */
export function describePlan(p: ParsedSignature): string {
  if (p.argTypes.length === 0) {
    return `${p.name}() takes no arguments — nothing to generate, and nothing to vary`;
  }
  const list = p.argTypes.map((t, i) => `arg${i}: ${t}`).join(", ");
  if (!p.supported) {
    return `${list} — cannot generate ${p.unsupported.join(", ")}`;
  }
  return `${list} — all generatable`;
}
