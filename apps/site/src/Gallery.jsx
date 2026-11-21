import React, { useEffect, useRef, useState } from "react";
import { chapters as featured } from "./stories";
import { Cube, go } from "./shared";

const wrap = (n, count = featured.length) => ((n % count) + count) % count;
const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
const fmt = (index) => String(index + 1).padStart(2, "0");
function cardFace(asset, image, size, ratio) {
  const card = document.createElement("canvas");
  card.width = card.height = Math.ceil(size * ratio);
  const ctx = card.getContext("2d");
  ctx.scale(card.width / size, card.height / size);
  const ink = "#243a50";
  const dark = document.documentElement.dataset.theme !== "light";
  const face = size - 8;
  function panel(x, y, side, radius, color) {
    ctx.beginPath();
    ctx.roundRect(x, y, side, side, radius);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.strokeStyle = ink;
    ctx.lineWidth = 1;
    ctx.stroke();
  }
  panel(6, 7, face, 9, dark ? "#435771" : "#8193aa");
  panel(4, 4.5, face, 9, "#c1cedb");
  panel(1.5, 1.5, face, 9, "#f4f5e9");
  const inset = 5,
    windowSize = face - 7;
  ctx.save();
  ctx.beginPath();
  ctx.roundRect(inset, inset, windowSize, windowSize, 6);
  ctx.clip();
  if (image?.complete && image.naturalWidth)
    ctx.drawImage(image, inset, inset, windowSize, windowSize);
  ctx.restore();
  ctx.font = "600 " + clamp(size * 0.042, 9, 13) + 'px "Geist Mono", monospace';
  ctx.fillStyle = ink;
  ctx.textBaseline = "middle";
  const margin = Math.max(12, size * 0.055);
  ctx.fillText(asset.name.toUpperCase(), margin, margin + 2);
  ctx.font = "500 " + clamp(size * 0.038, 9, 11) + 'px "Geist Mono", monospace';
  ctx.textAlign = "right";
  ctx.fillStyle = "#4e6572";
  ctx.fillText(fmt(asset.index), face - margin + 2, margin + 2);
  return card;
}
export default function Gallery() {
  const canvasRef = useRef(null),
    cursor = useRef(null),
    control = useRef(null),
    actions = useRef({});
  const [selected, setSelected] = useState(0),
    [ready, setReady] = useState(false);
  const railPointer = useRef(null);
  function scrubTrack(e) {
    const box = e.currentTarget.getBoundingClientRect(),
      vertical = box.height > box.width;
    const where = vertical
      ? (e.clientY - box.y) / box.height
      : (e.clientX - box.x) / box.width;
    actions.current.select?.(
      clamp(Math.floor(where * featured.length), 0, featured.length - 1),
    );
  }
  useEffect(() => {
    const canvas = canvasRef.current,
      ctx = canvas.getContext("2d", { alpha: true }),
      images = featured.map((a) => {
        const im = new Image();
        im.src = a.bannerIcon;
        return im;
      });
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    let width = 0,
      height = 0,
      size = 0,
      gap = 0,
      step = 0,
      vertical = false,
      dpr = 1,
      atlas = [],
      current = 0,
      target = 0,
      frame = 0,
      prevTime = 0;
    let hover = null,
      down = null,
      dragging = false,
      active = 0,
      alive = true,
      wheelTimer,
      resizeTimer,
      hitRegions = [];
    let lastInput = performance.now(),
      lastDrift = 0,
      motionPaused = motion.matches;
    function curvature(t) {
      const u = clamp((Math.abs(t) - 0.58) / 0.42, 0, 1);
      return u * u * (3 - 2 * u) * Math.sign(t);
    }
    function paint() {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, height);
      const cy = height * (vertical ? 0.506 : 0.452),
        cx = width / 2;
      hitRegions = [];
      const span = vertical ? height : width;
      const radius = Math.ceil(span / (2 * step)) + 1;
      for (
        let k = Math.floor(current) - radius;
        k <= Math.ceil(current) + radius;
        k++
      ) {
        const i = wrap(k),
          distance = (k - current) * step;
        const curve = curvature(distance / (span * 0.5));
        const x =
          cx -
          size * 0.5 +
          (vertical ? curve * Math.min(width * 0.065, 26) : distance);
        const y =
          cy -
          size * 0.5 +
          (vertical ? distance : -curve * Math.min(height * 0.063, 56));
        if (x + size <= 0 || x >= width || y + size <= 0 || y >= height)
          continue;
        // The path bends at the edges. Every card keeps its square face and its hit area.
        ctx.drawImage(atlas[i], x, y, size, size);
        hitRegions.push({ x, y, i, k });
      }
      const next = wrap(Math.round(current));
      if (active !== next) {
        active = next;
        setSelected(next);
      }
      if (control.current)
        control.current.style.setProperty(
          "--fraction",
          String(wrap(current) / featured.length),
        );
    }
    function animate(time) {
      frame = 0;
      const delta = target - current;
      const elapsed = clamp(time - (prevTime || time - 16), 1, 50);
      prevTime = time;
      current =
        motion.matches || Math.abs(delta) < 0.0005
          ? target
          : current + delta * (1 - Math.exp(-elapsed / (dragging ? 25 : 100)));
      paint();
      if (current !== target) frame = requestAnimationFrame(animate);
    }
    function kick() {
      if (!frame) {
        prevTime = 0;
        frame = requestAnimationFrame(animate);
      }
    }
    function resize() {
      width = canvas.clientWidth;
      height = canvas.clientHeight;
      vertical = width < 810;
      size = vertical
        ? Math.min(width * 0.636, height * 0.37)
        : Math.min(width * 0.19, height * 0.52);
      gap = vertical
        ? clamp(height * 0.024, 13, 22)
        : Math.max(10, width * 0.01);
      step = size + gap;
      dpr = Math.min(devicePixelRatio || 1, 2);
      canvas.width = width * dpr;
      canvas.height = height * dpr;
      atlas = featured.map((a, i) => cardFace(a, images[i], size, dpr));
      paint();
      setReady(true);
    }
    function hit(x, y) {
      return hitRegions.find(
        (r) => x >= r.x && x <= r.x + size && y >= r.y && y <= r.y + size,
      );
    }
    function cursorOff() {
      hover = null;
      if (cursor.current) cursor.current.dataset.show = "false";
      canvas.style.cursor = "grab";
    }
    function move(e) {
      if (down) {
        const distance = vertical ? e.clientY - down.y : e.clientX - down.x;
        if (Math.abs(distance) > 5) dragging = true;
        if (dragging) {
          target = down.start - distance / step;
          kick();
          cursorOff();
          canvas.style.cursor = "grabbing";
        }
        return;
      }
      hover = hit(e.clientX, e.clientY);
      if (hover && e.pointerType === "mouse" && cursor.current) {
        canvas.style.cursor = "none";
        cursor.current.style.transform =
          "translate3d(" + e.clientX + "px," + e.clientY + "px,0)";
        cursor.current.dataset.show = "true";
      } else cursorOff();
    }
    function start(e) {
      if (e.button !== 0) return;
      lastInput = performance.now();
      clearTimeout(wheelTimer);
      down = { x: e.clientX, y: e.clientY, start: current };
      dragging = false;
      canvas.setPointerCapture(e.pointerId);
    }
    function release(e) {
      if (!down) return;
      const wasDrag = dragging;
      down = null;
      dragging = false;
      if (wasDrag) {
        target = Math.round(target);
        kick();
      } else {
        const at = hit(e.clientX, e.clientY);
        if (at) go(featured[at.i].href);
      }
      cursorOff();
    }
    function cancel() {
      down = null;
      dragging = false;
      target = Math.round(target);
      kick();
      cursorOff();
    }
    function stepBy(n) {
      lastInput = performance.now();
      clearTimeout(wheelTimer);
      target = Math.round(target) + n;
      kick();
      cursorOff();
    }
    function wheel(e) {
      e.preventDefault();
      lastInput = performance.now();
      cursorOff();
      const change =
        Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
      target += clamp((change * (e.deltaMode === 1 ? 16 : 1)) / step, -2, 2);
      kick();
      clearTimeout(wheelTimer);
      wheelTimer = setTimeout(() => {
        target = Math.round(target);
        kick();
      }, 130);
    }
    function key(e) {
      if (
        document.querySelector(".site-menu[open]") ||
        e.altKey ||
        e.ctrlKey ||
        e.metaKey
      )
        return;
      if (["ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp"].includes(e.key)) {
        e.preventDefault();
        stepBy(["ArrowRight", "ArrowDown"].includes(e.key) ? 1 : -1);
      }
      if (e.key === "Enter" && document.activeElement === canvas) {
        e.preventDefault();
        go(featured[wrap(Math.round(target))].href);
      }
    }
    actions.current = {
      select: (i) => {
        lastInput = performance.now();
        const rem = wrap(Math.round(target)),
          half = Math.floor(featured.length / 2),
          dist = wrap(i - rem + half) - half;
        target = Math.round(target) + dist;
        kick();
      },
    };
    const pause = (e) => {
      motionPaused = e.detail;
      lastInput = performance.now();
    };
    const drift = setInterval(() => {
      const now = performance.now(),
        elapsed = lastDrift ? Math.min(100, now - lastDrift) : 0;
      lastDrift = now;
      if (
        document.hidden ||
        vertical ||
        down ||
        hover ||
        motionPaused ||
        motion.matches ||
        now - lastInput < 3800 ||
        document.querySelector("dialog[open]") ||
        document.activeElement !== document.body ||
        frame
      )
        return;
      current += elapsed * 0.000033;
      target = current;
      paint();
    }, 64);
    window.addEventListener("closari-motion", pause);
    const refresh = () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        if (alive) resize();
      }, 40);
    };
    images.forEach((im) => {
      im.onload = refresh;
    });
    document.fonts.ready.then(() => {
      if (alive) resize();
    });
    resize();
    const themeObserver = new MutationObserver(resize);
    themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    });
    const obs = new ResizeObserver(resize);
    obs.observe(canvas);
    canvas.addEventListener("pointerdown", start);
    canvas.addEventListener("pointermove", move);
    canvas.addEventListener("pointerup", release);
    canvas.addEventListener("pointercancel", cancel);
    canvas.addEventListener("pointerleave", cursorOff);
    canvas.addEventListener("wheel", wheel, { passive: false });
    window.addEventListener("keydown", key);
    return () => {
      alive = false;
      obs.disconnect();
      themeObserver.disconnect();
      clearInterval(drift);
      window.removeEventListener("closari-motion", pause);
      cancelAnimationFrame(frame);
      clearTimeout(wheelTimer);
      clearTimeout(resizeTimer);
      images.forEach((im) => (im.onload = null));
      window.removeEventListener("keydown", key);
      canvas.removeEventListener("pointerdown", start);
      canvas.removeEventListener("pointermove", move);
      canvas.removeEventListener("pointerup", release);
      canvas.removeEventListener("pointercancel", cancel);
      canvas.removeEventListener("pointerleave", cursorOff);
      canvas.removeEventListener("wheel", wheel);
    };
  }, []);
  return (
    <main className="gallery">
      <div className="grain" aria-hidden="true"></div>
      <canvas
        ref={canvasRef}
        className={"ribbon " + (ready ? "ready" : "")}
        tabIndex={0}
        aria-label="Closari field studies. Drag, scroll or use arrow keys to browse. Press Enter to open a chapter."
      />
      <div className="open-cursor" ref={cursor} aria-hidden="true">
        <span>Open ↗</span>
      </div>
      <div className="cube-home">
        <Cube />
      </div>
      <div className="gallery-intro">
        <h1 aria-label="Prediction markets for the closing bell.">
          {["Prediction markets", "for the closing bell."].map(
            (line, index) => (
              <span className="intro-line" key={line} aria-hidden="true">
                {[...line].map((char, i) => (
                  <span key={i} style={{ "--n": index * 17 + i }}>
                    {char === " " ? "\u00a0" : char}
                  </span>
                ))}
              </span>
            ),
          )}
        </h1>
        <p className="hero-definition">
          An automated market maker prices each stock-token outcome. Oracle
          prices settle the close in USDG.
        </p>
      </div>
      <a
        className="network-sign"
        href="https://docs.robinhood.com/chain/"
        target="_blank"
        rel="noreferrer"
        aria-label="Robinhood Chain documentation"
      >
        <img
          className="network-day"
          src="/network/robinhood-chain-black.svg"
          alt="Robinhood Chain"
        />
        <img
          className="network-night"
          src="/network/robinhood-chain-white.svg"
          alt="Robinhood Chain"
        />
      </a>
      <div
        className="gallery-track"
        ref={control}
        aria-label="Featured chapter selector"
        onPointerDown={(e) => {
          railPointer.current = e.pointerId;
          e.currentTarget.setPointerCapture(e.pointerId);
          scrubTrack(e);
        }}
        onPointerMove={(e) => {
          if (railPointer.current === e.pointerId) scrubTrack(e);
        }}
        onPointerUp={() => {
          railPointer.current = null;
        }}
        onPointerCancel={() => {
          railPointer.current = null;
        }}
      >
        {featured.map((a, i) => (
          <button
            key={a.slug}
            aria-label={"Select " + a.name}
            aria-pressed={selected === i}
            onClick={() => actions.current.select(i)}
          />
        ))}
        <i aria-hidden="true" />
      </div>
      <span className="phone-ticker" aria-hidden="true" key={selected}>
        {featured[selected].tag.toUpperCase()} / {fmt(selected)}
      </span>
      <a className="sr-reveal" href={featured[selected].href}>
        Open {featured[selected].name} field study
      </a>
      <span className="sr-only" aria-live="polite">
        {featured[selected].name}, {selected + 1} of {featured.length}
      </span>
    </main>
  );
}
