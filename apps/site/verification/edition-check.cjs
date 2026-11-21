const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { chromium } = require(
  process.env.CLOSARI_TOOLS
    ? path.join(process.env.CLOSARI_TOOLS, "playwright")
    : "playwright",
);
const origin = process.env.CLOSARI_URL || "http://127.0.0.1:5187",
  out = process.env.CLOSARI_QA || __dirname;
fs.mkdirSync(out, { recursive: true });
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true }),
    p = await browser.newPage({
      viewport: { width: 1440, height: 900 },
      deviceScaleFactor: 1,
      reducedMotion: "reduce",
    });
  const checks = [],
    errors = [];
  p.on("pageerror", (e) => errors.push(e.message));
  p.on("response", (r) => {
    if (r.status() >= 400) errors.push(r.url() + " " + r.status());
  });
  const visit = async (u) => {
    await p.goto(origin + u);
    await p.locator("main h1").waitFor();
    await p.evaluate(() => document.fonts.ready);
  };
  const shot = async (name) =>
    p.screenshot({ path: path.join(out, name + ".jpg"), quality: 86 });
  const check = (condition, msg) => {
    assert.ok(condition, msg);
    checks.push(msg);
  };
  try {
    for (const light of [false, true]) {
      await visit("/");
      const toggle = p.getByRole("switch", { name: "White theme" });
      if (((await toggle.getAttribute("aria-checked")) === "true") !== light)
        await toggle.click();
      await p.reload();
      await p.locator(".ribbon.ready").waitFor();
      const mode = light ? "white" : "night";
      check(
        (await p.locator("html").getAttribute("data-theme")) ===
          (light ? "light" : "dark"),
        mode + " persists across refresh",
      );
      await visit("/terminal/nvda");
      if (((await toggle.getAttribute("aria-checked")) === "true") !== light)
        await toggle.click();
      for (const width of [1440, 1280, 1024, 810, 768, 390, 320]) {
        await p.setViewportSize({ width, height: width < 810 ? 844 : 900 });
        for (const [url, name] of [
          ["/", "gallery"],
          ["/field/technology", "technology"],
          ["/field/roadmap", "roadmap"],
          ["/markets", "markets"],
          ["/journal", "journal"],
          ["/journal/strike", "article"],
          ["/protocol", "protocol"],
          ["/docs", "docs"],
          ["/terminal/nvda", "terminal"],
        ]) {
          await visit(url);
          assert.equal(
            await p.locator("html").getAttribute("data-theme"),
            light ? "light" : "dark",
          );
          const state = await p.evaluate(async () => {
            const imgs = [...document.querySelectorAll("img")];
            await Promise.all(
              imgs.map((i) => {
                i.loading = "eager";
                return i.decode().catch(() => {});
              }),
            );
            return {
              width: document.documentElement.scrollWidth,
              client: document.documentElement.clientWidth,
              broken: imgs
                .filter((i) => !i.naturalWidth)
                .map((i) => i.getAttribute("src")),
            };
          });
          check(
            state.width <= state.client + 1 && state.broken.length === 0,
            mode + " " + width + " " + url + " fits and art decodes",
          );
          if (name === "technology" || name === "roadmap") {
            const fits = await p.locator(".chapter-pair").evaluate((pair) => {
              const art = pair
                .querySelector(".chapter-art")
                .getBoundingClientRect();
              const study = pair
                .querySelector(".study-plate")
                .getBoundingClientRect();
              const stacked = study.top >= art.bottom;
              return stacked
                ? study.top - art.bottom >= 8 &&
                    Math.abs(art.width - art.height) < 1
                : study.left - art.right >= 8 &&
                    Math.abs(art.height - study.height) < 1;
            });
            check(
              fits,
              mode +
                " " +
                width +
                " " +
                url +
                " keeps a clear gap between exhibits",
            );
          }
          if (
            (width === 1440 &&
              [
                "gallery",
                "technology",
                "terminal",
                "journal",
                "markets",
                "protocol",
              ].includes(name)) ||
            (width === 390 &&
              ["gallery", "technology", "terminal"].includes(name))
          ) {
            await p.waitForTimeout(110);
            await shot(mode + "-" + width + "-" + name);
          }
        }
      }
      await p.setViewportSize({ width: 1280, height: 880 });
      await visit("/terminal/tsla?format=Range");
      await p.getByRole("button", { name: "Review paper buy" }).click();
      check(
        await p.locator("dialog.review-modal").isVisible(),
        mode + " range trade review opens",
      );
      await p.keyboard.press("Escape");
      check(
        (await p.getByRole("dialog").count()) === 0,
        mode + " modal dismisses",
      );
      await p.getByRole("button", { name: "At close", exact: true }).click();
      await p.getByLabel("Hypothetical token close").fill("0.5");
      check(
        (await p.locator(".close-scenario").textContent()).includes(
          "Void window",
        ),
        mode + " scenario retains void rule",
      );
    }
    await visit("/terminal/nvda");
    await p.getByRole("button", { name: "50", exact: true }).click();
    const pre = await p.locator(".quote-lines").first().innerText();
    await p.getByRole("switch", { name: "White theme" }).click();
    check(
      (await p.locator(".quote-lines").first().innerText()) === pre &&
        (await p.locator("#share-qty").inputValue()) === "50",
      "Changing theme retains quote and quantity",
    );
    check(errors.length === 0, "No browser errors or failed requests");
    console.log(checks.length + " illustrated frontend checks passed");
  } finally {
    fs.writeFileSync(
      path.join(out, "edition-result.json"),
      JSON.stringify({ checks, errors }, null, 2),
    );
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
