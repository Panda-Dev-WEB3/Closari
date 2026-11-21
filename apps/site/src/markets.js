export const universe = [
  ["NVDA", "NVIDIA", "Semiconductors", 190, 0.62, 1.000775, "#fa5636"],
  ["TSLA", "Tesla", "Automotive", 400, 0.46, 1, "#e8ab43"],
  ["SPY", "S&P 500", "Index ETF", 680, 0.53, 1.001718, "#8edbc2"],
  ["AAPL", "Apple", "Consumer technology", 260, 0.57, 1, "#eab7ba"],
  ["AMD", "AMD", "Semiconductors", 225, 0.48, 1, "#7f8ff2"],
  ["QQQ", "Nasdaq 100", "Index ETF", 600, 0.55, 1, "#c99976"],
  ["META", "Meta", "Communications", 650, 0.51, 1, "#7cd7bf"],
  ["MSFT", "Microsoft", "Software", 520, 0.59, 1, "#8cc7fa"],
  ["AMZN", "Amazon", "Consumer technology", 230, 0.54, 1, "#ffc28b"],
  ["GOOGL", "Alphabet", "Communications", 290, 0.58, 1, "#94b2f6"],
  ["PLTR", "Palantir", "Software", 170, 0.47, 1, "#adbaa1"],
  ["MU", "Micron", "Semiconductors", 235, 0.52, 1, "#ada4df"],
].map(([ticker, name, sector, strike, chance, multiplier, color], index) => ({
  ticker,
  name,
  sector,
  strike,
  chance,
  multiplier,
  color,
  index,
  issuer:
    {
      SPY: "SPDR S&P 500 ETF Trust",
      QQQ: "Invesco QQQ Trust",
      GOOGL: "Alphabet Class A",
      MU: "Micron Technology",
    }[ticker] || name,
  art: "/art/" + ticker.toLowerCase() + ".webp",
  sculpture: "/issuer-reliefs/" + ticker.toLowerCase() + ".png",
  logo: "/tokens/" + ticker.toLowerCase() + ".png",
}));

export const formats = ["Strike", "Range", "Up/down"];
export const sampleTime = "14:42 ET";
export const price = (value) =>
  new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  }).format(value);
