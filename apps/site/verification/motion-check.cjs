const path = require("node:path"),
  fs = require("node:fs"),
  assert = require("node:assert/strict");
const { chromium } = require(
  process.env.CLOSARI_TOOLS
    ? path.join(process.env.CLOSARI_TOOLS, "playwright")
    : "playwright",
);
const base = process.env.CLOSARI_URL || "http://127.0.0.1:5187",
  out = process.env.CLOSARI_QA || __dirname;
(async () => {
  const browser = await chromium.launch({ channel: "chrome", headless: true });
  const page = await browser.newPage({
    viewport: { width: 1440, height: 900 },
  });
  const checks = [];
  try {
    await page.goto(base);
    await page.waitForSelector("canvas.ready");
    await page
      .getByRole("button", { name: "Pause gallery motion" })
      .last()
      .click();
    await page.mouse.move(720, 400);
    await page.waitForTimeout(180);
    assert.equal(
      await page.locator(".open-cursor").getAttribute("data-show"),
      "true",
    );
    checks.push("Pointer hover shows opening affordance");
    await page.mouse.wheel(0, 285);
    await page.waitForTimeout(850);
    assert.equal(
      await page
        .locator(".gallery-track [aria-pressed=true]")
        .getAttribute("aria-label"),
      "Select What we do",
    );
    checks.push("Wheel settles one chapter forward");
    await page.mouse.move(850, 400);
    await page.mouse.down();
    await page.mouse.move(560, 400, { steps: 12 });
    await page.mouse.up();
    await page.waitForTimeout(800);
    assert.equal(
      await page
        .locator(".gallery-track [aria-pressed=true]")
        .getAttribute("aria-label"),
      "Select Case study",
    );
    checks.push("Pointer drag settles without navigating");
    const rail = await page.locator(".gallery-track").boundingBox();
    await page.mouse.move(rail.x + 5, rail.y + 16);
    await page.mouse.down();
    await page.mouse.move(rail.x + rail.width - 3, rail.y + 16, { steps: 14 });
    await page.mouse.up();
    await page.waitForTimeout(750);
    assert.equal(
      await page
        .locator(".gallery-track [aria-pressed=true]")
        .getAttribute("aria-label"),
      "Select Roadmap",
    );
    checks.push("Progress rail dragging selects Roadmap");
    await page.goto(base + "/terminal/nvda");
    await page.getByRole("button", { name: "At close", exact: true }).click();
    await page.getByLabel("Hypothetical token close").fill("0");
    assert.ok(
      (await page.locator(".close-scenario").innerText()).includes(
        "Void window",
      ),
    );
    await page.getByLabel("Hypothetical token close").fill("1");
    assert.ok(
      (await page.locator(".close-scenario").innerText()).includes(
        "100.00 USDG",
      ),
    );
    checks.push(
      "Closing-price scenario switches between void band and a winning example",
    );
    await page.getByRole("button", { name: "Review paper buy" }).click();
    await page.keyboard.press("Escape");
    assert.ok((await page.getByRole("dialog").count()) === 0);
    assert.ok(
      (await page.locator(".ticket-balance").innerText()).includes("10,000.00"),
    );
    checks.push("Dismissed review preserves balance");
    const mobile = await browser.newPage({
      viewport: { width: 390, height: 844 },
      hasTouch: true,
      isMobile: true,
      deviceScaleFactor: 1,
    });
    await mobile.goto(base);
    await mobile.locator("canvas.ready").waitFor();
    const cdp = await mobile.context().newCDPSession(mobile);
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: 190, y: 550 }],
    });
    for (let y = 525; y >= 265; y -= 20) {
      await cdp.send("Input.dispatchTouchEvent", {
        type: "touchMove",
        touchPoints: [{ x: 190, y }],
      });
    }
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchEnd",
      touchPoints: [],
    });
    await mobile.waitForTimeout(850);
    assert.equal(
      await mobile
        .locator(".gallery-track [aria-pressed=true]")
        .getAttribute("aria-label"),
      "Select What we do",
    );
    checks.push("Phone touch swipe advances the vertical ribbon");
    await mobile.touchscreen.tap(195, 420);
    await mobile.waitForURL("**/field/how-it-works");
    checks.push("Touch opens the centered field study");
    fs.writeFileSync(
      path.join(out, "motion-result.json"),
      JSON.stringify({ checks }, null, 2),
    );
    console.log(checks.length + " interaction checks passed");
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
