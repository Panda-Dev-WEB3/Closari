const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
const { chromium } = require(
  process.env.CLOSARI_TOOLS
    ? path.join(process.env.CLOSARI_TOOLS, "playwright")
    : "playwright",
);
const base = process.env.CLOSARI_URL || "http://127.0.0.1:5187",
  out = process.env.CLOSARI_QA || __dirname;
(async () => {
  const browser = await chromium.launch({ channel: "chrome" }),
    page = await browser.newPage({
      viewport: { width: 1440, height: 900 },
      reducedMotion: "reduce",
    });
  const checked = [];
  async function verify(selector, role) {
    const actual = await page
      .locator(selector)
      .first()
      .evaluate(async (e) => {
        await document.fonts.ready;
        const s = getComputedStyle(e);
        return {
          font: s.fontFamily,
          weight: s.fontWeight,
          width: e.getBoundingClientRect().width,
          loaded: [...document.fonts].some(
            (f) => f.family.includes("Magic Pixel") && f.status === "loaded",
          ),
        };
      });
    assert.ok(
      actual.loaded &&
        actual.font.startsWith('"Magic Pixel"') &&
        actual.weight === "400",
      role + " font mismatch",
    );
    checked.push({ role, ...actual });
  }
  try {
    await page.goto(base);
    await verify(".site-head>.wordmark", "Gallery wordmark");
    await page.screenshot({
      path: path.join(out, "brand-desktop.jpg"),
      quality: 88,
    });
    await page.goto(base + "/terminal/nvda");
    await verify(".desk-head>.wordmark", "Terminal wordmark");
    await page.goto(base + "/field/technology");
    await verify(".footer-logo", "Footer wordmark");
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(base);
    await verify(".site-head>.wordmark", "Phone wordmark");
    await page.getByRole("button", { name: "Menu", exact: true }).click();
    await verify(".site-menu .wordmark", "Mobile menu wordmark");
    await page.screenshot({
      path: path.join(out, "brand-mobile-menu.jpg"),
      quality: 88,
    });
    fs.writeFileSync(
      path.join(out, "brand-result.json"),
      JSON.stringify(checked, null, 2),
    );
    console.log(
      checked.length + " branded placements use loaded Magic Pixel Regular",
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
