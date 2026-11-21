import React, { useEffect, useRef, useState } from "react";
import {
  chances,
  contract,
  marketPath,
  money,
  pctOffset,
  price,
  strikeLevels,
  universe,
} from "./markets";
import { Icon, go } from "./shared";
const listings = universe.flatMap((asset) => [
  ...strikeLevels.map((level) => contract(asset, "Strike", level)),
  contract(asset, "Range", "daily"),
  contract(asset, "Up/down", "daily"),
]);
function describe(m) {
  return m.format === "Strike"
    ? pctOffset(m.offset) + " · " + price(m.strike)
    : m.format === "Range"
      ? "Five closing ranges"
      : "Close versus open";
}
export default function MarketFinder({ account }) {
  const ref = useRef(null),
    input = useRef(null),
    list = useRef(null),
    [text, setText] = useState(""),
    [index, setIndex] = useState(0);
  const tokens = text.trim().toLowerCase().split(/\s+/);
  const matches = listings.filter((m) => {
    const key = [
      m.asset.ticker,
      m.asset.name,
      m.format,
      describe(m).replaceAll("−", "-"),
    ]
      .join(" ")
      .toLowerCase();
    return tokens.every((token) => key.includes(token.replaceAll("−", "-")));
  });
  function open() {
    if (ref.current.open || document.querySelector("dialog[open]")) return;
    setText("");
    setIndex(0);
    ref.current.showModal();
    input.current.focus();
  }
  useEffect(() => {
    const key = (e) => {
      if (
        (e.ctrlKey || e.metaKey) &&
        e.key.toLowerCase() === "k" &&
        !document.querySelector("dialog[open]")
      ) {
        e.preventDefault();
        open();
      }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, []);
  function select(m) {
    ref.current.close();
    go(marketPath(m));
  }
  function navigate(e) {
    if (e.key === "Enter" && matches[index]) {
      e.preventDefault();
      select(matches[index]);
      return;
    }
    if (
      !["ArrowDown", "ArrowUp", "Home", "End"].includes(e.key) ||
      !matches.length
    )
      return;
    e.preventDefault();
    const i =
      e.key === "Home"
        ? 0
        : e.key === "End"
          ? matches.length - 1
          : Math.max(
              0,
              Math.min(
                matches.length - 1,
                index + (e.key === "ArrowDown" ? 1 : -1),
              ),
            );
    setIndex(i);
    list.current.children[i]?.scrollIntoView({ block: "nearest" });
  }
  return (
    <>
      <button className="find-market" onClick={open}>
        <Icon name="search" size={15} />
        Find market <kbd>Ctrl / ⌘ K</kbd>
      </button>
      <dialog
        ref={ref}
        className="market-finder"
        aria-labelledby="finder-title"
        onClick={(e) => {
          if (e.target === ref.current) {
            const b = ref.current.getBoundingClientRect();
            if (
              e.clientX < b.left ||
              e.clientX > b.right ||
              e.clientY < b.top ||
              e.clientY > b.bottom
            )
              ref.current.close();
          }
        }}
      >
        <div className="finder-head">
          <h2 id="finder-title">Find a market</h2>
          <button
            onClick={() => ref.current.close()}
            aria-label="Close market finder"
          >
            <Icon name="close" size={17} />
          </button>
        </div>
        <div className="finder-input">
          <Icon name="search" size={19} />
          <input
            ref={input}
            value={text}
            onChange={(e) => {
              setText(e.target.value);
              setIndex(0);
              if (list.current) list.current.scrollTop = 0;
            }}
            onKeyDown={navigate}
            placeholder="Ticker, company, format or strike"
            aria-label="Search daily markets"
            role="combobox"
            aria-expanded="true"
            aria-controls="daily-list"
            aria-autocomplete="list"
            aria-activedescendant={
              matches[index] ? "finder-option-" + index : undefined
            }
          />
        </div>
        <div className="finder-count" role="status">
          {matches.length} of {listings.length} paper markets
        </div>
        <div
          ref={list}
          className="finder-results"
          id="daily-list"
          role="listbox"
          aria-label="Matching contracts"
        >
          {matches.map((m, i) => {
            const o = m.format === "Range" ? 2 : 0;
            const p = chances(m, account.inventories[m.id])[o];
            return (
              <button
                id={"finder-option-" + i}
                role="option"
                aria-selected={index === i}
                tabIndex={-1}
                key={m.id}
                onClick={() => select(m)}
              >
                <img src={m.asset.logo} alt="" />
                <span>
                  <b>{m.asset.ticker}</b>
                  <small>{m.asset.name}</small>
                </span>
                <span className="finder-instrument">
                  <b>{m.format}</b>
                  <small>{describe(m)}</small>
                </span>
                <span className="finder-quote">
                  {money(p * 100)}¢
                  <small>
                    {m.format === "Range" ? "Middle range" : m.labels[o]}
                  </small>
                </span>
              </button>
            );
          })}
        </div>
        {!matches.length && (
          <p className="no-matches">
            Try a ticker such as NVDA, a strike price, or “range”.
          </p>
        )}
      </dialog>
    </>
  );
}
