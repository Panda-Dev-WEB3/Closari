import { InstrumentIcon } from "./InstrumentIcon";
import React, { useEffect, useState } from "react";
import { universe, formats, price, contract, defaultLevel } from "./markets";
import { chapters, articles } from "./stories";
import Chapter, { Questions } from "./Chapters";
import { Icon, Bracket } from "./shared";
import "./editorial.css";
const marketURL = (a, f) =>
  "/terminal/" +
  a.ticker.toLowerCase() +
  (formats.includes(f) ? "?format=" + encodeURIComponent(f) : "");
function Markets({ route }) {
  const initial = new URL(route, location.origin).searchParams.get("format");
  const [format, setFormat] = useState(
      formats.includes(initial) ? initial : "All",
    ),
    [view, setView] = useState("Grid"),
    [search, setSearch] = useState("");
  useEffect(
    () => setFormat(formats.includes(initial) ? initial : "All"),
    [initial],
  );
  const list = universe.filter((a) =>
    [a.ticker, a.name, a.issuer, a.sector]
      .join(" ")
      .toLowerCase()
      .includes(search.trim().toLowerCase()),
  );
  return (
    <main className="inner markets-page">
      <h1>
        Markets<sup>(12)</sup>
      </h1>
      <p className="lead">
        Ninety-six daily markets on twelve stock tokens. Closari uses an oracle
        price at the bell, which can differ from the exchange’s closing print.
      </p>
      <div className="market-controls">
        <div className="filter-group" aria-label="Market format">
          {["All", ...formats].map((f) => (
            <button
              aria-label={f}
              aria-pressed={format === f}
              onClick={() => setFormat(f)}
              key={f}
            >
              {f}
            </button>
          ))}
        </div>
        <div className="market-tools">
          <label className="market-search">
            <Icon name="search" size={14} />
            <input
              type="search"
              aria-label="Find a stock token"
              placeholder="Find ticker"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </label>
          <div className="filter-group" aria-label="Index layout">
            {["Grid", "List"].map((v) => (
              <button
                aria-label={v}
                aria-pressed={view === v}
                key={v}
                onClick={() => setView(v)}
              >
                {v}
              </button>
            ))}
          </div>
        </div>
      </div>
      <div className={"market-index " + view.toLowerCase()}>
        {list.map((a) => (
          <a className="market-card" key={a.ticker} href={marketURL(a, format)}>
            <div className="market-cap">
              <span>
                {String(a.index + 1).padStart(2, "0")} <b>{a.issuer}</b>
              </span>
              <span>{a.ticker}</span>
            </div>
            <div className="market-photo">
              <img
                className="issuer-sculpture"
                src={a.sculpture}
                alt={a.issuer + " logo"}
                width={720}
                height={720}
                loading={a.index < 3 ? "eager" : "lazy"}
              />
              <span className="image-open">
                <Icon name="diagonal" />
              </span>
            </div>
            <div className="market-detail-line">
              <span>{format === "All" ? a.sector : format + " market"}</span>
              <span className="directory-strike">
                {format === "Range"
                  ? "Five intervals"
                  : format === "Up/down"
                    ? "Open / close"
                    : price(contract(a, "Strike", defaultLevel).strike) +
                      " token"}
                {(format === "All" || format === "Strike") && (
                  <small>
                    ≈ {price(contract(a, "Strike", defaultLevel).equivalent)} /
                    share
                  </small>
                )}
              </span>
            </div>
          </a>
        ))}
      </div>
      {!list.length && (
        <p className="no-results">
          No token matches “{search}”.{" "}
          <button onClick={() => setSearch("")}>Clear search</button>
        </p>
      )}
    </main>
  );
}
function Journal() {
  return (
    <main className="inner journal">
      <h1>
        Journal<sup>(06)</sup>
      </h1>
      <p className="lead">
        A closer read of the prices, rules and capital behind a daily close.
      </p>
      <div className="journal-grid">
        {articles.map((a) => (
          <a href={"/journal/" + a.slug} key={a.slug}>
            <div className="journal-cover">
              <img src={a.art} alt={a.alt} />
            </div>
            <p className="eyebrow">{a.topic} &nbsp; / &nbsp; Field note</p>
            <h2>{a.title}</h2>
            <p>{a.deck}</p>
          </a>
        ))}
      </div>
    </main>
  );
}
const notes = {
  strike: [
    [
      "One hundred Yes shares",
      "With NVIDIA Yes at 0.62 USDG, the first share is only the starting point. A 100-share buy against a 2,000 USDG budget costs about 62.41 USDG before fees.",
    ],
    [
      "Follow the fill",
      "At a 0.50% fee, the total rounds to 62.72 USDG. The market then quotes Yes at about 62.8¢. The paper terminal uses the same pricing curve.",
    ],
  ],
  range: [
    [
      "The five intervals",
      "With a $400 TSLA reference, the example edges are $392, $398, $402 and $408 per token. Each bucket includes its lower edge. The upper edge belongs to the next bucket.",
    ],
    [
      "Inside the middle bucket",
      "All five start at 20¢. Fifty shares of the $398–$402 bucket cost about 10.16 USDG before fees. A $399.40 settlement outside the confidence bands pays 50 USDG. If the price falls inside the confidence band of an edge, the ladder voids.",
    ],
  ],
  open: [
    [
      "The opening observation",
      "The proposed up/down market records a Pyth regular-session opening price for 09:30 ET. Trading pauses at the open until the reference has been recorded.",
    ],
    [
      "A missing open",
      "If no valid open is recorded by 11:30 ET, that up/down market voids. Its time-weighted redemption window ends when trading paused at the open. Other market types have their own settlement conditions.",
    ],
  ],
  oracle: [
    [
      "The primary observation",
      "The first regular-session Pyth update in the bell second is the preferred price. Closari converts it to token terms using the multiplier fixed at listing.",
    ],
    [
      "A conditional second reading",
      "A Chainlink round at most 15 minutes old can cross-check the primary observation. A divergence above 1% voids the token’s daily markets. With a stale cross-check, Pyth alone governs.",
    ],
  ],
  pool: [
    [
      "A bounded allocation",
      "A 2,000 USDG market budget sets aside up to 2,000 USDG of pool capital. On a two-outcome market, that gives a liquidity parameter of approximately 2,885 shares.",
    ],
    [
      "After the close",
      "Reserved budgets release after settlement. Free capital can support instant withdrawals before then, subject to the proposed conservative valuation and 0.25% exit fee. The pool can lose its full budget on several markets in one session.",
    ],
  ],
  access: [
    [
      "What the token is for",
      "The proposed $CLSR tiers provide higher API rate limits and access to limited later market types. Trading and exiting positions require no $CLSR.",
    ],
    [
      "How a discount applies",
      "Proposed tiers reduce the base fee by 10%, 20% or 30% after a seven-day staking warm-up. The late fee ramp still applies in full. Token supply and tier sizes remain open decisions. Holders receive no trading-fee allocation.",
    ],
  ],
};
function Article({ article }) {
  const next = articles[(articles.indexOf(article) + 1) % articles.length],
    related = chapters.find((s) => s.slug === article.chapter);
  return (
    <main className="inner article">
      <p className="eyebrow">{article.topic} / Journal</p>
      <h1>{article.title}</h1>
      <p className="lead">{article.deck}</p>
      <figure className="article-plate">
        <img className="article-cover" src={article.art} alt={article.alt} />
      </figure>
      <div className="chapter-body">
        <aside>
          <Bracket href="/journal">All notes</Bracket>
        </aside>
        <article>
          {notes[article.slug].map(([h, p]) => (
            <section className="body-section" key={h}>
              <h2>{h}</h2>
              <p>{p}</p>
            </section>
          ))}
          <Bracket href={related.href}>Field study / {related.name}</Bracket>
        </article>
      </div>
      <a href={"/journal/" + next.slug} className="next-study">
        <span className="eyebrow">Next note</span>
        <strong>{next.title}</strong>
        <Icon name="arrow" />
      </a>
    </main>
  );
}
function Protocol() {
  return (
    <main className="inner protocol">
      <p className="eyebrow">Closari / Protocol</p>
      <h1>
        A market for
        <br />
        the closing bell.
      </h1>
      <div className="protocol-leads">
        <p>
          Closari is designed for daily markets on tokenized stocks. Each one
          gives a closing price a question to answer.
        </p>
        <p>
          Take a position above a strike, inside a range, or on the move from
          the open. The proposed market maker quotes shares in USDG until the
          ten-minute halt before the bell.
        </p>
      </div>
      <figure className="hall-panorama">
        <img
          src="/edition/settlement-hall.webp"
          alt="Illustrated Closari exchange hall with a TSLA closing-range example."
        />
      </figure>
      <div className="chapter-index">
        {chapters.map((s) => (
          <a href={s.href} key={s.slug}>
            <img src={s.art} alt="" />
            <span className="eyebrow">0{s.index + 1}</span>
            <h2>{s.name}</h2>
            <p>{s.deck}</p>
            <Icon name="diagonal" />
          </a>
        ))}
      </div>
    </main>
  );
}
const documents = {
  settlement: {
    title: "Settlement rules",
    intro:
      "The proposed price path from the ten-minute halt to a resolved or void market.",
    sections: [
      [
        "Halt and observation",
        "The regular-session halt is 15:50 ET. At 16:00 ET the first Pyth regular-session update in the bell second takes priority. Fallback windows use five seconds, then sixty seconds, with a 30-minute improvement window.",
      ],
      [
        "Cross-check",
        "A fresh Chainlink round, at most fifteen minutes old, supplies a comparison. A difference over 1% voids the daily markets for that stock. If the round is stale, Pyth alone governs.",
      ],
      [
        "Confidence and corporate actions",
        "A confidence band wider than 0.5% of the token price can void the day. A strike or interval edge inside the band voids that market. Specified multiplier changes or oracle pauses can void the stock’s daily markets.",
      ],
      [
        "No observation or unscheduled closure",
        "A missing usable price by close plus two hours voids a day. A missing opening reference by 11:30 ET voids the up/down market. A guardian can void a named market before its halt after an unscheduled exchange closure.",
      ],
      [
        "Void payment",
        "The standard redemption price is time-weighted over the last sixty minutes before trading stopped, or the shorter trading life. A guardian void uses the full trading life. Each account also receives its fees paid on that market.",
      ],
    ],
  },
  fees: {
    title: "Fees & share prices",
    intro:
      "The terminal uses the proposed regular base rate for a sample session before the late ramp.",
    sections: [
      [
        "Market price and fill price",
        "Shares are quoted in USDG. The marginal price changes along the market-maker curve as shares are bought or sold. The trade review shows the average price and total fee.",
      ],
      [
        "Proposed rates",
        "The standard base fee is 0.50% of trade value on buys and sells. The proposed launch window reduces it to 0.25%. From 15:20 to 15:50 ET on a regular day, a late component rises linearly to an additional 2.50%.",
      ],
      [
        "After resolution",
        "The proposed split is 80% to the house pool, 10% to the treasury, 5% to settlement bounties and 5% to builders. Without a builder, its portion goes to the pool. A void refunds fees paid in that market.",
      ],
    ],
  },
  access: {
    title: "Access & integrations",
    intro:
      "The paper preview is a local demonstration. The live protocol and connected services are still in design.",
    sections: [
      [
        "Planned market access",
        "The design specifies geographic restrictions for the frontend, API, MCP and relayer. Production access and eligibility require a separate launch review.",
      ],
      [
        "API and agent tools",
        "The proposed API exposes markets, quotes, positions and settlement proofs. The MCP design lets an agent build an instruction, sign with its own wallet, and relay the signed trade.",
      ],
      [
        "Dependencies",
        "Production requires verified token mappings, oracle feed identifiers, usable signed Pyth updates, contract deployments and an external review. The preview reads no live prices.",
      ],
    ],
  },
  privacy: {
    title: "Preview privacy",
    intro: "Paper trades and watchlist choices are saved by this browser.",
    sections: [
      [
        "What is stored",
        "The terminal records the side, quantity, ticker, market format and outcome for each paper fill. Watchlist storage contains the chosen ticker symbols.",
      ],
      [
        "Where it stays",
        "The preview saves these entries in local storage for this site’s origin. It collects no wallet signatures or account details. Clearing site data in your browser removes the local paper history.",
      ],
      [
        "Photographs and files",
        "The site serves its fonts, editorial artwork and stock marks from the same origin.",
      ],
    ],
  },
  terms: {
    title: "Preview terms",
    intro:
      "This build demonstrates the proposed Closari interface and market mechanics.",
    sections: [
      [
        "Paper session",
        "All balances, fills, charts and positions in the terminal are illustrative. Paper USDG has no monetary value. The preview does not accept deposits or create an on-chain transaction.",
      ],
      [
        "Design status",
        "Live contracts, feeds and payment infrastructure are pending. Proposed market parameters can change after validation. No external security review of the protocol has been completed.",
      ],
      [
        "Names and marks",
        "Company and fund names identify the underlying assets. The editorial photographs are original visual studies. No affiliation or endorsement by the issuers, chain, or oracle providers is represented.",
      ],
    ],
  },
};
function Docs({ slug }) {
  const d = documents[slug];
  if (d)
    return (
      <main className="inner docs-detail">
        <Bracket href="/docs">Field guide</Bracket>
        <h1>{d.title}</h1>
        <p className="lead">{d.intro}</p>
        <div className="doc-sections">
          {d.sections.map(([h, p]) => (
            <section className="body-section" key={h}>
              <h2>{h}</h2>
              <p>{p}</p>
            </section>
          ))}
        </div>
      </main>
    );
  return (
    <main className="inner docs-index">
      <p className="eyebrow">Documentation / Design preview</p>
      <h1>The field guide.</h1>
      <p className="lead">
        Read the rule behind a quote, a fee or a closing price.
      </p>
      <div className="doc-links">
        {Object.entries(documents).map(([key, d]) => (
          <a key={key} href={"/docs/" + key}>
            <InstrumentIcon name={key} />
            <h2>{d.title}</h2>
            <p>{d.intro}</p>
            <Icon name="diagonal" />
          </a>
        ))}
      </div>
      <h2 className="faq-head">Frequently asked questions</h2>
      <Questions />
    </main>
  );
}
export default function Editorial({ route }) {
  const path = new URL(route, location.origin).pathname,
    [, section, slug] = path.split("/");
  if (section === "markets") return <Markets route={route} />;
  if (section === "field") {
    const story = chapters.find((s) => s.slug === slug);
    if (story) return <Chapter key={slug} story={story} />;
  }
  if (section === "journal") {
    const article = articles.find((a) => a.slug === slug);
    if (article) return <Article article={article} />;
    if (!slug) return <Journal />;
  }
  if (section === "protocol" && location.hash === "#roadmap")
    return (
      <Chapter
        key="roadmap"
        story={chapters.find((s) => s.slug === "roadmap")}
      />
    );
  if (section === "protocol") return <Protocol />;
  if (section === "docs" && (!slug || documents[slug]))
    return <Docs slug={slug} />;
  return (
    <main className="inner">
      <h1>Page unavailable.</h1>
      <p className="lead">
        Return to the field studies or open the market index.
      </p>
      <Bracket href="/">Back to Closari</Bracket>
    </main>
  );
}
