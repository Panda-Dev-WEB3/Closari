import React from "react";

const drawing = {
  technology: (
    <>
      <path fill="var(--icon-fill)" d="M4 6h23v18H4z" />
      <path d="M7 9h17v10H7zM9 15h3l2-3 3 5 2-3h3M10 27h12" />
    </>
  ),
  "how-it-works": (
    <>
      <path
        fill="var(--icon-fill)"
        d="M3 18h7v8H3zM13 12h7v14h-7zM23 6h6v20h-6z"
      />
      <path d="M4 11 16 6m-4-2 4 2-2 4" />
    </>
  ),
  "case-study": (
    <>
      <path fill="var(--icon-fill)" d="M3 9h10l3 3h12v13H3z" />
      <path d="M7 9V5h18v7M8 21l4-4 4 2 5-5" />
    </>
  ),
  settlement: (
    <>
      <path fill="var(--icon-fill)" d="M5 21h22l-4-5c0-6-3-9-7-9s-7 3-7 9z" />
      <path d="M4 24h24M13 26c1 3 5 3 6 0M15 4h2" />
    </>
  ),
  liquidity: (
    <>
      <path fill="var(--icon-fill)" d="M7 6h18v15c0 5-4 7-9 7s-9-2-9-7z" />
      <path d="M7 15c5-4 12 4 18 0M7 9c6 3 12 3 18 0M20 18h4m-4 4h4" />
    </>
  ),
  faq: (
    <>
      <path fill="var(--icon-fill)" d="M4 6h24v16H15l-7 6v-6H4z" />
      <path d="M13 12c0-4 8-4 8 0 0 3-4 3-4 6m0 2v.5" />
    </>
  ),
  roadmap: (
    <>
      <path fill="var(--icon-fill)" d="m3 8 8-3 9 4 9-4v20l-9 3-9-4-8 4z" />
      <path d="M11 5v19m9-15v19m-14-9 7-5 5 3 8-6" />
    </>
  ),
  fees: (
    <>
      <path fill="var(--icon-fill)" d="M7 4h18v24l-3-2-3 2-3-2-3 2-3-2-3 2z" />
      <path d="M11 10h10m-10 4h8m-8 5h4m4 0h2" />
    </>
  ),
  access: (
    <>
      <path fill="var(--icon-fill)" d="m3 11 22-5 4 16-22 5z" />
      <circle cx="11" cy="16" r="2" />
      <path d="m15 15 7-2m-6 6 6-2" />
    </>
  ),
  privacy: (
    <>
      <path
        fill="var(--icon-fill)"
        d="m16 3 11 4v9c0 6-7 11-11 13C12 27 5 22 5 16V7z"
      />
      <path d="m10 16 4 4 8-9" />
    </>
  ),
  terms: (
    <>
      <path fill="var(--icon-fill)" d="M7 3h13l6 6v20H7z" />
      <path d="M20 4v6h6M11 15h11m-11 4h11m-11 4h7" />
    </>
  ),
  clock: (
    <>
      <circle cx="16" cy="16" r="12" fill="var(--icon-fill)" />
      <path d="M16 7v9l6 3M6 16h2m16 0h2m-10 8v2" />
    </>
  ),
  ticket: (
    <>
      <path
        fill="var(--icon-fill)"
        d="M4 8h24v5c-4 0-4 6 0 6v5H4v-5c4 0 4-6 0-6z"
      />
      <path d="M19 9v3m0 2v3m0 2v3M8 11h7m-7 10h7" />
    </>
  ),
};
export function InstrumentIcon({ name, size = 30, className = "" }) {
  return (
    <svg
      className={"instrument-icon " + className}
      width={size}
      height={size}
      viewBox="0 0 32 32"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {drawing[name]}
    </svg>
  );
}
