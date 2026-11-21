// Writes the shared test vectors the Solidity tests read. Re-run after changing a reference.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { LAUNCH_EDGE_BPS, LAUNCH_STRIKE_BPS, positional } from "../src/strikes/strikes.ts";

const VECTORS = join(import.meta.dir, "..", "..", "..", "contracts", "test", "vectors");
mkdirSync(VECTORS, { recursive: true });

const num = (x: bigint): number => {
  if (x > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error(`unsafe JSON number ${x}`);
  return Number(x);
};

// Reference prices: the launch tokens' Chainlink answers read on 2026-11-21, plus the Overview examples.
const REFS: Record<string, bigint> = {
  NVDA: 13_000_000_000n,
  TSLA: 35_000_000_000n,
  SPY: 69_940_000_000n,
  QQQ: 61_720_000_000n,
  AAPL: 34_455_000_000n,
  META: 56_731_000_000n,
  MSFT: 49_015_000_000n,
  AMZN: 25_061_000_000n,
  GOOGL: 27_078_000_000n,
  AMD: 43_958_000_000n,
  PLTR: 14_612_000_000n,
  MU: 60_835_000_000n,
  NVDA_EXAMPLE: 18_812_000_000n,
  TSLA_EXAMPLE: 40_000_000_000n,
};
const TICKS = [10_000_000n, 50_000_000n, 100_000_000n]; // $0.10, $0.50, $1.00

type Case = { name: string; ref8: number; tick8: number; bps: number[]; expected: number[] };
const cases: Case[] = [];
const add = (name: string, ref8: bigint, tick8: bigint, bps: readonly number[]) =>
  cases.push({
    name,
    ref8: num(ref8),
    tick8: num(tick8),
    bps: [...bps],
    expected: positional(ref8, bps, tick8).map(num),
  });

for (const [t, ref] of Object.entries(REFS)) {
  for (const tick of TICKS) {
    add(`${t}/above/${tick}`, ref, tick, LAUNCH_STRIKE_BPS);
    add(`${t}/range/${tick}`, ref, tick, LAUNCH_EDGE_BPS);
  }
}
add("halfUp", 10_000_000_000n, 50_000_000n, [-25, 25]);
add("collapse", 100_000_000n, 50_000_000n, LAUNCH_STRIKE_BPS);
add("allZero", 10_000_000n, 50_000_000n, LAUNCH_STRIKE_BPS);
add("extremes", 9_999_999_999n, 1_000_000n, [-9_999, -5_000, 0, 5_000, 9_999]);

writeFileSync(
  join(VECTORS, "strikes.json"),
  `${JSON.stringify({ count: cases.length, cases }, null, 2)}\n`,
);
console.log(`strikes.json: ${cases.length} cases`);
