const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require(process.env.CLOSARI_TOOLS
  ? path.join(process.env.CLOSARI_TOOLS, "playwright")
  : "playwright");
const base = process.env.CLOSARI_URL || "http://127.0.0.1:5187";
const out = process.env.CLOSARI_QA || __dirname;
const issuers = "NVDA TSLA SPY AAPL AMD QQQ META MSFT AMZN GOOGL PLTR MU".split(" ").sort();
fs.mkdirSync(out, { recursive: true });

async function run() {
  const browser = await chromium.launch({ channel: "chrome" });
  const page = await browser.newPage({ reducedMotion: "reduce" });
  const checks = [];
  const errors = [];
  const check = (ok, label) => { assert.ok(ok, label); checks.push(label); };
  page.on("pageerror", e => errors.push(e.message));
  page.on("response", r => { if (r.status() >= 400) errors.push(r.url()); });
  const visit = async route => {
    await page.goto(base + route);
    await page.locator("main h1").waitFor();
    await page.evaluate(() => document.fonts.ready);
  };
  // Observe the actual rectangle sent to the browser for every visible gallery tile.
  await page.addInitScript(() => {
    const context = CanvasRenderingContext2D.prototype;
    const clear = context.clearRect;
    const draw = context.drawImage;
    context.clearRect = function (...args) {
      if (this.canvas.classList.contains("ribbon")) window.tileDimensions = [];
      return clear.apply(this, args);
    };
    context.drawImage = function (...args) {
      if (this.canvas.classList.contains("ribbon"))
        window.tileDimensions.push([args[3], args[4]]);
      return draw.apply(this, args);
    };
  });
  const shot = name => page.screenshot({ path: path.join(out, name + ".jpg"), quality: 89 });
  try {
    for (const width of [1440, 768, 390]) {
      await page.setViewportSize({ width, height: width === 1440 ? 900 : 844 });
      await visit("/");
      await page.locator(".ribbon.ready").waitFor();
      const tileData = await page.evaluate(async () => {
        const urls = [...new Set(performance.getEntriesByType("resource")
          .map(entry => entry.name).filter(url => url.includes("/chapter-icons/")))];
        const masters = await Promise.all(urls.map(async url => {
          const im = new Image(); im.src = url; await im.decode();
          return [im.naturalWidth, im.naturalHeight];
        }));
        return { drawn: window.tileDimensions, masters };
      });
      check(tileData.drawn.length >= 3 && tileData.drawn.every(([w,h]) =>
        w === h && w === tileData.drawn[0][0]), width + "px ribbon draws equally sized squares");
      check(tileData.masters.length === 7 && tileData.masters.every(([w,h]) =>
        w === 720 && h === 720), width + "px gallery loads all seven square masters");
    }

    for (const width of [1440, 390]) {
      await page.setViewportSize({ width, height: width === 1440 ? 900 : 844 });
      for (const theme of ["dark", "light"]) {
        await visit("/markets");
        const toggle = page.getByRole("switch", { name: "White theme" });
        if ((await page.locator("html").getAttribute("data-theme")) !== theme) await toggle.click();
        for (const layout of ["Grid", "List"]) {
          await page.getByRole("button", { name: layout, exact: true }).click();
          const marks = await page.locator(".market-card .issuer-sculpture").evaluateAll(async images => {
            return Promise.all(images.map(async image => {
              image.loading = "eager";
              await image.decode();
              const card = image.closest("a");
              const frame = image.parentElement.getBoundingClientRect();
              const rect = image.getBoundingClientRect();
              const ticker = card.querySelector(".market-cap > span:last-child").textContent;
              // Check the visible silhouette as well as its image element.
              const canvas = document.createElement("canvas");
              canvas.width = canvas.height = 180;
              const ctx = canvas.getContext("2d");
              ctx.drawImage(image, 0, 0, 180, 180);
              const rgba = ctx.getImageData(0, 0, 180, 180).data;
              let left=180, right=-1, top=180, bottom=-1;
              for (let y=0; y<180; y++) for (let x=0; x<180; x++) {
                if (rgba[(y*180+x)*4+3] <= 12) continue;
                left=Math.min(left,x); right=Math.max(right,x);
                top=Math.min(top,y); bottom=Math.max(bottom,y);
              }
              return { ticker,
                mapped: image.currentSrc.endsWith("/issuer-reliefs/"+ticker.toLowerCase()+".png")
                  && new URL(card.href).pathname === "/terminal/"+ticker.toLowerCase(),
                square: image.naturalWidth === 720 && image.naturalHeight === 720
                  && Math.abs(frame.width-frame.height) <= 1,
                centered: Math.abs(rect.left+rect.right-frame.left-frame.right) <= 1
                  && Math.abs(rect.top+rect.bottom-frame.top-frame.bottom) <= 1
                  && left>0 && top>0 && right<179 && bottom<179 && right>left && bottom>top
                  && Math.abs((left+right)/2-89.5)<=0.5 && Math.abs((top+bottom)/2-89.5)<=0.5 };
            }));
          });
          const key = width+"px "+theme+" "+layout;
          assert.deepEqual(marks.map(m => m.ticker).sort(), issuers);
          check(marks.every(m => m.mapped && m.square && m.centered),
            key+" centers each transparent logo in its square and links the matching ticker");
          if ((width === 1440 && theme === "dark") || (width === 390 && theme === "light")) {
            await page.evaluate(() => window.scrollTo(0, document.querySelector(".market-controls").getBoundingClientRect().top + scrollY - 75));
            await shot("markets-"+layout.toLowerCase()+"-"+width);
          }
        }
        await page.getByRole("searchbox", { name: "Find a stock token" }).fill("QQQ");
        await page.locator(".market-card").click();
        await page.waitForURL("**/terminal/qqq");
        check(true, width+"px "+theme+" filtered issuer opens its desk");
      }
    }

    for (const width of [1440, 1024, 768, 701, 700, 390]) {
      await page.setViewportSize({ width, height: width <= 768 ? 844 : 900 });
      for (const [slug,count] of [["nvda",2],["tsla?format=Range",5]]) {
        await visit("/terminal/"+slug);
        const outcomes = page.locator(".outcome-ledger button");
        assert.equal(await outcomes.count(), count);
        await outcomes.last().click();
        assert.equal(await outcomes.last().getAttribute("aria-pressed"), "true");
        const heights = await outcomes.evaluateAll(buttons => buttons.map(b => b.getBoundingClientRect().height));
        check(Math.max(...heights)-Math.min(...heights) <= 1, width+"px "+slug+" has evenly sized outcome rows");
        const tabs = page.locator(".ledger-tabs button");
        for (let i=0; i<await tabs.count(); i++) {
          await tabs.nth(i).click();
          const state = await page.evaluate(() => {
            const bounds = sel => document.querySelector(sel).getBoundingClientRect();
            const ledger = bounds(".ledger"), session = bounds(".session-card"), ticket = bounds(".ticket");
            return { aligned: Math.abs(ledger.bottom-session.bottom) <= 1,
              stacked: ledger.top >= ticket.bottom-1 && session.top >= ledger.bottom-1,
              fits: document.documentElement.scrollWidth <= document.documentElement.clientWidth+1 };
          });
          check((width > 700 ? state.aligned : state.stacked) && state.fits,
            width+"px "+slug+" "+(await tabs.nth(i).innerText()).trim()+" fits its adjacent panel");
          if (width === 1440 && slug === "nvda" && i === 0) {
            await page.locator(".outcome-ledger button").first().click();
            await page.locator(".ledger").scrollIntoViewIfNeeded();
            await shot("outcome-alignment-desktop");
          }
        }
      }
    }
    check(errors.length === 0, "No page errors or failed requests");
    console.log(checks.length + " ribbon, issuer and panel checks passed");
  } finally {
    fs.writeFileSync(path.join(out, "surface-result.json"), JSON.stringify({checks, errors}, null, 2));
    await browser.close();
  }
}
run().catch(error => {console.error(error); process.exitCode=1;});
