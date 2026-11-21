// Seeded opening prices (M2 spec §3): zero-drift lognormal close-to-close model, daily vol in bps.
import type Decimal from "decimal.js";
import { Dec } from "./lmsr.ts";

const SQRT_2PI = Dec.sqrt(Dec.acos(-1).mul(2));

/** Φ(x) = 1/2 + φ(x)·Σ_k x^(2k+1)/(1·3·…·(2k+1)); converges for all x, ample at 60 digits for |x| ≤ 9. */
export function normCdf(x: Decimal): Decimal {
  if (x.abs().gt(12)) return x.isPositive() ? new Dec(1) : new Dec(0);
  const pdf = Dec.exp(x.mul(x).div(-2)).div(SQRT_2PI);
  let term = new Dec(x);
  let sum = new Dec(x);
  for (let k = 1; k < 2000; k++) {
    term = term
      .mul(x)
      .mul(x)
      .div(2 * k + 1);
    sum = sum.add(term);
    if (term.abs().lt("1e-80")) break;
  }
  return new Dec("0.5").add(pdf.mul(sum));
}

/** P(close > k8) given ref8 and daily vol (bps). */
export function probAbove(ref8: bigint, k8: bigint, volBps: number): Decimal {
  const sigma = new Dec(volBps).div(10_000);
  const d = Dec.ln(new Dec(ref8.toString()).div(k8.toString()))
    .sub(sigma.mul(sigma).div(2))
    .div(sigma);
  return normCdf(d);
}

/** Bucket probabilities for strictly increasing edges: [P(≤e1), P(e1<·≤e2), …, P(>em)]. One edge = ABOVE [NO, YES]. */
export function rawPrior(ref8: bigint, edges8: bigint[], volBps: number): Decimal[] {
  const out: Decimal[] = [];
  let prev: Decimal = new Dec(1);
  for (const e of edges8) {
    const s = probAbove(ref8, e, volBps);
    out.push(prev.sub(s));
    prev = s;
  }
  out.push(prev);
  return out;
}
