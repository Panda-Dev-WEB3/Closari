import assert from "node:assert/strict";
import { existsSync } from "node:fs";
const sibling = new URL("../src/markets.js", import.meta.url);
const { universe, contract, quote, chances, accountState, historyPoints } =
  await import(sibling.href);
assert.equal(universe.length, 12);
for (const a of universe) {
  assert.ok(
    existsSync(new URL("../public" + a.logo, import.meta.url)),
    a.ticker + " PNG",
  );
  for (const format of ["Strike", "Range", "Up/down"]) {
    const m = contract(a, format),
      p = chances(m, []);
    assert.ok(Math.abs(p.reduce((sum, n) => sum + n, 0) - 1) < 1e-12);
    for (let i = 0; i < m.labels.length; i++) {
      const take = quote(m, [], i, 100, "Buy"),
        inv = Array(p.length).fill(0);
      inv[i] = 100;
      const unwind = quote(m, inv, i, 100, "Sell");
      assert.ok(Math.abs(take.value - unwind.value) < 1e-8);
      assert.ok(take.total > unwind.total);
      assert.ok(chances(m, inv)[i] > p[i]);
      const path = historyPoints(a, format, i, "Day", p[i]),
        short = historyPoints(a, format, i, "1H", p[i]);
      assert.deepEqual(short, path.slice(-61));
      assert.equal(short.at(-1), p[i]);
    }
  }
}
const m = contract(universe[0], "Strike"),
  q = quote(m, [], 0, 100, "Buy");
assert.equal(q.total.toFixed(2), "62.72");
assert.equal(
  quote(contract(universe[1], "Range"), [], 2, 50, "Buy").value.toFixed(2),
  "10.16",
);
assert.equal(quote(m, [], 0, 0, "Buy"), null);
const trade = {
  ticker: "NVDA",
  format: "Strike",
  outcome: 0,
  quantity: 100,
  side: "Buy",
};
const a = accountState([
  trade,
  { ...trade, quantity: 101, side: "Sell" },
  { ...trade, quantity: 40, side: "Sell" },
  null,
]);
assert.equal(a.trades.length, 2);
assert.equal(a.positions["NVDA|Strike|0"].shares, 60);
assert.ok(a.cash < 10000);
assert.deepEqual(accountState(a.trades), a);
console.log(
  "Pricing, fee, reverse trade, price-history and ledger checks passed for all 36 sample contracts.",
);
