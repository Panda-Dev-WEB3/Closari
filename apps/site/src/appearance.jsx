import React, { useLayoutEffect, useState } from "react";

function readTheme() {
  return document.documentElement.dataset.theme === "light" ? "light" : "dark";
}
function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  document
    .querySelector('meta[name="theme-color"]')
    ?.setAttribute("content", theme === "light" ? "#fafafa" : "#111b32");
}
export function Appearance({ desk }) {
  const key = "closari.appearance." + (desk ? "desk" : "site");
  const fallback = desk ? "light" : "dark";
  const [theme, setTheme] = useState(readTheme);
  useLayoutEffect(() => {
    function sync() {
      let next = fallback;
      try {
        const saved = localStorage.getItem(key);
        if (saved === "light" || saved === "dark") next = saved;
      } catch {}
      applyTheme(next);
      setTheme(next);
    }
    sync();
    function onStorage(event) {
      if (event.key === key || event.key === null) sync();
    }
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, [key, fallback]);
  const light = theme === "light";
  function toggle() {
    const next = light ? "dark" : "light";
    applyTheme(next);
    setTheme(next);
    try {
      localStorage.setItem(key, next);
    } catch {}
  }
  return (
    <button
      type="button"
      className="appearance-switch"
      onClick={toggle}
      role="switch"
      aria-label="White theme"
      aria-checked={light}
      title={light ? "Switch to dark theme" : "Switch to white theme"}
    >
      <span className={!light ? "current" : ""}>
        <svg viewBox="0 0 20 20" aria-hidden="true">
          <path d="M14.5 13.7A6.9 6.9 0 0 1 6.4 4.9a6.8 6.8 0 1 0 8.1 8.8Z" />
        </svg>
      </span>
      <span className={light ? "current" : ""}>
        <svg viewBox="0 0 20 20" aria-hidden="true">
          <circle cx="10" cy="10" r="3.3" />
          <path d="M10 1.8v2m0 12.4v2m8.2-8.2h-2m-12.4 0h-2m14-5.8-1.4 1.4m-8.8 8.8-1.4 1.4m11.6 0-1.4-1.4M5.6 5.6 4.2 4.2" />
        </svg>
      </span>
    </button>
  );
}
