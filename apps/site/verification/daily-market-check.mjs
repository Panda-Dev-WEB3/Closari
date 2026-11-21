import assert from "node:assert/strict";
import {
  accountState,
  contract,
  quote,
  marketPath,
  universe,
  strikeLevels,
  chances,
} from "../src/markets.js";
const ids = new Set(),
  links = new Set();
for (const asset of universe) {
  let lastStrike = -Infinity,
    lastYes = Infinity;
  for (const offset of strikeLevels) {
    const m = contract(asset, "Strike", offset);
    assert.ok(m.strike > lastStrike && m.probabilities[0] < lastYes);
    assert.equal(
      Math.round(m.strike * 100),
      Math.floor(
        (Math.round(m.reference * 100) * (10000 + offset) + 5000) / 10000,
      ),
    );
    assert.equal(m.equivalent, m.strike / asset.multiplier);
    lastStrike = m.strike;
    lastYes = m.probabilities[0];
    ids.add(m.id);
    links.add(marketPath(m));
    const q = quote(m, [], 0, 50, "Buy");
    assert.equal(q.priceAfter, chances(m, [50, 0])[0]);
    assert.ok(q.priceAfter > m.probabilities[0]);
    assert.ok(q.fee >= q.value * 0.005 && q.fee - q.value * 0.005 < 0.000001);
  }
  for (const kind of ["Range", "Up/down"]) {
    const m = contract(asset, kind, "daily");
    ids.add(m.id);
    links.add(marketPath(m));
    assert.equal(m.labels.length, kind === "Range" ? 5 : 2);
  }
}
assert.equal(ids.size, 96);
assert.equal(links.size, 96);
const [nvda, tsla] = universe;
assert.equal(contract(nvda, "Strike", 100).strike, 190);
assert.deepEqual(
  contract(tsla, "Range", "daily").boundaries,
  [392, 398, 402, 408],
);
const fill = {
  ticker: "NVDA",
  format: "Strike",
  quantity: 100,
  outcome: 0,
  side: "Buy",
};
const state = accountState([
  fill,
  { ...fill, listing: -100 },
  { ...fill, listing: 100, side: "Sell", quantity: 40 },
]);
assert.equal(state.positions["NVDA|Strike|0"].shares, 60);
assert.equal(
  state.positions[contract(nvda, "Strike", -100).id + "|0"].shares,
  100,
);
const old = accountState([{ ...fill, ticker: "TSLA" }]);
const oldMarket = Object.values(old.positions)[0].market;
assert.equal(oldMarket.strike, 400);
assert.ok(marketPath(oldMarket).includes("series=example"));
assert.notEqual(oldMarket.id, contract(tsla, "Strike", 100).id);
assert.equal(accountState([{ ...fill, listing: 333 }]).trades.length, 0);
assert.equal(
  quote(contract(nvda, "Strike", -500), [], 0, 25000, "Buy").outsideLimits,
  true,
);
console.log(
  "96 daily market identities and links, strike rounding, fee precision, quote impact, scope of inventory and earlier paper positions verified.",
);
