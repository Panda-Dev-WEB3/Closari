import { describe, expect, test } from "bun:test";
import Decimal from "decimal.js";
import { buyExact, costWad, Dec, normCdf, rawPrior, sellExact } from "../src/lmsr/index.ts";

const D = (v: string | number) => new Decimal(v);

describe("normCdf", () => {
  test("known values", () => {
    expect(normCdf(D(0)).toFixed(30)).toBe(D("0.5").toFixed(30));
    expect(normCdf(D("1.96")).sub("0.97500210485177952").abs().lt("1e-16")).toBe(true);
    expect(normCdf(D("-1.6448536269514722")).sub("0.05").abs().lt("1e-15")).toBe(true);
  });
  test("symmetry", () => {
    for (const x of ["0.3", "1.1", "2.5", "4", "7.5"]) {
      expect(
        normCdf(D(x))
          .add(normCdf(D(x).neg()))
          .sub(1)
          .abs()
          .lt("1e-40"),
      ).toBe(true);
    }
  });
});

describe("cost", () => {
  test("uniform start costs b·ln n", () => {
    const b = 1000n * 10n ** 18n;
    const c = costWad([0n, 0n, 0n], b);
    const expected = new Dec(b.toString()).mul(Dec.ln(3)); // 60-digit reference; global Decimal.ln is 20-digit
    expect(c.sub(expected).abs().lt("1e-30")).toBe(true);
  });
  test("buy then sell the same shares is exact inverse", () => {
    const b = 2885n * 10n ** 18n;
    const x = [0n, 0n];
    const buy = buyExact(x, b, 0, 100_000_000n);
    const sell = sellExact([100_000_000n * 10n ** 12n, 0n], b, 0, 100_000_000n);
    expect(buy.sub(sell).abs().lt("1e-30")).toBe(true);
    expect(buy.gt(50_000_000)).toBe(true); // 100 shares at p≈0.5 cost > 50 USDG
  });
});

describe("rawPrior", () => {
  test("one edge: [P(≤K), P(>K)] sums to 1, +5% at 3% vol ≈ 0.05", () => {
    const ref = 18_812_000_000n;
    const k = (ref * 105n) / 100n;
    const p = rawPrior(ref, [k], 300);
    expect(p.length).toBe(2);
    const [pNo = D(0), pYes = D(0)] = p;
    expect(pNo.add(pYes).sub(1).abs().lt("1e-40")).toBe(true);
    expect(pYes.gt("0.049")).toBe(true);
    expect(pYes.lt("0.052")).toBe(true);
  });
  test("range buckets sum to 1", () => {
    const ref = 18_812_000_000n;
    const edges = [18_450_000_000n, 18_700_000_000n, 18_900_000_000n, 19_200_000_000n];
    const p = rawPrior(ref, edges, 300);
    expect(p.length).toBe(5);
    expect(
      p
        .reduce((a, v) => a.add(v), D(0))
        .sub(1)
        .abs()
        .lt("1e-40"),
    ).toBe(true);
  });
});
