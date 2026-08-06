/**
 * The boundary value list.
 *
 * This is the file to read if you want to see the QA thinking behind the whole
 * project. Everything else is plumbing; this is the judgement.
 *
 * WHAT THIS IS, AND WHAT IT DELIBERATELY IS NOT
 *
 * These are the values a tester tries first against ANY function that takes a
 * uint256 quantity — before knowing anything about the contract's internals.
 * The agent has no source for the target. It reads one function signature,
 * `deposit(uint256)`, and nothing more. So this list cannot and does not contain
 * the target's actual bug threshold; it contains the values that are suspicious
 * in general.
 *
 * That distinction is the entire point. The planted bug happens to sit at
 * exactly 1e18. 1e18 is on this list — but it is here because "one whole token
 * at 18 decimals" is the single most common amount in all of DeFi, the first
 * round number any tester of a token amount reaches for. It is NOT here because
 * anyone told the agent where the bug was. If it were, this would be a lookup,
 * not a search.
 *
 * WHY THE ORDER
 *
 * Cheapest and most-suspicious first. Degenerate values (0, 1, 2), then the
 * human-meaningful "one unit at N decimals" amounts, then the machine-word
 * ceilings. This ordering is what makes boundary search fast: the values most
 * likely to expose an off-by-one or a decimals confusion are tried before the
 * fuzzer would have made its first random guess.
 *
 * On DemoVault this list reaches the bug on the 6th probe. That number is not
 * tuned — it falls out of putting 1e18 where a tester would naturally put it.
 * See docs/measurements/task1-findability.md.
 */

export interface BoundaryValue {
  value: bigint;
  label: string;
  why: string;
}

/**
 * Boundary values for a uint256 amount, most-suspicious first.
 *
 * Nothing here is specific to DemoVault. Swap in any contract taking a uint256
 * quantity and this is still the right first list to try.
 */
export const UINT256_BOUNDARIES: BoundaryValue[] = [
  {
    value: 0n,
    label: "zero",
    why: "the additive identity and the classic degenerate input; many functions special-case it or forget to",
  },
  {
    value: 1n,
    label: "one",
    why: "the smallest positive value; off-by-one bugs live in the gap between 0 and 1",
  },
  {
    value: 2n,
    label: "two",
    why: "the smallest value that is neither identity nor edge; catches 'x > 1' vs 'x >= 1' slips",
  },
  {
    value: 1_000_000n, // 1e6
    label: "1e6 (one unit at 6 decimals)",
    why: "one whole USDC in its ERC-20 form; a decimals confusion between 6 and 18 shows up here first",
  },
  {
    value: 1_000_000_000n, // 1e9
    label: "1e9 (one gwei)",
    why: "one unit at 9 decimals, and the gwei scale; a common intermediate a developer might hardcode",
  },
  {
    // The planted bug is at exactly this value. It is on the list because it is
    // the most ordinary token amount there is, not because the agent knows.
    value: 1_000_000_000_000_000_000n, // 1e18
    label: "1e18 (one whole unit at 18 decimals)",
    why: "one whole token at the standard 18 decimals — the most common single amount in DeFi, and the first round number any tester of a token quantity tries",
  },
  {
    value: 255n, // 2**8 - 1
    label: "uint8 max",
    why: "the first machine-word ceiling; catches an unsafe downcast to uint8",
  },
  {
    value: 65_535n, // 2**16 - 1
    label: "uint16 max",
    why: "downcast-to-uint16 boundary",
  },
  {
    value: 4_294_967_295n, // 2**32 - 1
    label: "uint32 max",
    why: "downcast-to-uint32 boundary; also the 32-bit timestamp/counter ceiling",
  },
  {
    value: 18_446_744_073_709_551_615n, // 2**64 - 1
    label: "uint64 max",
    why: "downcast-to-uint64 boundary; a very common storage-packing width",
  },
  {
    value: 340_282_366_920_938_463_463_374_607_431_768_211_455n, // 2**128 - 1
    label: "uint128 max",
    why: "downcast-to-uint128 boundary; the width DemoVault's own bonus maths would overflow past",
  },
  {
    value: (1n << 128n), // 2**128
    label: "2**128",
    why: "one past the uint128 ceiling; the exact value an unsafe uint128 cast wraps to zero",
  },
  {
    value: 2n ** 256n - 1n,
    label: "uint256 max",
    why: "the largest representable value; forces every addition in the function to its overflow edge",
  },
];

/** Just the values, in order, for a generator that does not need the reasons. */
export function boundaryValues(): bigint[] {
  return UINT256_BOUNDARIES.map((b) => b.value);
}

/** Find the annotation for a value, so a hit can be explained in the log. */
export function describeBoundary(value: bigint): BoundaryValue | undefined {
  return UINT256_BOUNDARIES.find((b) => b.value === value);
}
