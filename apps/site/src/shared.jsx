import React, { useEffect, useState, useRef, useId } from "react";
import { Appearance } from "./appearance";
import FoldedMark from "./FoldedMark";
export function go(href, replace = false) {
  const url = new URL(href, location.origin);
  if (url.origin !== location.origin) return;
  if (replace) history.replaceState({}, "", url);
  else history.pushState({}, "", url);
  window.dispatchEvent(new PopStateEvent("popstate"));
}
export function useRoute() {
  function readRoute() {
    if (/^\/field\/about\/?$/.test(location.pathname))
      history.replaceState(history.state, "", "/protocol");
    return location.pathname + location.search + location.hash;
  }
  const [route, setRoute] = useState(readRoute);
  useEffect(() => {
    const change = () => setRoute(readRoute());
    function link(e) {
      const a = e.target.closest?.("a[href]");
      if (
        !a ||
        e.defaultPrevented ||
        e.button !== 0 ||
        e.altKey ||
        e.metaKey ||
        e.ctrlKey ||
        e.shiftKey ||
        a.download ||
        a.target
      )
        return;
      const url = new URL(a.href);
      if (url.origin !== location.origin || url.pathname.startsWith("/files/"))
        return;
      e.preventDefault();
      go(url.pathname + url.search + url.hash);
    }
    window.addEventListener("popstate", change);
    document.addEventListener("click", link);
    return () => {
      window.removeEventListener("popstate", change);
      document.removeEventListener("click", link);
    };
  }, []);
  return route;
}
export function Icon({ name, size = 18, ...props }) {
  const shapes = {
    arrow: "M5 12h13m-5-5 5 5-5 5",
    diagonal: "M5 19 19 5M6 5h13v13",
    chevron: "m8 10 4 4 4-4",
    close: "m6 6 12 12m0-12L6 18",
    star: "m12 3 2.8 5.6 6.2.9-4.5 4.4 1.1 6.1-5.6-2.9L6.4 20l1.1-6.1L3 9.5l6.2-.9z",
    plus: "M12 4v16M4 12h16",
    check: "m4 12 5 5L20 6",
    search: "M16 16l5 5m-3-12a7 7 0 1 1-14 0 7 7 0 0 1 14 0",
  };
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...props}
    >
      <path d={shapes[name]} />
    </svg>
  );
}
export function Cube() {
  const [paused, setPaused] = useState(
    () => matchMedia("(prefers-reduced-motion:reduce)").matches,
  );
  useEffect(() => {
    const sync = (e) => setPaused(e.detail);
    const media = matchMedia("(prefers-reduced-motion: reduce)");
    const prefer = (e) =>
      window.dispatchEvent(
        new CustomEvent("closari-motion", { detail: e.matches }),
      );
    window.addEventListener("closari-motion", sync);
    media.addEventListener("change", prefer);
    return () => {
      window.removeEventListener("closari-motion", sync);
      media.removeEventListener("change", prefer);
    };
  }, []);
  return (
    <button
      type="button"
      className={"cube-button " + (paused ? "paused" : "")}
      onClick={() => {
        setPaused(!paused);
        window.dispatchEvent(
          new CustomEvent("closari-motion", { detail: !paused }),
        );
      }}
      aria-label={paused ? "Resume gallery motion" : "Pause gallery motion"}
      aria-pressed={paused}
    >
      <FoldedMark paused={paused} />
    </button>
  );
}
export function Bracket({ href, children, className = "", ...props }) {
  return (
    <a href={href} className={"bracket " + className} {...props}>
      <span>{children}</span>
    </a>
  );
}
const pages = [
  ["Markets", "/markets"],
  ["Journal", "/journal"],
  ["Protocol", "/protocol"],
  ["Docs", "/docs"],
];
export function Header({ route }) {
  const isHome = route === "/",
    desk = route.startsWith("/terminal");
  const dialog = useRef(null),
    trigger = useRef(null);
  const [open, setOpen] = useState(false);
  function close() {
    dialog.current?.close();
    setOpen(false);
  }
  useEffect(() => {
    if (dialog.current?.open) close();
  }, [route]);
  useEffect(() => {
    if (open) {
      const old = document.body.style.overflow;
      document.body.style.overflow = "hidden";
      return () => {
        document.body.style.overflow = old;
      };
    }
  }, [open]);
  return (
    <header
      className={
        "site-head " + (isHome ? "over-home " : "") + (desk ? "desk-head" : "")
      }
    >
      <a className="wordmark" href="/" aria-label="Closari home">
        Closari
      </a>
      <div className="head-formats">
        <a href="/field/technology">Technology</a>
        <i aria-hidden="true">/</i>
        <a href="/field/faq">FAQ</a>
      </div>
      <nav aria-label="Main">
        {pages.map(([s, u], i) => (
          <a
            aria-current={route.startsWith(u) ? "page" : undefined}
            key={s}
            href={u}
          >
            {s}
            {i === 0 && <sup>12</sup>}
          </a>
        ))}
        <Bracket href="/terminal/nvda">
          Open terminal <i className="cursor-block" />
        </Bracket>
      </nav>
      <Appearance desk={desk} />
      <div className="mobile-mark">
        <Cube />
      </div>
      <button
        ref={trigger}
        aria-label="Menu"
        className="menu-toggle bracket"
        aria-expanded={open}
        onClick={() => {
          dialog.current.showModal();
          setOpen(true);
        }}
      >
        <span>Menu</span>
      </button>
      <dialog
        className="site-menu"
        ref={dialog}
        onClick={(e) => {
          if (e.target.closest("a[href]")) close();
        }}
        onClose={() => {
          setOpen(false);
          trigger.current?.focus({ preventScroll: true });
        }}
      >
        <div className="menu-top">
          <a className="wordmark" href="/">
            Closari
          </a>
          <button
            onClick={close}
            aria-label="Close menu"
            className="bracket"
            autoFocus
          >
            <span>Close</span>
          </button>
        </div>
        <nav aria-label="Mobile">
          {pages.map(([name, path], i) => (
            <a href={path} key={name}>
              <small>0{i + 1}</small>
              {name}
              <Icon name="diagonal" size={27} />
            </a>
          ))}
        </nav>
        <Bracket href="/terminal/nvda" className="menu-cta">
          Open terminal
        </Bracket>
        <div className="menu-foot">
          <span>Stock-close markets</span>
          <span>Paper session</span>
        </div>
      </dialog>
    </header>
  );
}
export function Footer() {
  return (
    <footer className="footer">
      <div className="footer-cta">
        <h2>Read the close.</h2>
        <Bracket href="/terminal/nvda">Open the paper terminal ↗</Bracket>
      </div>
      <div className="footer-cols">
        <a href="/" className="footer-logo">
          Closari
        </a>
        <div>
          <small>Explore</small>
          <a href="/markets">Market index</a>
          <a href="/journal">Journal</a>
          <a href="/protocol">Protocol</a>
        </div>
        <div>
          <small>Reference</small>
          <a href="/docs">Field guide</a>
          <a href="/field/roadmap">Roadmap</a>
          <a href="/field/faq">FAQ</a>
        </div>
        <div>
          <small>Documents</small>
          <a href="/docs/privacy">Privacy</a>
          <a href="/docs/terms">Preview terms</a>
          <a href="/docs/settlement">Settlement rules</a>
        </div>
      </div>
      <div className="footer-floor">
        <span>Closari · Design preview</span>
        <span>Sample session / USDG</span>
      </div>
    </footer>
  );
}
export function Accordion({ title, children, defaultOpen = false }) {
  const [open, setOpen] = useState(defaultOpen),
    id = useId();
  return (
    <div className={"accord " + (open ? "expanded" : "")}>
      <button
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen(!open)}
      >
        {title}
        <Icon name="plus" />
      </button>
      <div className="accord-reveal" id={id} inert={!open}>
        <div>
          <div className="accord-body">{children}</div>
        </div>
      </div>
    </div>
  );
}
