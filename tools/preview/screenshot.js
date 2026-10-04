// Renders tools/preview/out/*.html to PNG with Playwright's Chromium.
// Usage: node tools/preview/screenshot.js
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

(async () => {
  const out = path.join(__dirname, "out");
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on("pageerror", (error) => console.error("page error:", error.message));
  for (const file of fs.readdirSync(out).filter((f) => f.endsWith(".html"))) {
    await page.goto("file://" + path.join(out, file));
    const target = path.join(out, file.replace(/\.html$/, ".png"));
    await page.screenshot({ path: target });
    console.log("rendered", path.relative(process.cwd(), target));
  }
  await browser.close();
})();
