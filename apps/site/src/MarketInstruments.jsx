import React from "react";
import {
  chances,
  contract,
  marketPath,
  money,
  pctOffset,
  price,
  strikeLevels,
} from "./markets";

export function StrikeBoard({ market, account }) {
  return (
    <nav className="strike-board" aria-label="Daily strike markets">
      <div className="instrument-label">
        <span>Strike ladder</span>
        <span>Prior token close {price(market.reference)}</span>
      </div>
      <div className="strike-keys">
        {strikeLevels.map((level) => {
          const m = contract(market.asset, "Strike", level);
          const p = chances(m, account.inventories[m.id])[0];
          return (
            <a
              key={level}
              href={marketPath(m)}
              aria-current={market.id === m.id ? "page" : undefined}
              aria-label={
                pctOffset(level) +
                " strike, " +
                price(m.strike) +
                " per token, approximately " +
                price(m.equivalent) +
                " per share"
              }
            >
              <span className="strike-offset">{pctOffset(level)}</span>
              <strong>{price(m.strike)}</strong>
              <small>≈ {price(m.equivalent)}/sh</small>
              <i aria-hidden="true">
                <b style={{ width: p * 100 + "%" }} />
              </i>
            </a>
          );
        })}
      </div>
    </nav>
  );
}

export function ExecutionPreview({ before, q }) {
  if (!q) return null;
  const delta = (q.priceAfter - before) * 100;
  return (
    <div className="execution-preview">
      <div>
        <span className="ticket-label">Quote after order</span>
        <strong>{(q.priceAfter * 100).toFixed(2)}¢</strong>
      </div>
      <span className="impact-gauge" aria-hidden="true">
        <i style={{ width: before * 100 + "%" }} />
        <b style={{ left: q.priceAfter * 100 + "%" }} />
      </span>
      <div className="impact-caption">
        <span>Now {(before * 100).toFixed(2)}¢</span>
        <span>
          {delta > 0 ? "+" : ""}
          {delta.toFixed(2)}¢ impact
        </span>
      </div>
    </div>
  );
}

export function SessionStrip({ account }) {
  const positions = Object.values(account.positions).filter(
    (p) => p.shares > 0,
  );
  const mark = positions.reduce(
    (total, p) =>
      total +
      chances(p.market, account.inventories[p.market.id])[p.outcome] * p.shares,
    0,
  );
  return (
    <section className="account-strip" aria-label="Paper account and session">
      <div className="session-indicator">
        <i />
        <span>Paper session</span>
        <strong>
          14:42 <small>ET</small>
        </strong>
        <small>Nov 18, 2026 · frozen</small>
      </div>
      <dl>
        <div>
          <dt>Available cash</dt>
          <dd>
            {money(account.cash)} <small>USDG</small>
          </dd>
        </div>
        <div>
          <dt>Position value</dt>
          <dd>
            {money(mark)} <small>USDG</small>
          </dd>
        </div>
        <div>
          <dt>Paper fills</dt>
          <dd>{String(account.trades.length).padStart(2, "0")}</dd>
        </div>
      </dl>
    </section>
  );
}

export function MarketTerms({ market, account }) {
  const { asset, format } = market;
  const fills = account.trades.filter(
    (t) =>
      t.ticker === asset.ticker &&
      t.format === format &&
      contract(asset, t.format, t.listing).id === market.id,
  );
  const volume = fills.reduce(
    (total, t) =>
      total + (t.side === "Buy" ? t.total - t.fee : t.total + t.fee),
    0,
  );
  return (
    <div className="market-terms">
      <dl>
        {[
          ["Market budget", "2,000.00 USDG"],
          ["Liquidity parameter", money(market.b) + " shares"],
          ["Paper volume", money(volume) + " USDG"],
          ["Listing multiplier", asset.multiplier.toFixed(6) + "×"],
          ["Base fee at 14:42", "0.50%"],
          ["Late fee ramp", "15:20–15:50 ET"],
        ].map(([k, v]) => (
          <div key={k}>
            <dt>{k}</dt>
            <dd>{v}</dd>
          </div>
        ))}
      </dl>
      <p>
        The 30-minute ramp adds up to 2.50% at the halt. Staking discounts apply
        only to the base fee.
      </p>
      {format === "Range" && (
        <p>
          Token edges {market.boundaries.map(price).join(" · ")}. Equivalent
          share prices{" "}
          {market.boundaries
            .map((edge) => price(edge / asset.multiplier))
            .join(" · ")}
          .
        </p>
      )}
      {format === "Up/down" && (
        <p>
          The paper opening reference is {price(market.strike)} per token.
          Up/down uses the sum of the opening and closing confidence bands.
        </p>
      )}
      <a href="/field/liquidity">How the pool funds this market ↗</a>
    </div>
  );
}

export function SettlementStatus() {
  return (
    <div className="proof-panel">
      <div className="proof-heading">
        <span className="status-lamp" />
        Awaiting the bell <small>Paper session</small>
      </div>
      <dl>
        {[
          ["Pyth update", "Due at 16:00 ET"],
          ["Chainlink cross-check", "Round pending"],
          ["Claimable / deferred", "0.00 / 0.00 USDG"],
        ].map(([k, v]) => (
          <div key={k}>
            <dt>{k}</dt>
            <dd>{v}</dd>
          </div>
        ))}
      </dl>
      <p>
        The closing proof records the signed Pyth update and any eligible
        Chainlink round. A round older than 15 minutes is skipped. At this
        pre-close snapshot, the proof and payout are pending.
      </p>
      <a href="/docs/settlement">Read the settlement rules ↗</a>
    </div>
  );
}
