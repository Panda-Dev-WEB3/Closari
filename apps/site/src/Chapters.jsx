import { InstrumentIcon } from "./InstrumentIcon";
import React, { useId, useState } from "react";
import { chapters, faq, roadmap } from "./stories";
import { Accordion, Bracket, Icon } from "./shared";
import { universe, contract, quote, money } from "./markets";
const folio = (n) => String(n).padStart(2, "0");
export function Questions() {
  const [query, setQuery] = useState("");
  const answers = faq.filter(([q, a]) =>
    (q + " " + a).toLowerCase().includes(query.trim().toLowerCase()),
  );
  return (
    <section className="questions" id="faq">
      <label className="search-field">
        <Icon name="search" />
        <input
          type="search"
          value={query}
          placeholder="Search questions"
          aria-label="Search questions"
          onChange={(e) => setQuery(e.target.value)}
        />
      </label>
      {[...new Set(answers.map(([, , group]) => group))].map((group) => (
        <section className="question-group" key={group}>
          <h3>{group}</h3>
          {answers
            .filter(([, , category]) => category === group)
            .map(([q, a]) => (
              <Accordion key={q} title={q}>
                <p>{a}</p>
              </Accordion>
            ))}
        </section>
      ))}
      {!answers.length && (
        <p className="no-results">
          No questions match “{query}”.{" "}
          <button onClick={() => setQuery("")}>Clear search</button>
        </p>
      )}
    </section>
  );
}
export function Roadmap() {
  const [phase, setPhase] = useState(0),
    current = roadmap[phase];
  return (
    <section className="milestones" id="roadmap">
      <div className="phase-index" aria-label="Engineering milestones">
        {roadmap.map(([id, name], i) => (
          <button
            key={id}
            onClick={() => setPhase(i)}
            aria-pressed={phase === i}
          >
            <small>{id}</small>
            {name}
            <span>↗</span>
          </button>
        ))}
      </div>
      <div className="phase-content" key={phase}>
        <p className="eyebrow">{current[0]} / Planned</p>
        <h3>{current[1]}</h3>
        <p>{current[2]}</p>
        <small>How we’ll test it</small>
        <p>{current[3]}</p>
        <button
          className="bracket"
          onClick={() => setPhase((phase + 1) % roadmap.length)}
        >
          <span>
            {phase === roadmap.length - 1 ? "Back to M1" : "Next milestone"} →
          </span>
        </button>
      </div>
    </section>
  );
}
const examples = ["$190.00", "5 intervals", "09:30 ET"];
const labels = ["Strike", "Range", "Up/down"];
function Study({ story }) {
  const [setting, setSetting] = useState(0),
    [quantity, setQuantity] = useState(100);
  const q = quote(contract(universe[0], "Strike"), [], 0, quantity, "Buy"),
    id = useId();
  const headline = (
    <div className="sheet-head">
      <span className="sheet-identity">
        <InstrumentIcon name={story.slug} size={22} />
        Closari / Field notes
      </span>
      <span>
        {folio(story.index + 1)} / {folio(chapters.length)}
      </span>
    </div>
  );
  let content;
  switch (story.slug) {
    case "technology": {
      const b = 2000 / Math.log(2),
        chance = (n) => 1 / (1 + (1 / 0.62 - 1) * Math.exp(-n / b));
      const px = (n) => 6 + (n / 300) * 264,
        py = (n) => 82 - (chance(n) - 0.62) * 2900;
      const line = Array.from(
        { length: 61 },
        (_, i) => (i ? "L" : "M") + px(i * 5) + " " + py(i * 5),
      ).join(" ");
      content = (
        <>
          <span className="sheet-kicker">
            NVDA Yes · Price after your order
          </span>
          <strong className="sheet-number">
            {(chance(quantity) * 100).toFixed(2)}
            <small>¢</small>
          </strong>
          <svg
            viewBox="0 0 276 92"
            className="curve-study"
            aria-label="Marginal share price rises with the size of a buy"
            role="img"
          >
            <path d="M6 8V83H271" stroke="#9f9c92" fill="none" />
            <path d={line} stroke="#494b3e" strokeWidth="2" fill="none" />
            <line
              x1={px(quantity)}
              x2={px(quantity)}
              y1={py(quantity)}
              y2="82"
              stroke="#77796c"
              strokeDasharray="2 3"
            />
            <circle cx={px(quantity)} cy={py(quantity)} r="4" fill="#282e27" />
          </svg>
          <label className="sheet-control" htmlFor={id}>
            Shares added <b>{quantity}</b>
          </label>
          <input
            id={id}
            aria-label="Shares added to the inventory curve"
            type="range"
            min="1"
            max="300"
            value={quantity}
            onChange={(e) => setQuantity(Number(e.target.value))}
          />
        </>
      );
      break;
    }
    case "case-study":
      content = (
        <>
          <span className="sheet-kicker">NVDA · Yes / $190 strike</span>
          <strong className="sheet-number">
            {money(q.total)}
            <small> USDG</small>
          </strong>
          <div className="sheet-rule" />
          <div className="sheet-row">
            <span>Share cost</span>
            <b>{money(q.value)}</b>
          </div>
          <div className="sheet-row">
            <span>Proposed fee · 0.50%</span>
            <b>{money(q.fee)}</b>
          </div>
          <label className="sheet-control" htmlFor={id}>
            Order size <b>{quantity} shares</b>
          </label>
          <input
            id={id}
            type="range"
            min="1"
            max="300"
            value={quantity}
            onChange={(e) => setQuantity(Number(e.target.value))}
          />
        </>
      );
      break;
    case "how-it-works":
      content = (
        <>
          <span className="sheet-kicker">
            {labels[setting]} / Sample reference
          </span>
          <strong className="sheet-number">{examples[setting]}</strong>
          <div className="sheet-rule" />
          <p>
            {
              [
                "Does NVIDIA finish above the token strike?",
                "Which TSLA interval contains the closing price?",
                "Does SPY finish above its opening reference?",
              ][setting]
            }
          </p>
          <div className="sheet-choices">
            {labels.map((s, i) => (
              <button
                key={s}
                aria-pressed={setting === i}
                onClick={() => setSetting(i)}
              >
                {s}
              </button>
            ))}
          </div>
        </>
      );
      break;
    case "settlement":
      content = (
        <>
          <span className="sheet-kicker">Regular session / ET</span>
          <strong className="sheet-number">
            {["15:50", "16:00", "18:00"][setting]}
          </strong>
          <div className="sheet-rule" />
          <p>
            {
              [
                "Buying and selling halt. The market keeps its reserved budget.",
                "The first Pyth regular-session update in the bell second takes priority.",
                "If a stock still has no usable submitted price, its markets void for the day.",
              ][setting]
            }
          </p>
          <div className="sheet-choices">
            {["Halt", "Bell", "Deadline"].map((s, i) => (
              <button
                key={s}
                aria-pressed={setting === i}
                onClick={() => setSetting(i)}
              >
                {s}
              </button>
            ))}
          </div>
        </>
      );
      break;
    case "liquidity": {
      const cap = setting === 0 ? 40 : 0.75;
      content = (
        <>
          <span className="sheet-kicker">Proposed pool limit</span>
          <strong className="sheet-number">
            {cap}
            <small>%</small>
          </strong>
          <div className="reserve-scale" aria-hidden="true">
            <i style={{ width: cap + "%" }} />
          </div>
          <p>
            {setting === 0
              ? "A pool worth 100,000 USDG could reserve up to 40,000 USDG across all its open markets."
              : "In that same 100,000 USDG pool, one market could receive up to 750 USDG."}
          </p>
          <div className="sheet-choices">
            {["All open markets", "One market"].map((name, i) => (
              <button
                key={name}
                aria-pressed={setting === i}
                onClick={() => setSetting(i)}
              >
                {name}
              </button>
            ))}
          </div>
        </>
      );
      break;
    }
    case "faq":
      content = (
        <>
          <span className="sheet-kicker">From the reference file</span>
          <strong className="sheet-word">Q / A</strong>
          <div className="sheet-rule" />
          <p>
            Looking for a fill, a fee or a payout rule? Search the desk guide by
            the words on your ticket.
          </p>
          <Bracket href="#faq">Read the answers ↓</Bracket>
        </>
      );
      break;
    default:
      content = (
        <>
          <span className="sheet-kicker">Engineering milestones</span>
          <strong className="sheet-word">M1–M8</strong>
          <div className="sheet-rule" />
          <p>
            Follow the build from the first eligible listing to a full
            trading-day rehearsal.
          </p>
          <Bracket href="#roadmap">Explore the plan ↓</Bracket>
        </>
      );
  }
  return (
    <div className="study-plate">
      <div className="paper-study">
        {headline}
        <div className="sheet-content">{content}</div>
        <div className="sheet-end">
          <span>{story.tag}</span>
          <i />
        </div>
      </div>
    </div>
  );
}
export default function Chapter({ story }) {
  const next = chapters[(story.index + 1) % chapters.length];
  const destinations = story.notes.length
    ? story.notes.map(([label, title], i) => [
        story.slug === "case-study" ? title : label,
        "#reading-" + (i + 1),
      ])
    : [
        [
          story.slug === "faq" ? "Find a question" : "Explore the milestones",
          "#" + story.slug,
        ],
      ];
  return (
    <main className={"inner chapter-page chapter-" + story.slug}>
      <div className="folio-bar">
        <a href="/protocol">← Field studies</a>
        <span>
          {folio(story.index + 1)} / {folio(chapters.length)}
        </span>
      </div>
      <div className="chapter-opening">
        <h1>{story.name}</h1>
        <p>{story.deck}</p>
      </div>
      <div className="chapter-pair">
        <figure className="chapter-art">
          <img src={story.art} alt={story.alt} />
        </figure>
        <Study story={story} />
      </div>
      <div className="chapter-body">
        <aside className="study-meta reading-index">
          <InstrumentIcon name={story.slug} size={42} />
          <p className="eyebrow">In this study</p>
          <nav aria-label="In this study">
            {destinations.map(([label, href]) => (
              <a key={href} href={href}>
                {label}
                <span aria-hidden="true">↓</span>
              </a>
            ))}
          </nav>
        </aside>
        <article>
          <h2>{story.heading}</h2>
          <p className="body-lead">{story.intro}</p>
          {story.notes.length > 0 && (
            <div className="reading-notes">
              {story.notes.map(([label, title, body], i) => (
                <section
                  id={"reading-" + (i + 1)}
                  className="reading-note"
                  key={title}
                >
                  <span className="note-label">{label}</span>
                  <div>
                    <h3>{title}</h3>
                    <p>{body}</p>
                  </div>
                </section>
              ))}
            </div>
          )}
          {story.closing && <p className="pool-risk">{story.closing}</p>}
          {story.slug === "faq" && <Questions />}
          {story.slug === "roadmap" && <Roadmap />}
          <Bracket href={story.link[1]}>{story.link[0]} ↗</Bracket>
        </article>
      </div>
      <a href={next.href} className="next-study">
        <img
          className="next-exhibit"
          src={next.bannerIcon}
          alt=""
          width="76"
          height="76"
          loading="lazy"
        />
        <span className="eyebrow">
          Next field study · {folio(next.index + 1)}
        </span>
        <strong>{next.name}</strong>
        <Icon name="arrow" size={37} />
      </a>
    </main>
  );
}