export const money = (value) =>
  new Intl.NumberFormat("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
export const strikeLevels = [-500, -200, -100, 100, 200, 500];
export const defaultLevel = 100;
export const pctOffset = (level) =>
  (level > 0 ? "+" : "−") + Math.abs(level / 100) + "%";

// The NVDA vignette in the brief specifies a $190 strike. This paper prior
// close makes $190 its +1% listing. All sample listings use a one-cent tick.
const tickPrice = (reference, bps) =>
  Math.floor((Math.round(reference * 100) * (10000 + bps) + 5000) / 10000) /
  100;
export function contract(asset, format, listing = "example") {
  const { ticker, chance, multiplier } = asset;
  const priorClose = ticker === "NVDA" ? 188.12 : asset.strike;
  const old = listing === "example";
  const offset =
    format === "Strike" && !old
      ? strikeLevels.includes(listing)
        ? listing
        : defaultLevel
      : null;
  const reference = old ? asset.strike : priorClose;
  const strike =
    offset !== null
      ? tickPrice(reference, offset)
      : format === "Range"
        ? reference
        : asset.strike;
  const boundaries = [-200, -50, 50, 200].map((level) =>
    tickPrice(reference, level),
  );
  const yes =
    offset === null
      ? chance
      : 1 /
        (1 +
          Math.exp(
            -Math.log(chance / (1 - chance)) + (offset - defaultLevel) / 160,
          ));
  const dailyAlias =
    format === "Strike"
      ? ticker === "NVDA" && (old || offset === defaultLevel)
      : format === "Up/down" || asset.strike === priorClose;
  const identity =
    old || dailyAlias
      ? ticker + "|" + format
      : ticker + "|" + format + "|" + (offset ?? "daily");
  const archived = old && !dailyAlias;
  const rangeLabels = [
    "< " + price(boundaries[0]),
    ...boundaries
      .slice(0, 3)
      .map((v, i) => price(v) + " – " + price(boundaries[i + 1])),
    "≥ " + price(boundaries[3]),
  ];
  const labels =
    format === "Range"
      ? rangeLabels
      : format === "Up/down"
        ? ["Up", "Down"]
        : ["Yes", "No"];
  const probabilities =
    format === "Range" ? Array(5).fill(0.2) : [yes, 1 - yes];
  const question =
    format === "Range"
      ? "Where will " + ticker + " close?"
      : format === "Up/down"
        ? "Will " + ticker + " close above its open?"
        : "Will " + ticker + " close above " + price(strike) + "?";
  return {
    asset,
    format,
    id: identity,
    listing,
    offset,
    strike,
    reference,
    archived,
    labels,
    probabilities,
    question,
    b: 2000 / Math.log(labels.length),
    equivalent: strike / multiplier,
    boundaries,
  };
}
export function marketPath(market, outcome) {
  const params = new URLSearchParams();
  if (market.format !== "Strike") params.set("format", market.format);
  if (market.archived) params.set("series", "example");
  else if (market.offset !== null && market.offset !== defaultLevel)
    params.set("level", String(market.offset));
  if (outcome !== undefined) params.set("outcome", String(outcome));
  const query = params.toString();
  return (
    "/terminal/" +
    market.asset.ticker.toLowerCase() +
    (query ? "?" + query : "")
  );
}
export function chances(market, inventory = []) {
  const weights = market.probabilities.map(
    (p, i) => Math.log(p) + (inventory[i] || 0) / market.b,
  );
  const max = Math.max(...weights),
    exp = weights.map((x) => Math.exp(x - max)),
    sum = exp.reduce((a, b) => a + b, 0);
  return exp.map((value) => value / sum);
}
export function quote(market, inventory, outcome, quantity, side) {
  if (
    !Number.isSafeInteger(quantity) ||
    quantity <= 0 ||
    quantity > 25000 ||
    !Number.isInteger(outcome) ||
    outcome < 0 ||
    outcome >= market.labels.length
  )
    return null;
  const p = chances(market, inventory)[outcome],
    delta = side === "Buy" ? quantity : -quantity;
  const value = Math.abs(
    market.b * Math.log1p(p * Math.expm1(delta / market.b)),
  );
  const quantities = market.labels.map(
    (_, i) => (inventory?.[i] || 0) + (i === outcome ? delta : 0),
  );
  const after = chances(market, quantities);
  const fee = Math.ceil(value * 0.005 * 1e6) / 1e6;
  return {
    value,
    fee,
    total: side === "Buy" ? value + fee : value - fee,
    average: value / quantity,
    priceAfter: after[outcome],
    outsideLimits: after.some((p) => p < 0.001 || p > 0.999),
  };
}
export const bankStart = 10000;
const storageKey = "closari.paper.v1";
export function accountState(trades) {
  let cash = bankStart;
  const positions = {},
    inventories = {};
  const accepted = [];
  for (const t of trades) {
    const a = universe.find((a) => a.ticker === t?.ticker);
    if (
      !a ||
      !formats.includes(t.format) ||
      !["Buy", "Sell"].includes(t.side) ||
      !Number.isInteger(t.outcome)
    )
      continue;
    if (
      t.listing !== undefined &&
      !(
        t.listing === "example" ||
        (t.format === "Strike"
          ? strikeLevels.includes(t.listing)
          : t.listing === "daily")
      )
    )
      continue;
    const m = contract(a, t.format, t.listing),
      inv = inventories[m.id] || Array(m.labels.length).fill(0);
    const key = m.id + "|" + t.outcome,
      pos = positions[key] || { market: m, outcome: t.outcome, shares: 0 };
    const q = quote(m, inv, t.outcome, t.quantity, t.side);
    if (q && t.listing === undefined) {
      q.fee = q.value * 0.005;
      q.total = t.side === "Buy" ? q.value + q.fee : q.value - q.fee;
    }
    if (
      !q ||
      (t.listing !== undefined && q.outsideLimits) ||
      (t.side === "Buy" ? cash < q.total : pos.shares < t.quantity)
    )
      continue;
    const sign = t.side === "Buy" ? 1 : -1;
    cash -= sign * q.total;
    inv[t.outcome] += sign * t.quantity;
    inventories[m.id] = inv;
    positions[key] = { ...pos, shares: pos.shares + sign * t.quantity };
    accepted.push({ ...t, market: m, total: q.total, fee: q.fee });
  }
  return { cash, positions, inventories, trades: accepted };
}
export function readTrades() {
  try {
    const t = JSON.parse(localStorage.getItem(storageKey) || "[]");
    return Array.isArray(t) ? t : [];
  } catch {
    return [];
  }
}
export function saveTrades(trades) {
  localStorage.setItem(storageKey, JSON.stringify(trades));
}
export function historyPoints(
  asset,
  format,
  outcome,
  interval,
  last,
  listing = "example",
) {
  const market = contract(asset, format, listing),
    length = 313;
  const paths = market.labels.map((_, index) => {
    let seed =
      (asset.index + 2) * 9791 + formats.indexOf(format) * 417 + index * 701;
    const series = [];
    let walk = 0;
    for (let minute = 0; minute < length; minute++) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      walk = 0.977 * walk + (seed / 4294967296 - 0.5) * 0.048;
      series.push(walk + Math.sin(minute * 0.049 + index) * 0.074);
    }
    const end = series.at(-1);
    return series.map(
      (v, minute) =>
        market.probabilities[index] *
        Math.exp(
          v - end + (index === 0 ? -1 : 1) * (length - 1 - minute) * 0.0004,
        ),
    );
  });
  const values = paths[outcome].map(
    (v, i) => v / paths.reduce((sum, series) => sum + series[i], 0),
  );
  values[values.length - 1] = last;
  const minutes = interval === "1H" ? 60 : interval === "3H" ? 180 : 312;
  return values.slice(-minutes - 1);
}
