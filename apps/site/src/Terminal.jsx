import { InstrumentIcon } from "./InstrumentIcon";
import {
  StrikeBoard,
  ExecutionPreview,
  MarketTerms,
  SettlementStatus,
  SessionStrip,
} from "./MarketInstruments";
import React, { useState, useMemo, useRef, useEffect } from "react";
import {
  universe,
  formats,
  contract,
  chances,
  quote,
  readTrades,
  saveTrades,
  accountState,
  price,
  money,
  marketPath,
  defaultLevel,
  strikeLevels,
} from "./markets";
import { Icon, Bracket } from "./shared";
import Chart from "./Chart";
import MarketFinder from "./MarketFinder";
import "./terminal.css";

const pct = (p) => (p * 100).toFixed(1) + "%";
function storedStars() {
  try {
    const value = JSON.parse(localStorage.getItem("closari.favorites") || "[]");
    return Array.isArray(value)
      ? value.filter((x) => universe.some((a) => a.ticker === x))
      : [];
  } catch {
    return [];
  }
}
function MarketRail({ asset, format, listing, stars, account }) {
  const [filter, setFilter] = useState("All");
  const list = universe.filter(
    (a) => filter === "All" || stars.includes(a.ticker),
  );
  return (
    <section className="ticker-rack" aria-label="Market selector">
      <div className="rack-top">
        <div className="rack-filter">
          {["All", "Watchlist"].map((f) => (
            <button
              key={f}
              aria-pressed={filter === f}
              onClick={() => setFilter(f)}
            >
              {f === "All" ? "Market tape" : f}
              <sup>
                {f === "All" ? "12" : String(stars.length).padStart(2, "0")}
              </sup>
            </button>
          ))}
        </div>
        <MarketFinder account={account} />
      </div>
      <div className="ticker-list">
        {list.map((a) => {
          const m = contract(a, format, listing),
            p = chances(m, account.inventories[m.id])[
              format === "Range" ? 2 : 0
            ];
          return (
            <a
              className={
                "ticker-chip " + (a.ticker === asset.ticker ? "selected" : "")
              }
              href={marketPath(m)}
              key={a.ticker}
              aria-current={a === asset ? "true" : undefined}
            >
              <img className="stock-logo" alt={a.issuer} src={a.logo} />
              <span>
                <b>{a.ticker}</b>
                <small>{(p * 100).toFixed(1)}¢</small>
              </span>
            </a>
          );
        })}
        {!list.length && (
          <p className="rack-empty">
            Star a market to add it to your watchlist.
          </p>
        )}
      </div>
    </section>
  );
}
function Ticket({ market, account, outcome, setOutcome, onReview, notice }) {
  const [side, setSide] = useState("Buy"),
    [raw, setRaw] = useState("100");
  useEffect(() => {
    setSide("Buy");
    setRaw("100");
  }, [market.id]);
  const qty = Number(raw),
    inv = account.inventories[market.id],
    probs = chances(market, inv),
    q = quote(market, inv, outcome, qty, side);
  const held = account.positions[market.id + "|" + outcome]?.shares || 0;
  const reason = !q
    ? "Enter 1–25,000 whole shares."
    : q.outsideLimits
      ? "Reduce the quantity to keep every outcome between 0.1¢ and 99.9¢."
      : side === "Buy" && q.total > account.cash
        ? "Insufficient paper balance."
        : side === "Sell" && qty > held
          ? "Paper position holds " + held + " shares."
          : "";
  const info = (label, value) => (
    <div>
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
  return (
    <aside
      id="paper-order"
      className="ticket"
      tabIndex={-1}
      aria-label="Paper order ticket"
    >
      <div className="ticket-heading">
        <h2>
          <InstrumentIcon name="ticket" size={23} />
          Order ticket
        </h2>
        <span className="paper-stamp">Paper</span>
      </div>
      <div className="side-switch">
        {["Buy", "Sell"].map((x) => (
          <button key={x} aria-pressed={side === x} onClick={() => setSide(x)}>
            {x}
          </button>
        ))}
      </div>
      <p className="ticket-label">Outcome</p>
      <div
        className={"outcome-picks " + (market.format === "Range" ? "many" : "")}
      >
        {market.labels.map((label, i) => (
          <button
            key={label}
            aria-pressed={outcome === i}
            onClick={() => setOutcome(i)}
          >
            <span>{label}</span>
            <b>{(probs[i] * 100).toFixed(1)}¢</b>
          </button>
        ))}
      </div>
      <label className="ticket-label" htmlFor="share-qty">
        {side === "Buy" ? "Shares to buy" : "Shares to sell"}
      </label>
      <div className="qty-input">
        <input
          id="share-qty"
          inputMode="numeric"
          type="number"
          min="1"
          max="25000"
          step="1"
          value={raw}
          onChange={(e) => setRaw(e.target.value)}
          aria-describedby={reason ? "ticket-error" : undefined}
        />
        <span>shares</span>
      </div>
      <div className="quick-qty">
        {[10, 50, 100, 250].map((v) => (
          <button
            key={v}
            aria-pressed={qty === v}
            onClick={() => setRaw(String(v))}
          >
            {v}
          </button>
        ))}
      </div>
      <ExecutionPreview before={probs[outcome]} q={q} />
      <dl className="quote-lines">
        {info("Average / share", q ? money(q.average * 100) + "¢" : "—")}
        {info(
          side === "Buy" ? "Gross cost" : "Gross proceeds",
          q ? money(q.value) + " USDG" : "—",
        )}
        {info("Fee · 0.50%", q ? money(q.fee) + " USDG" : "—")}
        {info(
          side === "Buy" ? "Total cost" : "Net proceeds",
          q ? money(q.total) + " USDG" : "—",
        )}
        {side === "Buy" &&
          info("Payout if correct", q ? money(qty) + " USDG" : "—")}
      </dl>
      {reason && (
        <p id="ticket-error" className="ticket-error" role="status">
          {reason}
        </p>
      )}
      <button
        className="ticket-cta"
        disabled={!!reason}
        onClick={() =>
          onReview(
            {
              ticker: market.asset.ticker,
              format: market.format,
              listing: market.listing,
              outcome,
              side,
              quantity: qty,
            },
            q,
          )
        }
      >
        <span>Review paper {side.toLowerCase()}</span>
        <Icon name="arrow" />
      </button>
      <div className="ticket-balance">
        <span>
          {side === "Buy" ? "Available paper cash" : "Held in this outcome"}
        </span>
        <b>
          {side === "Buy" ? money(account.cash) + " USDG" : held + " shares"}
        </b>
      </div>
      {notice && (
        <p className="trade-notice" role="status">
          {notice}
        </p>
      )}
    </aside>
  );
}
function CloseScenario({ market, outcome }) {
  const [move, setMove] = useState(0.75);
  const mark = market.strike * (1 + move / 100),
    band = market.strike * 0.0005 * (market.format === "Up/down" ? 2 : 1);
  const edges = market.format === "Range" ? market.boundaries : [market.strike];
  const closeToEdge = edges.some(
    (edge) => Math.abs(mark - edge) <= band + 1e-9,
  );
  const winning =
    market.format === "Range"
      ? edges.filter((edge) => mark >= edge).length
      : mark > market.strike
        ? 0
        : 1;
  const payout = winning === outcome ? 100 : 0;
  return (
    <div className="close-scenario">
      <div>
        <label htmlFor="sample-bell-price">Hypothetical token close</label>
        <strong>{price(mark)}</strong>
        <input
          id="sample-bell-price"
          type="range"
          min="-3"
          max="3"
          step=".05"
          value={move}
          onChange={(e) => setMove(Number(e.target.value))}
        />
        <div className="scenario-range">
          <span>{price(market.strike * 0.97)}</span>
          <span>{price(market.strike * 1.03)}</span>
        </div>
      </div>
      <div aria-live="polite">
        <p className="eyebrow">100 {market.labels[outcome]} shares</p>
        <b>{closeToEdge ? "Void window" : money(payout) + " USDG"}</b>
        <p>
          {closeToEdge
            ? "The example close is inside the confidence band of an edge. The void payout depends on the time-weighted market price and fees."
            : market.labels[winning] +
              " wins at this example close. The amount shown is the gross payout."}
        </p>
        <small>
          Assumes valid feeds and an illustrative comparison band of ±
          {price(band)}.
        </small>
      </div>
    </div>
  );
}
function Ledger({ tab, setTab, market, probs, account, onChoose, outcome }) {
  const positions = Object.values(account.positions).filter(
    (p) => p.shares > 0,
  );
  return (
    <section className="ledger">
      <div className="ledger-tabs" aria-label="Market records">
        {[
          "Outcomes",
          "At close",
          "Positions",
          "Activity",
          "Market terms",
          "Settlement",
        ].map((name) => (
          <button
            key={name}
            aria-pressed={tab === name}
            onClick={() => setTab(name)}
          >
            {name}
            {name === "Positions" && <sup>{positions.length}</sup>}
          </button>
        ))}
      </div>
      {tab === "Market terms" && (
        <MarketTerms market={market} account={account} />
      )}
      {tab === "Settlement" && <SettlementStatus />}
      {tab === "At close" && (
        <CloseScenario key={market.id} market={market} outcome={outcome} />
      )}
      {tab === "Outcomes" && (
        <div className="outcome-ledger">
          {market.labels.map((name, i) => (
            <button
              key={name}
              onClick={() => onChoose(i)}
              aria-pressed={outcome === i}
            >
              <span className="outcome-num">0{i + 1}</span>
              <b>{name}</b>
              <i>
                <em style={{ width: pct(probs[i]) }} />
              </i>
              <strong>{pct(probs[i])}</strong>
              <Icon name="arrow" size={15} />
            </button>
          ))}
        </div>
      )}
      {tab === "Positions" &&
        (positions.length ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Market</th>
                  <th>Outcome</th>
                  <th>Shares</th>
                  <th>Current mark</th>
                </tr>
              </thead>
              <tbody>
                {positions.map((p) => {
                  const prob = chances(
                    p.market,
                    account.inventories[p.market.id],
                  )[p.outcome];
                  return (
                    <tr key={p.market.id + p.outcome}>
                      <td>
                        <a href={marketPath(p.market, p.outcome)}>
                          <img
                            className="ledger-mark"
                            src={p.market.asset.logo}
                            alt=""
                          />
                          {p.market.asset.ticker} ·{" "}
                          {p.market.format === "Strike"
                            ? price(p.market.strike)
                            : p.market.format}{" "}
                          ↗
                        </a>
                      </td>
                      <td>{p.market.labels[p.outcome]}</td>
                      <td>{p.shares}</td>
                      <td>{money(prob * p.shares)} USDG</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="ledger-empty">
            Your first paper position will appear here after you confirm a
            trade.
          </p>
        ))}
      {tab === "Activity" &&
        (account.trades.length ? (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Fill</th>
                  <th>Market</th>
                  <th>Shares</th>
                  <th>Cash movement</th>
                </tr>
              </thead>
              <tbody>
                {account.trades
                  .slice()
                  .reverse()
                  .map((t, i) => (
                    <tr key={i}>
                      <td>{t.side}</td>
                      <td>
                        <a href={marketPath(t.market, t.outcome)}>
                          <img
                            className="ledger-mark"
                            src={t.market.asset.logo}
                            alt=""
                          />
                          {t.ticker} ·{" "}
                          {t.format === "Strike"
                            ? price(t.market.strike)
                            : t.format}{" "}
                          · {t.market.labels[t.outcome]}
                        </a>
                      </td>
                      <td>{t.quantity}</td>
                      <td>
                        {t.side === "Buy" ? "−" : "+"}
                        {money(t.total)} USDG
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="ledger-empty">
            Confirmed paper fills appear here in the order they were placed.
          </p>
        ))}
    </section>
  );
}
export default function Terminal({ route }) {
  const url = new URL(route, location.origin),
    symbol = url.pathname.split("/")[2]?.toUpperCase() || "NVDA";
  const asset = universe.find((a) => a.ticker === symbol),
    format = formats.includes(url.searchParams.get("format"))
      ? url.searchParams.get("format")
      : "Strike";
  if (!asset)
    return (
      <main className="inner">
        <h1>Market unavailable.</h1>
        <p className="lead">This symbol is outside the twelve paper markets.</p>
        <Bracket href="/markets">Market index</Bracket>
      </main>
    );
  const level = Number(url.searchParams.get("level"));
  const listing =
    url.searchParams.get("series") === "example"
      ? "example"
      : format === "Strike"
        ? strikeLevels.includes(level)
          ? level
          : defaultLevel
        : "daily";
  return (
    <Desk
      listing={listing}
      asset={asset}
      format={format}
      requestedOutcome={url.searchParams.get("outcome")}
    />
  );
}
function Desk({ asset, format, listing, requestedOutcome }) {
  const market = useMemo(
    () => contract(asset, format, listing),
    [asset, format, listing],
  );
  const [selected, setSelected] = useState(0),
    validOutcome = Number(requestedOutcome),
    outcome = Math.min(selected, market.labels.length - 1);
  const [trades, setTrades] = useState(readTrades),
    [stars, setStars] = useState(storedStars),
    [tab, setTab] = useState("Outcomes"),
    [notice, setNotice] = useState(""),
    [review, setReview] = useState(null);
  const account = useMemo(() => accountState(trades), [trades]),
    prob = chances(market, account.inventories[market.id]);
  const modal = useRef(null),
    busy = useRef(false);
  useEffect(() => {
    setSelected(
      requestedOutcome !== null &&
        Number.isInteger(validOutcome) &&
        validOutcome >= 0 &&
        validOutcome < market.labels.length
        ? validOutcome
        : format === "Range"
          ? 2
          : 0,
    );
    setNotice("");
    setReview(null);
    modal.current?.close();
  }, [market.id, requestedOutcome]);
  useEffect(() => {
    const sync = () => {
      setTrades(readTrades());
      setStars(storedStars());
    };
    window.addEventListener("storage", sync);
    return () => window.removeEventListener("storage", sync);
  }, []);
  const starred = stars.includes(asset.ticker);
  function toggleStar() {
    const list = storedStars(),
      next = list.includes(asset.ticker)
        ? list.filter((a) => a !== asset.ticker)
        : [...list, asset.ticker];
    try {
      localStorage.setItem("closari.favorites", JSON.stringify(next));
      setStars(next);
    } catch {
      setNotice("This browser could not save the watchlist.");
    }
  }
  function openReview(trade, q) {
    setNotice("");
    setReview({ trade, q });
    modal.current.showModal();
  }
  async function confirm() {
    if (!review || busy.current) return;
    busy.current = true;
    const execute = () => {
      const saved = readTrades(),
        state = accountState(saved),
        t = review.trade;
      const fresh = quote(
        market,
        state.inventories[market.id],
        t.outcome,
        t.quantity,
        t.side,
      );
      if (
        !fresh ||
        fresh.outsideLimits ||
        Math.abs(fresh.total - review.q.total) > 0.000001 ||
        (t.side === "Buy"
          ? fresh.total > state.cash
          : t.quantity >
            (state.positions[market.id + "|" + t.outcome]?.shares || 0))
      ) {
        setTrades(saved);
        setNotice("Your paper account changed. Review the updated quote.");
        return;
      }
      const next = [...saved, t];
      saveTrades(next);
      setTrades(next);
      setTab("Positions");
      setNotice(
        "Paper fill recorded · " +
          t.quantity +
          " " +
          market.labels[t.outcome] +
          " shares " +
          (t.side === "Buy" ? "bought." : "sold."),
      );
    };
    try {
      if (navigator.locks)
        await navigator.locks.request("closari-paper-account", execute);
      else execute();
    } catch {
      setNotice("The fill could not be saved in this browser.");
    } finally {
      modal.current?.close();
      setReview(null);
      busy.current = false;
    }
  }
  return (
    <main className="terminal" style={{ "--asset": asset.color }}>
      <SessionStrip account={account} />
      <MarketRail
        listing={
          format === "Strike" && listing === "example" ? defaultLevel : listing
        }
        asset={asset}
        format={format}
        stars={stars}
        account={account}
      />
      <div className="workspace-grid">
        <div className="market-column">
          <section className="analysis-panel">
            <div className="instrument-head">
              <div className="instrument-art">
                <img src={asset.art} alt="" />
                <img
                  className="instrument-logo stock-logo"
                  src={asset.logo}
                  alt={asset.issuer}
                />
              </div>
              <div>
                <p className="eyebrow">
                  {asset.ticker} / {asset.sector}
                </p>
                <h1>{market.question}</h1>
                <button
                  className="jump-ticket"
                  onClick={() => {
                    const el = document.getElementById("paper-order");
                    el.focus({ preventScroll: true });
                    el.scrollIntoView({ block: "start" });
                  }}
                >
                  Order ticket ↓
                </button>
              </div>
              <button
                className="star-button"
                onClick={toggleStar}
                aria-label={
                  starred ? "Remove from watchlist" : "Add to watchlist"
                }
                aria-pressed={starred}
              >
                <Icon name="star" />
              </button>
            </div>
            <div className="format-bar">
              <div className="format-tabs">
                {formats.map((v) => (
                  <a
                    key={v}
                    href={marketPath(
                      contract(
                        asset,
                        v,
                        v === "Strike" ? defaultLevel : "daily",
                      ),
                    )}
                    aria-current={format === v ? "page" : undefined}
                  >
                    {v}
                  </a>
                ))}
              </div>
              <span>
                {format === "Strike"
                  ? "Token strike"
                  : format === "Range"
                    ? "Ladder reference"
                    : "Opening reference"}{" "}
                <b>{price(market.strike)}</b>
                <small>≈ {price(market.equivalent)} / share</small>
              </span>
            </div>
            {format === "Strike" && (
              <StrikeBoard market={market} account={account} />
            )}
            {market.archived && (
              <p className="archived-market">
                Earlier paper example ·{" "}
                <a
                  href={marketPath(
                    contract(
                      asset,
                      format,
                      format === "Strike" ? defaultLevel : "daily",
                    ),
                  )}
                >
                  View daily listing ↗
                </a>
              </p>
            )}
            <Chart market={market} outcome={outcome} last={prob[outcome]} />
          </section>
          <Ledger
            tab={tab}
            setTab={setTab}
            market={market}
            probs={prob}
            account={account}
            onChoose={setSelected}
            outcome={outcome}
          />
        </div>
        <div className="order-column">
          <Ticket
            market={market}
            account={account}
            outcome={outcome}
            setOutcome={setSelected}
            onReview={openReview}
            notice={notice}
          />
          <section className="session-card">
            <div className="session-card-top">
              <p className="eyebrow">
                <InstrumentIcon name="clock" size={21} />
                Session clock
              </p>
              <span>ET</span>
            </div>
            <div className="session-line">
              <i />
            </div>
            <div className="clock-points">
              <span>
                <b>09:30</b>Open
              </span>
              <span>
                <b>15:50</b>Halt
              </span>
              <span>
                <b>16:00</b>Bell
              </span>
            </div>
            <p className="settlement-caption">
              Closari uses the Pyth token-equivalent price at the bell. The
              exchange’s closing-auction print may differ.
            </p>
            <button
              className="proof-link"
              onClick={() => {
                setTab("Settlement");
                requestAnimationFrame(() =>
                  document
                    .querySelector(".ledger")
                    ?.scrollIntoView({ block: "nearest" }),
                );
              }}
            >
              Settlement details <Icon name="diagonal" size={13} />
            </button>
          </section>
        </div>
      </div>
      <div className="desk-footer">
        <span>Illustrative session · Paper cash stays in this browser</span>
        <a href="/markets">Market index ↗</a>
      </div>
      <dialog
        className="review-modal"
        ref={modal}
        onClose={() => setReview(null)}
        aria-labelledby="review-title"
      >
        {review && (
          <>
            <div className="modal-top">
              <p className="eyebrow">Order preview / Paper only</p>
              <button
                aria-label="Close review"
                onClick={() => modal.current.close()}
              >
                <Icon name="close" />
              </button>
            </div>
            <h2 id="review-title">
              {review.trade.side} {review.trade.quantity} shares
            </h2>
            <p>{market.question}</p>
            <dl className="quote-lines">
              {[
                ["Outcome", market.labels[review.trade.outcome]],
                ["Average price", money(review.q.average * 100) + "¢"],
                ["Price after order", money(review.q.priceAfter * 100) + "¢"],
                ["Fee included", money(review.q.fee) + " USDG"],
                [
                  review.trade.side === "Buy"
                    ? "Total paper cost"
                    : "Net paper proceeds",
                  money(review.q.total) + " USDG",
                ],
              ].map(([k, v]) => (
                <div key={k}>
                  <dt>{k}</dt>
                  <dd>{v}</dd>
                </div>
              ))}
            </dl>
            <p className="review-risk">
              {review.trade.side === "Buy"
                ? "A winning share pays 1 USDG. A losing share pays 0. "
                : ""}
              On a void, shares redeem at their time-weighted price and fees are
              refunded. The standard window is the final 60 minutes of trading.
              A guardian void uses the market’s full trading life.
            </p>
            <button className="ticket-cta" onClick={confirm}>
              Confirm paper {review.trade.side.toLowerCase()}
              <Icon name="check" />
            </button>
          </>
        )}
      </dialog>
    </main>
  );
}
