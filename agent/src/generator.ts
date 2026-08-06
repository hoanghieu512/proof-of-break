/**
 * Producing candidate inputs.
 *
 * Two strategies, chosen at the top level, never by the agent itself:
 *
 *   boundary-first  try the boundary list (boundaries.ts) in order, then fall
 *                   through to random draws
 *   random-only     skip the list entirely; random draws from the start
 *
 * The two exist to reproduce the head-to-head number the project rests on:
 * random search misses, boundary search lands almost immediately. Same agent,
 * same lack of any source for the target — only the strategy differs.
 *
 * All randomness is drawn off-chain, from the OS CSPRNG. That is not just
 * convenient: Arc's PREVRANDAO is always 0, so there is no on-chain randomness
 * to draw even if we wanted to. Input generation has to happen here.
 */

import { randomBytes } from "node:crypto";
import { encodeAbiParameters, type AbiParameter } from "viem";
import { boundaryValues, describeBoundary } from "./boundaries.js";
import type { ParsedSignature } from "./signature.js";

export type Strategy = "boundary-first" | "random-only";

export interface Candidate {
  /** ABI-encoded arguments, ready to append to the selector. */
  argsEncoded: `0x${string}`;
  /** The raw values, for logging and for explaining a hit. */
  values: bigint[];
  /** Where this candidate came from. */
  source: "boundary" | "random";
  /** Set when source is "boundary": why a tester would try this value. */
  boundaryReason?: string;
}

const MAX_UINT256 = 2n ** 256n - 1n;

/** A uniform random uint256, drawn from the OS CSPRNG (Arc has no on-chain rand). */
export function randomUint256(): bigint {
  return BigInt(`0x${randomBytes(32).toString("hex")}`) & MAX_UINT256;
}

/** Random value fitting a specific uint width, e.g. uint8 → [0, 255]. */
function randomUintOfWidth(bits: number): bigint {
  const max = (1n << BigInt(bits)) - 1n;
  return randomUint256() & max;
}

function widthOf(type: string): number {
  const m = /^uint(\d+)?$/.exec(type);
  return m ? Number(m[1] ?? "256") : 256;
}

/** A random value appropriate to one argument type. */
function randomForType(type: string): bigint {
  if (/^uint\d*$/.test(type)) return randomUintOfWidth(widthOf(type));
  if (type === "bool") return randomUint256() & 1n;
  // int/address/bytes fall back to a full-width random; the demo target only
  // ever uses uint256, and the signature parser already refuses anything the
  // generator cannot handle, so this is a safety net rather than a hot path.
  return randomUint256();
}

function abiParams(sig: ParsedSignature): AbiParameter[] {
  return sig.argTypes.map((t) => ({ type: t }));
}

function encode(sig: ParsedSignature, values: bigint[]): `0x${string}` {
  // viem wants JS types matching each ABI type; for uint/int a bigint is
  // correct, for bool a boolean, for address a hex string. The demo is all
  // uint256, so bigint straight through; the conversions here keep the general
  // case honest.
  const coerced = sig.argTypes.map((t, i) => {
    const v = values[i];
    if (t === "bool") return v !== 0n;
    if (t === "address") return `0x${(v & ((1n << 160n) - 1n)).toString(16).padStart(40, "0")}`;
    return v;
  });
  return encodeAbiParameters(abiParams(sig), coerced);
}

/**
 * Yields candidates forever. The caller decides when to stop — normally when a
 * bounty falls, or after a cap in the comparison harness.
 *
 * For a single-argument signature (the demo case) the boundary list is walked
 * value by value. For multiple arguments, each boundary value is placed in the
 * first argument with the rest random, then everything goes random — a full
 * combinatorial sweep of boundaries across several arguments is out of scope
 * and would rarely be what finds a bug anyway.
 */
export function* candidates(
  sig: ParsedSignature,
  strategy: Strategy,
): Generator<Candidate> {
  if (strategy === "boundary-first") {
    for (const bv of boundaryValues()) {
      const values = sig.argTypes.map((t, i) =>
        i === 0 ? bv : randomForType(t),
      );
      yield {
        argsEncoded: encode(sig, values),
        values,
        source: "boundary",
        boundaryReason: describeBoundary(bv)?.why,
      };
    }
  }

  // Random tail (boundary-first) or the whole thing (random-only).
  for (;;) {
    const values = sig.argTypes.map((t) => randomForType(t));
    yield {
      argsEncoded: encode(sig, values),
      values,
      source: "random",
    };
  }
}
