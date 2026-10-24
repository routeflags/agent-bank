import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const puppeteer = require("puppeteer-core");

const CHROME_PATH =
  process.env.CHROME_PATH ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const BASE_URL = process.env.BASE_URL || "http://localhost:3000";
const LOCALE = process.env.LOCALE || "ja";
const DATE_DIR = process.env.DATE_DIR || "20260819";

const USERNAME = process.env.LOGIN_USERNAME || "admin2";
const PASSWORD = process.env.LOGIN_PASSWORD || "TestPassword1!";

const screenshotsDir = path.resolve(
  process.cwd(),
  "screenshots",
  DATE_DIR,
  "browser_round1"
);

async function ensureDir(dirPath) {
  await fs.mkdir(dirPath, { recursive: true });
}

async function screenshot(page, name, fullPage = true) {
  const filePath = path.join(screenshotsDir, name);
  await page.screenshot({ path: filePath, fullPage });
  return filePath;
}

function url(p) {
  if (p.startsWith("http://") || p.startsWith("https://")) return p;
  return `${BASE_URL}${p}`;
}

async function safeWaitForNavigation(page, timeoutMs = 15000) {
  try {
    await page.waitForNavigation({ timeout: timeoutMs, waitUntil: "networkidle2" });
    return true;
  } catch {
    return false;
  }
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  await ensureDir(screenshotsDir);

  const browser = await puppeteer.launch({
    executablePath: CHROME_PATH,
    headless: "new",
    args: [
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-gpu",
      "--window-size=1440,900",
    ],
    defaultViewport: { width: 1440, height: 900 },
  });

  const page = await browser.newPage();

  const report = {
    baseUrl: BASE_URL,
    locale: LOCALE,
    screenshots: {},
    notes: [],
    issues: [],
  };

  try {
    // 1) Top
    await page.goto(url(`/${LOCALE}/`), { waitUntil: "networkidle2" });
    report.screenshots.top = await screenshot(page, "01_top.png", true);

    // Detect search warning banner (best-effort)
    const hasSearchDownBanner = await page.evaluate(() => {
      const text = document.body?.innerText || "";
      return text.includes("現在検索が使用できません");
    });
    if (hasSearchDownBanner) {
      report.issues.push({
        severity: "P0",
        title: "検索が停止中（現在検索が使用できません）",
        evidence: "トップに検索停止バナーが表示される",
        screenshot: "01_top.png",
      });
    }

    // 2) Login
    await page.goto(url(`/${LOCALE}/login`), { waitUntil: "networkidle2" });
    report.screenshots.login = await screenshot(page, "02_login.png", false);

    // Fill and submit
    await page.type("#main_person_login", USERNAME, { delay: 10 });
    await page.type("#main_person_password", PASSWORD, { delay: 10 });

    await Promise.all([
      page.click("#main_log_in_button"),
      safeWaitForNavigation(page),
    ]);

    report.screenshots.after_login = await screenshot(page, "03_after_login.png", false);

    // 3) New listing page (auth-only)
    await page.goto(url(`/${LOCALE}/listings/new`), { waitUntil: "networkidle2" });
    report.screenshots.listings_new = await screenshot(page, "04_listings_new.png", true);

    // Detect locale drift (e.g. /fi/)
    const currentUrl = page.url();
    if (!currentUrl.includes(`/${LOCALE}/`)) {
      report.issues.push({
        severity: "P0",
        title: "ロケールが保持されず他言語へ遷移する可能性",
        evidence: `想定ロケール: /${LOCALE}/, 実URL: ${currentUrl}`,
        screenshot: "04_listings_new.png",
      });
    }

    // 4) Listing detail + chat panel open
    const listingId = Number(process.env.LISTING_ID || "20");
    const listingSlug =
      process.env.LISTING_SLUG || "tesuto-raiteingu-asisutanto";
    await page.goto(url(`/${LOCALE}/listings/${listingId}-${listingSlug}`), {
      waitUntil: "networkidle2",
    });
    report.screenshots.listing_detail = await screenshot(page, "05_listing_detail.png", true);

    // Open chat trigger
    await page.click('button[aria-label="Open AI chat"]');
    await page.waitForSelector('[aria-label="AI Chat"]', { timeout: 15000 });
    report.screenshots.chat_open = await screenshot(page, "06_chat_open.png", true);

    // 5) Send a message (may error depending on config)
    const message = process.env.CHAT_MESSAGE || "こんにちは。自己紹介して。";
    await page.type('textarea[aria-label="Chat message input"]', message, {
      delay: 10,
    });

    await page.click('button[aria-label="Send message"]');
    await sleep(2500);
    report.screenshots.chat_after_send = await screenshot(page, "07_chat_after_send.png", true);

    const lastSystemMessage = await page.evaluate(() => {
      const bubbles = Array.from(document.querySelectorAll(".chatPanel__message"));
      const system = bubbles.filter((el) => {
        return (el.getAttribute("data-role") || "").toLowerCase() === "system";
      });
      const last = system[system.length - 1];
      return last ? last.textContent?.trim() : null;
    });
    if (lastSystemMessage && lastSystemMessage.length > 0) {
      report.notes.push({ kind: "system_message", text: lastSystemMessage });
    }
  } finally {
    await page.close().catch(() => {});
    await browser.close().catch(() => {});
  }

  const outPath = path.join(screenshotsDir, "report.json");
  await fs.writeFile(outPath, JSON.stringify(report, null, 2), "utf-8");
  process.stdout.write(`${outPath}\n`);
}

main().catch((err) => {
  process.stderr.write(String(err?.stack || err) + "\n");
  process.exitCode = 1;
});
