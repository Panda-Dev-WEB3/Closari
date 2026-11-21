const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { chromium } = require(
  process.env.CLOSARI_TOOLS
    ? path.join(process.env.CLOSARI_TOOLS, "playwright")
    : "playwright",
);
const base = process.env.CLOSARI_URL || "http://127.0.0.1:5187";
const out = process.env.CLOSARI_QA || __dirname;
fs.mkdirSync(out, { recursive: true });
const error = [],
  checks = [];
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
    reducedMotion: "reduce",
  });
  const page = await context.newPage();
  page.on("pageerror", (e) => error.push(e.message));
  page.on("response", (r) => {
    if (r.status() >= 400) error.push(r.status() + " " + r.url());
  });
  const url = (s) => base + s;
  const check = (desc, test) => {
    assert.ok(test, desc);
    checks.push(desc);
  };
  const snap = async (name) => {
    await page.screenshot({
      path: path.join(out, name + ".jpg"),
      type: "jpeg",
      quality: 87,
    });
  };
  const get = async (p) => {
    await page.goto(url(p));
    await page.locator("h1").waitFor();
    await page.evaluate(() => document.fonts.ready);
  };
  try {
    await get("/");
    await page.waitForTimeout(250);
    await snap("home-desktop");
    await page.locator("canvas.ribbon").focus();
    await page.keyboard.press("ArrowRight");
    await page.waitForTimeout(80);
    await page.keyboard.press("Enter");
    await page.waitForURL("**/field/how-it-works");
    check("Keyboard hero opens What we do", true);
    await get("/field/about");
    await page.waitForURL("**/protocol");
    check("Retired chapter opens the seven-study index", await page.locator(".chapter-index a").count() === 7);
    await get("/");
    await page.mouse.move(720, 400);
    await page.mouse.click(720, 400);
    await page.waitForURL("**/field/technology");
    check("Pointer opens Technology chapter", true);
    await snap("technology-desktop");
    await page.locator("input[type=range]").fill("210");
    check(
      "Technology study reprices 210 shares",
      (await page.locator(".sheet-control").textContent()).includes("210"),
    );
    await get("/field/roadmap");
    await page.getByRole("button", { name: /M8 Replay/ }).click();
    check(
      "Roadmap reveals M8 acceptance criteria",
      (await page.locator(".phase-content").textContent()).includes("dry-run"),
    );
    await get("/field/faq");
    await page.getByRole("searchbox").fill("void");
    await page
      .getByRole("button", { name: "What do I receive on a void?" })
      .click();
    check(
      "FAQ search and accessible expansion",
      (await page
        .getByRole("button", { name: "What do I receive on a void?" })
        .getAttribute("aria-expanded")) === "true",
    );
    await get("/markets");
    check(
      "Index contains 12 PNG marks",
      (await page
        .locator('.market-index .issuer-sculpture[src$=".png"]')
        .count()) === 12,
    );
    await page.getByRole("button", { name: "List", exact: true }).click();
    await page.getByRole("searchbox").fill("QQQ");
    check(
      "Ticker filter/list returns matching fund",
      (await page.locator(".market-card").count()) === 1,
    );
    await page.getByRole("button", { name: "Range", exact: true }).click();
    await page.locator(".market-card").click();
    await page.waitForURL("**/terminal/qqq?format=Range");
    check(
      "Filtered market opens range ticket",
      (await page.locator(".outcome-picks button").count()) === 5,
    );
    await get("/terminal/nvda");
    await snap("terminal-desktop");
    check(
      "NVDA 100-share quote matches source example",
      (await page.locator(".quote-lines").first().innerText()).includes(
        "62.72 USDG",
      ),
    );
    await page.getByRole("button", { name: "Add to watchlist" }).click();
    await page.getByRole("button", { name: /Watchlist/ }).click();
    check(
      "Watchlist selects saved market",
      (await page.locator(".ticker-chip").count()) === 1,
    );
    await page.getByRole("button", { name: /Market tape/ }).click();
    await page.getByRole("button", { name: "1H", exact: true }).click();
    await page.getByRole("slider").focus();
    await page.keyboard.press("ArrowLeft");
    check(
      "Chart keyboard scrub changes observed minute",
      (await page.getByRole("slider").getAttribute("aria-valuetext")).includes(
        "14:41",
      ),
    );
    await page.getByRole("button", { name: "Review paper buy" }).click();
    check(
      "Review explains void TWAP",
      (await page.locator(".review-modal").innerText()).includes("60 minutes"),
    );
    await page.getByRole("button", { name: "Confirm paper buy" }).click();
    await page.locator(".trade-notice").waitFor();
    check(
      "Buy leaves expected paper cash",
      (await page.locator(".ticket-balance").innerText()).includes("9,937.28"),
    );
    await page.reload();
    await page.getByRole("button", { name: /Positions/ }).click();
    check(
      "Reload preserves 100 shares",
      (await page.locator(".ledger table").innerText()).includes("100"),
    );
    await page.getByRole("button", { name: "Sell", exact: true }).click();
    await page.getByLabel("Shares to sell").fill("101");
    check(
      "Sell cannot exceed position",
      await page
        .getByRole("button", { name: "Review paper sell" })
        .isDisabled(),
    );
    await page.getByLabel("Shares to sell").fill("50");
    await page.getByRole("button", { name: "Review paper sell" }).click();
    await page.getByRole("button", { name: "Confirm paper sell" }).click();
    await page.locator(".trade-notice").waitFor();
    await page.getByRole("button", { name: "Activity", exact: true }).click();
    check(
      "Two paper fills recorded",
      (await page.locator(".ledger tbody tr").count()) === 2,
    );
    const symbols = [
      "nvda",
      "tsla",
      "spy",
      "aapl",
      "amd",
      "qqq",
      "meta",
      "msft",
      "amzn",
      "googl",
      "pltr",
      "mu",
    ];
    const routes = [
      "/",
      "/markets",
      "/journal",
      "/protocol",
      "/docs",
      ...[
        "technology",
        "how-it-works",
        "case-study",
        "settlement",
        "liquidity",
        "faq",
        "roadmap",
      ].map((s) => "/field/" + s),
      ...["strike", "range", "open", "oracle", "pool", "access"].map(
        (s) => "/journal/" + s,
      ),
      ...["access", "privacy", "settlement", "terms", "fees"].map(
        (s) => "/docs/" + s,
      ),
      ...symbols.map((s) => "/terminal/" + s),
    ];
    for (const route of routes) {
      await get(route);
      const dimensions = await page.locator("img").evaluateAll(async (imgs) => {
        await Promise.all(
          imgs.map((i) => {
            i.loading = "eager";
            return i.decode().catch(() => {});
          }),
        );
        return imgs.map((i) => [i.getAttribute("src"), i.naturalWidth]);
      });
      check(
        route + " renders with valid assets",
        dimensions.every(([, w]) => w > 0) &&
          !(await page.locator("h1").innerText()).includes("unavailable"),
      );
    }
    for (const width of [320, 390, 768, 1024, 1280, 1440]) {
      await page.setViewportSize({ width, height: width <= 390 ? 844 : 900 });
      for (const route of [
        "/",
        "/markets",
        "/field/technology",
        "/field/faq",
        "/field/roadmap",
        "/journal",
        "/protocol",
        "/docs",
        "/terminal/nvda",
        "/terminal/tsla?format=Range",
      ]) {
        await get(route);
        const sizes = await page.evaluate(() => [
          document.documentElement.scrollWidth,
          document.documentElement.clientWidth,
        ]);
        check(width + "px " + route + " fits width", sizes[0] <= sizes[1] + 1);
        if (
          width === 390 &&
          ["/", "/terminal/nvda", "/field/technology", "/markets"].includes(
            route,
          )
        ) {
          await page.waitForTimeout(100);
          await snap(
            "phone-" + (route.slice(1).replaceAll("/", "-") || "home"),
          );
        }
      }
    }
    await page.setViewportSize({ width: 390, height: 844 });
    await get("/");
    await page.getByRole("button", { name: "Menu", exact: true }).click();
    await page
      .getByRole("dialog")
      .getByRole("link", { name: "Markets" })
      .click();
    await page.waitForURL("**/markets");
    check(
      "Mobile menu opens index and closes",
      (await page.getByRole("dialog").count()) === 0,
    );
    await page.goBack();
    await page.waitForURL(base + "/");
    check(
      "Back navigation restores gallery",
      (await page.locator("canvas.ribbon").count()) === 1,
    );
    check("No uncaught browser or HTTP errors", error.length === 0);
    console.log(checks.length + " browser checks passed");
  } finally {
    fs.writeFileSync(
      path.join(out, "browser-result.json"),
      JSON.stringify({ base, checks, error }, null, 2),
    );
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
