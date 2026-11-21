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
const chapters = [
  "technology",
  "how-it-works",
  "case-study",
  "settlement",
  "liquidity",
  "faq",
  "roadmap",
];
const checks = [];
const errors = [];
const check = (condition, label) => {
  assert.ok(condition, label);
  checks.push(label);
};
async function run() {
  const browser = await chromium.launch({ channel: "chrome" });
  const page = await browser.newPage({ reducedMotion: "reduce" });
  fs.mkdirSync(out, { recursive: true });
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("response", (r) => {
    if (r.status() >= 400) errors.push(r.url());
  });
  const visit = async (route) => {
    await page.goto(base + route);
    await page.locator("main h1").waitFor();
    await page.evaluate(() => document.fonts.ready);
  };
  try {
    for (const width of [1440, 768, 390, 320]) {
      await page.setViewportSize({ width, height: width > 800 ? 900 : 844 });
      for (const theme of ["dark", "light"]) {
        await visit("/protocol");
        if ((await page.locator("html").getAttribute("data-theme")) !== theme)
          await page.getByRole("switch", { name: "White theme" }).click();
        assert.deepEqual(
          await page
            .locator(".chapter-index a")
            .evaluateAll((links) =>
              links.map((link) => link.getAttribute("href")),
            ),
          chapters.map((slug) => "/field/" + slug),
        );
        for (const [index, slug] of chapters.entries()) {
          await visit("/field/" + slug);
          const result = await page
            .locator(".chapter-page")
            .evaluate(async (main) => {
              await Promise.all(
                [...main.querySelectorAll("img")].map((img) => {
                  img.loading = "eager";
                  return img.decode();
                }),
              );
              const article = main.querySelector("article");
              const targets = [
                ...main.querySelectorAll(".reading-index a"),
              ].every((a) => !!document.getElementById(a.hash.slice(1)));
              const panel = main
                .querySelector(".study-plate")
                .getBoundingClientRect();
              const sheet = main
                .querySelector(".paper-study")
                .getBoundingClientRect();
              return {
                fits:
                  document.documentElement.scrollWidth <=
                    document.documentElement.clientWidth + 1 &&
                  article.scrollWidth <= article.clientWidth + 1,
                sheetFits:
                  sheet.left >= panel.left &&
                  sheet.right <= panel.right &&
                  sheet.top >= panel.top &&
                  sheet.bottom <= panel.bottom,
                title: main
                  .querySelector(".sheet-head > span:last-child")
                  .textContent.trim(),
                next: main.querySelector(".next-study").getAttribute("href"),
                targets,
              };
            });
          const label = width + "px " + theme + " " + slug;
          check(
            result.fits && result.sheetFits && result.targets,
            label + " fits and links to its reading sections",
          );
          check(
            result.next === "/field/" + chapters[(index + 1) % 7] &&
              result.title === "0" + (index + 1) + " / 07",
            label + " has the matching folio and next chapter",
          );
          if (
            (width === 1440 && theme === "dark") ||
            (width === 390 &&
              theme === "light" &&
              ["case-study", "settlement"].includes(slug))
          ) {
            await page
              .locator(".chapter-body article")
              .evaluate((el) =>
                window.scrollTo(
                  0,
                  el.getBoundingClientRect().top + window.scrollY - 30,
                ),
              );
            await page.screenshot({
              path: path.join(out, "reading-" + slug + "-" + width + ".jpg"),
              quality: 88,
            });
          }
        }
      }
    }
    await page.setViewportSize({ width: 1280, height: 900 });
    await visit("/field/liquidity");
    await page.getByRole("button", { name: "One market", exact: true }).click();
    check(
      (await page.locator(".sheet-number").innerText()) === "0.75%" &&
        (await page.locator(".sheet-content p").innerText()).includes(
          "750 USDG",
        ),
      "One-market budget and cap agree",
    );
    await page
      .getByRole("button", { name: "All open markets", exact: true })
      .click();
    check(
      (await page.locator(".sheet-content p").innerText()).includes(
        "40,000 USDG",
      ),
      "Pool-wide budget switches back",
    );
    await visit("/field/faq");
    const search = page.getByRole("searchbox");
    await search.fill("time-weighted");
    check(
      (await page.locator(".question-group").count()) === 1,
      "FAQ search keeps the matching category",
    );
    await page
      .getByRole("button", { name: "What do I receive on a void?" })
      .click();
    check(
      (await page.locator(".accord.expanded").innerText()).includes(
        "60 minutes",
      ),
      "FAQ includes the audited void window",
    );
    await visit("/protocol#roadmap");
    check(
      (await page.locator("main h1").innerText()) === "Roadmap" &&
        (await page.locator(".phase-index button").count()) === 8,
      "Roadmap shortcut retains eight engineering milestones",
    );
    await visit("/field/about/");
    await page.waitForURL("**/protocol");
    check(
      (await page.locator(".chapter-index a").count()) === 7 &&
        !(await page.locator("body").innerText()).includes("Who we are"),
      "Retired bookmark opens the current protocol index",
    );
    check(errors.length === 0, "No page or network errors");
    console.log(
      checks.length + " chapter copy, navigation and layout checks passed",
    );
  } finally {
    fs.writeFileSync(
      path.join(out, "chapter-result.json"),
      JSON.stringify({ checks, errors }, null, 2),
    );
    await browser.close();
  }
}
run().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
