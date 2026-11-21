import { describe, expect, test } from "bun:test";
import {
  compact,
  LAUNCH_EDGE_BPS,
  LAUNCH_STRIKE_BPS,
  positional,
  strike,
} from "../src/strikes/strikes.ts";

const TICK = 50_000_000n; // $0.50

describe("strikes", () => {
  test("NVDA ref $188.12: ±1/2/5% at a $0.50 tick (Overview example: +1% = $190.00)", () => {
    expect(positional(18_812_000_000n, LAUNCH_STRIKE_BPS, TICK)).toEqual([
      17_850_000_000n,
      18_450_000_000n,
      18_600_000_000n,
      19_000_000_000n,
      19_200_000_000n,
      19_750_000_000n,
    ]);
  });

  test("TSLA ref $400: range edges 392 / 398 / 402 / 408", () => {
    expect(positional(40_000_000_000n, LAUNCH_EDGE_BPS, TICK)).toEqual([
      39_200_000_000n,
      39_800_000_000n,
      40_200_000_000n,
      40_800_000_000n,
    ]);
  });

  test("exact half ticks round up", () => {
    expect(strike(10_000_000_000n, 25, TICK)).toBe(10_050_000_000n); // 100.25 → 100.50
    expect(strike(10_000_000_000n, -25, TICK)).toBe(10_000_000_000n); // 99.75 → 100.00
  });

  test("duplicates and non-positive strikes collapse to 0", () => {
    expect(positional(100_000_000n, LAUNCH_STRIKE_BPS, TICK)).toEqual([
      100_000_000n,
      0n,
      0n,
      0n,
      0n,
      0n,
    ]);
    expect(positional(10_000_000n, LAUNCH_STRIKE_BPS, TICK)).toEqual([0n, 0n, 0n, 0n, 0n, 0n]);
    expect(compact([0n, 5n, 0n, 7n])).toEqual([5n, 7n]);
  });

  test("rejects bad inputs", () => {
    expect(() => strike(0n, 100, TICK)).toThrow();
    expect(() => strike(1n, 100, 0n)).toThrow();
    expect(() => strike(1n, -10_000, TICK)).toThrow();
  });
});
