import React, { useEffect, useId, useMemo, useRef, useState } from "react";
import { historyPoints } from "./markets";
const left = 6,
  top = 14,
  bottom = 24;
function clock(minutes) {
  return Math.floor(minutes / 60) + ":" + String(minutes % 60).padStart(2, "0");
}
export default function Chart({ market, outcome, last }) {
  const [period, setPeriod] = useState("Day"),
    [at, setAt] = useState(null);
  const id = useId().replaceAll(":", ""),
    svg = useRef(null);
  const [box, setBox] = useState({ width: 780, height: 220 });
  useEffect(() => {
    const observer = new ResizeObserver(([entry]) =>
      setBox({
        width: entry.contentRect.width,
        height: entry.contentRect.height,
      }),
    );
    observer.observe(svg.current);
    return () => observer.disconnect();
  }, []);
  const W = Math.max(220, box.width),
    H = Math.max(125, box.height),
    right = W < 400 ? 39 : 48;
  const points = useMemo(
    () =>
      historyPoints(
        market.asset,
        market.format,
        outcome,
        period,
        last,
        market.listing,
      ),
    [market, outcome, period, last],
  );
  useEffect(() => setAt(null), [market.id, outcome, period, last]);
  const lo = Math.max(0, Math.floor((Math.min(...points) - 0.018) * 20) / 20),
    hi = Math.min(1, Math.ceil((Math.max(...points) + 0.018) * 20) / 20);
  const loPoint = Math.min(...points),
    hiPoint = Math.max(...points);
  const x = (i) => left + (i / (points.length - 1)) * (W - left - right),
    y = (p) => top + ((hi - p) / (hi - lo)) * (H - top - bottom);
  const line = points
    .map((p, i) => (i ? "L" : "M") + x(i).toFixed(2) + " " + y(p).toFixed(2))
    .join(" ");
  const active =
      at === null ? points.length - 1 : Math.min(at, points.length - 1),
    isScrub = at !== null;
  const start = period === "1H" ? 822 : period === "3H" ? 702 : 570,
    end = 882;
  function scrub(e) {
    const box = svg.current.getBoundingClientRect(),
      v = ((e.clientX - box.left) / box.width) * W;
    setAt(
      Math.max(
        0,
        Math.min(
          points.length - 1,
          Math.round(((v - left) / (W - left - right)) * (points.length - 1)),
        ),
      ),
    );
  }
  return (
    <div className="prob-chart">
      <div className="chart-toolbar">
        <div>
          <p className="eyebrow">{market.labels[outcome]} · Implied chance</p>
          <div className="big-chance">
            {(points[active] * 100).toFixed(1)}
            <span>%</span>
            <small>
              {isScrub
                ? clock(
                    Math.round(
                      start + ((end - start) * active) / (points.length - 1),
                    ),
                  ) + " ET"
                : "Paper quote"}
            </small>
          </div>
        </div>
        <div className="periods" aria-label="Chart interval">
          {["1H", "3H", "Day"].map((v) => (
            <button
              key={v}
              aria-pressed={period === v}
              onClick={() => setPeriod(v)}
            >
              {v}
            </button>
          ))}
        </div>
      </div>
      <svg
        ref={svg}
        className="plot"
        viewBox={"0 0 " + W + " " + H}
        preserveAspectRatio="none"
        role="slider"
        aria-label="Explore sample probability history"
        tabIndex={0}
        aria-valuemin={0}
        aria-valuemax={points.length - 1}
        aria-valuenow={active}
        aria-valuetext={
          clock(
            Math.round(start + ((end - start) * active) / (points.length - 1)),
          ) +
          " Eastern, " +
          (points[active] * 100).toFixed(1) +
          " percent"
        }
        onPointerMove={scrub}
        onPointerDown={scrub}
        onPointerLeave={() => setAt(null)}
        onBlur={() => setAt(null)}
        onKeyDown={(e) => {
          if (
            ["ArrowLeft", "ArrowRight", "Home", "End", "Escape"].includes(e.key)
          ) {
            e.preventDefault();
            setAt(
              e.key === "Escape"
                ? null
                : e.key === "Home"
                  ? 0
                  : e.key === "End"
                    ? points.length - 1
                    : Math.max(
                        0,
                        Math.min(
                          points.length - 1,
                          active + (e.key === "ArrowLeft" ? -1 : 1),
                        ),
                      ),
            );
          }
        }}
      >
        <defs>
          <linearGradient id={id + "-ink"} x1="0%" y1="0%" x2="100%" y2="0%">
            <stop stopColor="var(--lavender)" offset="0%" />
            <stop stopColor="var(--chart)" offset="68%" />
          </linearGradient>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="var(--chart)" stopOpacity=".24" />
            <stop offset="1" stopColor="var(--chart)" stopOpacity=".00" />
          </linearGradient>
        </defs>
        {[0, 0.25, 0.5, 0.75, 1].map((fraction, i) => {
          const val = lo + (hi - lo) * fraction;
          return (
            <g key={i}>
              <line
                x1={left}
                x2={W - right + 3}
                y1={y(val)}
                y2={y(val)}
                className="grid-line"
              />
              <text x={W - right + 8} y={y(val) + 4}>
                {Number((val * 100).toFixed(1))}%
              </text>
            </g>
          );
        })}
        <path
          d={
            line +
            " L" +
            x(points.length - 1) +
            " " +
            (H - bottom) +
            " L" +
            left +
            " " +
            (H - bottom) +
            " Z"
          }
          fill={"url(#" + id + ")"}
        />
        <path
          d={line}
          stroke={"url(#" + id + "-ink)"}
          strokeWidth="2.45"
          fill="none"
          strokeLinejoin="round"
          vectorEffect="non-scaling-stroke"
        />
        {isScrub && (
          <line
            x1={x(active)}
            x2={x(active)}
            y1={top}
            y2={H - bottom}
            stroke="#a5a5a8"
            strokeDasharray="3 4"
          />
        )}
        <circle
          cx={x(active)}
          cy={y(points[active])}
          r="7.5"
          fill="var(--chart)"
          opacity=".16"
        />
        <circle
          cx={x(active)}
          cy={y(points[active])}
          r="3"
          fill="var(--chart)"
        />
        {[0, 0.25, 0.5, 0.75, 1].map((v, i) => (
          <text
            key={i}
            x={left + (W - left - right) * v}
            y={H - 3}
            textAnchor={i === 0 ? "start" : i === 4 ? "end" : "middle"}
          >
            {clock(Math.round(start + (end - start) * v))}
          </text>
        ))}
      </svg>
      <p className="chart-caption">
        <span>Illustrative path · ET</span>
        <span className="plot-range">
          Low {(loPoint * 100).toFixed(1)}% <i /> High{" "}
          {(hiPoint * 100).toFixed(1)}%
        </span>
      </p>
    </div>
  );
}
