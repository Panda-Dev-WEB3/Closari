// 60-digit reference for the fixed-b LMSR (Backend §3.4). Quantities and b are WAD (base units × 1e12).
import Decimal from "decimal.js";

export const Dec = Decimal.clone({ precision: 60, rounding: Decimal.ROUND_HALF_EVEN });
const E12 = new Dec("1e12");

/** C(x) = m + b·ln Σ exp((x_i − m)/b), in WAD. */
export function costWad(x: bigint[], bWad: bigint): Decimal {
  const b = new Dec(bWad.toString());
  const xs = x.map((v) => new Dec(v.toString()));
  const m = Dec.max(...xs);
  const s = xs.reduce((acc, xi) => acc.add(Dec.exp(xi.sub(m).div(b))), new Dec(0));
  return m.add(b.mul(Dec.ln(s)));
}

/** Exact cost in base units of buying `sharesBase` of outcome k. */
export function buyExact(x: bigint[], bWad: bigint, k: number, sharesBase: bigint): Decimal {
  const after = x.slice();
  after[k] = (after[k] ?? 0n) + sharesBase * 10n ** 12n;
  return costWad(after, bWad).sub(costWad(x, bWad)).div(E12);
}

/** Exact proceeds in base units of selling `sharesBase` of outcome k. */
export function sellExact(x: bigint[], bWad: bigint, k: number, sharesBase: bigint): Decimal {
  const after = x.slice();
  after[k] = (after[k] ?? 0n) - sharesBase * 10n ** 12n;
  return costWad(x, bWad).sub(costWad(after, bWad)).div(E12);
}
