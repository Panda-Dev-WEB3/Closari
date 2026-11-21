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
    p = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  const checks = [],
    errors = [];
  const check = (test, label) => {
    assert.ok(test, label);
    checks.push(label);
  };
  const theme = () => p.locator("html").getAttribute("data-theme");
  const visit = async (route) => {
    await p.goto(base + route);
    await p.locator("main h1").waitFor();
  };
  const toggle = () => p.getByRole("switch", { name: "White theme" }).click();
  p.on("pageerror", (err) => errors.push(err.message));
  p.on("response", (r) => {
    if (r.status() >= 400) errors.push(r.url());
  });
  try {
    await visit("/");
    check((await theme()) === "dark", "Fresh landing uses navy");
    const title = await p.locator("main h1").getAttribute("aria-label");
    check(
      title === "Prediction markets for the closing bell.",
      "Hero states the product",
    );
    check(
      await p.locator(".network-sign").evaluate((el) => {
        const image = Array.from(el.querySelectorAll("img")).find(
          (i) => getComputedStyle(i).display !== "none",
        );
        return (
          getComputedStyle(el).backgroundColor === "rgba(0, 0, 0, 0)" &&
          image.src.endsWith("white.svg") &&
          image.clientHeight >= 20
        );
      }),
      "Official white lockup has a transparent surround",
    );
    const canvas = p.locator(".cube-home .folded-emblem canvas[data-ready]");
    await canvas.waitFor();
    const pixels = () => canvas.evaluate((c) => c.toDataURL());
    let a = await pixels();
    await p.waitForTimeout(420);
    check(a !== (await pixels()), "Folded C turns in three dimensions");
    await p.locator(".cube-home button").click();
    await p.waitForTimeout(120);
    a = await pixels();
    await p.waitForTimeout(260);
    check(a === (await pixels()), "Pausing freezes the cube");
    await p.locator(".site-head nav a[href='/terminal/nvda']").click();
    check(
      (await theme()) === "light",
      "Client navigation applies independent white desk default",
    );
    check(
      !(await p.locator("main").innerText()).includes("Closing desk"),
      "Former heading removed",
    );
    await toggle();
    await visit("/");
    check(
      (await theme()) === "dark",
      "Desk choice leaves landing preference alone",
    );
    await toggle();
    await visit("/terminal/nvda");
    check((await theme()) === "dark", "Manual desk choice survives reload");
    await toggle();
    await visit("/");
    check((await theme()) === "light", "Manual gallery choice survives reload");
    await visit("/terminal/nvda");
    check(
      (await p.locator(".strike-keys a").count()) === 6,
      "Six independent strike selectors",
    );
    await p.locator(".strike-keys a").first().click();
    check(
      (await p.locator("main h1").textContent()).includes("$178.71"),
      "Selector drives active price",
    );
    await p.keyboard.press("Control+k");
    check(
      (await p.getByRole("option").count()) === 96,
      "Keyboard finder lists 96 markets",
    );
    await p.getByRole("combobox").fill("TSLA range");
    check(
      (await p.getByRole("option").count()) === 1,
      "Multi-term finder narrows to one contract",
    );
    await p.keyboard.press("Enter");
    await p.waitForURL("**/terminal/tsla?format=Range");
    await p.getByRole("button", { name: "50", exact: true }).click();
    check(
      (await p.locator(".quote-lines").first().innerText()).includes(
        "10.16 USDG",
      ),
      "TSLA 50-share fill gross matches the brief",
    );
    check(
      (await p.locator(".execution-preview").innerText()).includes("20.65"),
      "Ticket shows price after the range order",
    );
    await p.getByRole("button", { name: "Review paper buy" }).click();
    await p.getByRole("button", { name: "Confirm paper buy" }).click();
    await p.getByRole("button", { name: "Market terms", exact: true }).click();
    check(
      (await p.locator(".market-terms").innerText()).includes("10.16 USDG"),
      "Local market volume tracks confirmed fills",
    );
    await p.getByRole("button", { name: "Settlement", exact: true }).click();
    check(
      (await p.locator(".proof-panel").innerText()).includes("Round pending"),
      "Pre-close proof and claims are pending",
    );
    for (const width of [320, 390, 768, 1024, 1440]) {
      await p.setViewportSize({ width, height: 900 });
      await visit("/terminal/nvda");
      const size = await p.evaluate(() => {
        const ticket = document
            .querySelector(".ticket")
            .getBoundingClientRect(),
          balance = document
            .querySelector(".ticket-balance")
            .getBoundingClientRect(),
          clock = document
            .querySelector(".session-card")
            .getBoundingClientRect();
        return [
          ticket.bottom - balance.bottom,
          clock.top - ticket.bottom,
          document.documentElement.scrollWidth -
            document.documentElement.clientWidth,
        ];
      });
      check(
        size[0] < 25 &&
          size[2] <= 1 &&
          (width <= 700 || Math.abs(size[1] - 14) <= 5),
        width + "px ticket fits its contents and neighboring cards",
      );
    }
    await p.setViewportSize({ width: 390, height: 844 });
    await p.getByRole("button", { name: "Order ticket ↓" }).click();
    check(
      await p
        .locator("#paper-order")
        .evaluate(
          (el) =>
            el === document.activeElement &&
            el.getBoundingClientRect().top < 40,
        ),
      "Mobile shortcut focuses order ticket",
    );
    check(!errors.length, "No page errors or failed network requests");
    console.log(checks.length + " focused desk and identity checks passed");
  } finally {
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(
      path.join(out, "desk-result.json"),
      JSON.stringify({ checks, errors }, null, 2),
    );
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
