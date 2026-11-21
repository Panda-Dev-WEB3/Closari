import React, { useEffect, useRef } from "react";
import officialMark from "./folded-c.svg";
import source from "./folded-c.svg?raw";

// Use the top outline of the official SVG and the three step levels from
// its original drawing. Coordinates are width, depth and downward height.
let cachedFaces;
function model() {
  if (cachedFaces) return cachedFaces;
  const paths = new DOMParser()
    .parseFromString(source, "image/svg+xml")
    .querySelectorAll("path");
  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute("d", paths[paths.length - 1].getAttribute("d"));
  const length = path.getTotalLength();
  const outline = Array.from({ length: 160 }, (_, i) => {
    const p = path.getPointAtLength((length * i) / 160);
    return [p.x, p.y];
  });
  const faces = [];
  function slab(contour, z, bottom, top, color) {
    const ring = (h) => contour.map(([x, y]) => [x, y, h]);
    faces.push({ points: ring(z), color: top, line: true });
    faces.push({ points: ring(bottom), color: "#919ec8", line: true });
    for (let i = 0; i < contour.length; i++) {
      const a = contour[i],
        b = contour[(i + 1) % contour.length];
      faces.push({
        points: [
          [...a, z],
          [...b, z],
          [...b, bottom],
          [...a, bottom],
        ],
        color,
        line: contour.length <= 4,
      });
    }
  }
  const rectangle = (x1, y1, x2, y2) => [
    [x1, y1],
    [x2, y1],
    [x2, y2],
    [x1, y2],
  ];
  slab(outline, 0, 3, "#fff9e9", "#b2dccc");
  slab(rectangle(113, 76, 116, 100), 3, 38, "#d3ecdb", "#a8e6d4");
  slab(rectangle(17, 111, 116, 136), 19, 21.2, "#d6f5e9", "#aacfbf");
  slab(rectangle(113.5, 111, 116, 136), 21.2, 39.8, "#c5e9db", "#a8e6d4");
  slab(rectangle(18, 146, 116, 171), 38, 40.2, "#fff9e9", "#a8e6d4");
  cachedFaces = faces;
  return faces;
}
const cage = [];
for (const x of [-1, 1])
  for (const y of [-1, 1])
    for (const z of [-1, 1]) {
      const a = [x, y, z];
      for (const dimension of [0, 1, 2])
        if (a[dimension] === -1) {
          const b = [...a];
          b[dimension] = 1;
          cage.push([a, b]);
        }
    }

export default function FoldedMark({ paused }) {
  const canvas = useRef(null),
    phase = useRef(0),
    paintReady = useRef(false);
  useEffect(() => {
    const el = canvas.current,
      ctx = el.getContext("2d");
    if (!ctx) return;
    let frame = 0,
      last = 0,
      visible = false,
      light = false,
      size = 0;
    const surfaces = model();
    function render(time) {
      frame = 0;
      if (!size || !visible || document.hidden) {
        last = 0;
        return;
      }
      if (!paused && last && time - last < 32) {
        frame = requestAnimationFrame(render);
        return;
      }
      if (!paused && last)
        phase.current += (Math.min(time - last, 75) * Math.PI * 2) / 20000;
      last = time;
      const theta = Math.PI / 4 + phase.current,
        tilt = 0.57 + 0.07 * Math.sin(phase.current),
        c = Math.cos(theta),
        s = Math.sin(theta),
        h = Math.sin(tilt),
        v = Math.cos(tilt);
      const project = ([x, y, z]) => [
        x * c - y * s,
        (x * s + y * c) * h + z * v,
        (x * s + y * c) * v - z * h,
      ];
      const meshes = surfaces.map((f) => {
        const p = f.points.map(([x, y, z]) =>
          project([(x - 58) * 0.75, (y - 85) * 0.75, (z - 18) * 0.93]),
        );
        return {
          p,
          depth: p.reduce((n, v) => n + v[2], 0) / p.length,
          fill: f.color,
          line: f.line,
        };
      });
      const edges = cage.map(([a, b]) => {
        const p = [a, b].map((pt) => project(pt.map((n) => n * 76)));
        return { p, depth: (p[0][2] + p[1][2]) / 2, edge: true };
      });
      const scale = size / 257;
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, size, size);
      ctx.setTransform(scale, 0, 0, scale, size / 2, size / 2);
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      function drawFace(f) {
        ctx.beginPath();
        f.p.forEach(([x, y], i) => {
          if (i) ctx.lineTo(x, y);
          else ctx.moveTo(x, y);
        });
        if (f.edge) {
          ctx.strokeStyle =
            f.depth > 0
              ? light
                ? "#506789"
                : "#cfefe4"
              : light
                ? "#8397ab99"
                : "#9aaed68c";
          ctx.lineWidth = f.depth > 0 ? 1.32 : 0.85;
          ctx.stroke();
          return;
        }
        ctx.closePath();
        ctx.fillStyle = f.fill;
        ctx.fill();
        ctx.strokeStyle = f.line ? "#273e5b" : f.fill;
        ctx.lineWidth = f.line ? 1.05 : 0.6;
        ctx.stroke();
      }
      edges.filter((e) => e.depth < 0).forEach(drawFace);
      meshes.sort((a, b) => a.depth - b.depth).forEach(drawFace);
      edges.filter((e) => e.depth >= 0).forEach(drawFace);
      if (!paintReady.current) {
        el.dataset.ready = "true";
        paintReady.current = true;
      }
      if (!paused) frame = requestAnimationFrame(render);
    }
    function redraw() {
      cancelAnimationFrame(frame);
      last = 0;
      frame = requestAnimationFrame(render);
    }
    function resize() {
      size = Math.round(
        el.clientWidth * Math.min(window.devicePixelRatio || 1, 2),
      );
      el.width = size;
      el.height = size;
      redraw();
    }
    function theme() {
      light = document.documentElement.dataset.theme === "light";
      redraw();
    }
    const obs = new ResizeObserver(resize),
      appearance = new MutationObserver(theme),
      visibility = new IntersectionObserver(([entry]) => {
        visible = entry.isIntersecting;
        redraw();
      });
    obs.observe(el);
    visibility.observe(el);
    appearance.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    });
    document.addEventListener("visibilitychange", redraw);
    theme();
    resize();
    return () => {
      cancelAnimationFrame(frame);
      obs.disconnect();
      visibility.disconnect();
      appearance.disconnect();
      document.removeEventListener("visibilitychange", redraw);
    };
  }, [paused]);
  return (
    <span className="folded-emblem" aria-hidden="true">
      <canvas ref={canvas} />
      <img src={officialMark} alt="" />
    </span>
  );
}
