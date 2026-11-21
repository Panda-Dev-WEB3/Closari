// Bigint reference for contracts/src/lib/StrikeMath.sol. Both sides must agree on contracts/test/vectors/strikes.json.
export const LAUNCH_STRIKE_BPS: readonly number[] = [-500, -200, -100, 100, 200, 500];
export const LAUNCH_EDGE_BPS: readonly number[] = [-200, -50, 50, 200];

/** roundHalfUp(ref8 × (10_000 + bps) / 10_000, tick8), computed exactly on the rational. */
export function strike(ref8: bigint, bps: number, tick8: bigint): bigint {
  if (ref8 <= 0n) throw new Error("bad reference");
  if (tick8 <= 0n) throw new Error("bad tick");
  if (bps <= -10_000) throw new Error("bad bps");
  const num = ref8 * (10_000n + BigInt(bps));
  const den = 10_000n * tick8;
  return ((2n * num + den) / (2n * den)) * tick8;
}

/** Strikes by template index; 0 = collapsed (non-positive or not strictly above the previous kept strike). */
export function positional(ref8: bigint, bps: readonly number[], tick8: bigint): bigint[] {
  let last = 0n;
  return bps.map((b) => {
    const s = strike(ref8, b, tick8);
    if (s > last) {
      last = s;
      return s;
    }
    return 0n;
  });
}

export function compact(p: readonly bigint[]): bigint[] {
  return p.filter((x) => x !== 0n);
}
