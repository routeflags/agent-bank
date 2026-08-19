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

const USERNAME = process.env.LOGIN_USERNAME || "buyer1";
const PASSWORD = process.env.LOGIN_PASSWORD || "TestPassword1!";

const LISTING_ID = Number(process.env.LISTING_ID || "20");
const LISTING_SLUG =
  process.env.LISTING_SLUG || "tesuto-raiteingu-asisutanto";

const CHAT_MESSAGE = process.env.CHAT_MESSAGE || "こんにちは。自己紹介して。";

const screenshotsDir = path.resolve(
  process.cwd(),
  "screenshots",
  DATE_DIR,
  "browser_round2"
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

async function clickByText(page, text) {
  return await page.evaluate((t) => {
    const candidates = Array.from(
      document.querySelectorAll('a,button,input[type="submit"],input[type="button"]')
    );

    const match = candidates.find((el) => {
      const label =
        (el instanceof HTMLInputElement ? el.value : el.textContent) || "";
      return label.trim().includes(t);
    });

    if (!match) return false;
    (match instanceof HTMLElement ? match : match.parentElement)?.click();
    return true;
  }, text);
}

function shouldTrackUrl(u) {
  return (
    u.includes("/api/") ||
    u.includes("/cable") ||
    u.includes("/chat") ||
    u.includes("/transactions") ||
    u.includes("/paypal") ||
    u.includes("/people/") ||
    u.includes("/listings/")
  );
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
    listing: { id: LISTING_ID, slug: LISTING_SLUG },
    screenshots: {},
    notes: [],
    events: [],
    issues: [],
  };

  page.on("console", (msg) => {
    const type = msg.type();
    if (!["error", "warning"].includes(type)) return;
    report.events.push({ kind: "console", type, text: msg.text() });
  });

  page.on("pageerror", (err) => {
    report.events.push({ kind: "pageerror", message: String(err?.message || err) });
  });

  page.on("requestfailed", (req) => {
    const u = req.url();
    if (!shouldTrackUrl(u)) return;
    report.events.push({
      kind: "requestfailed",
      url: u,
      method: req.method(),
      error: req.failure()?.errorText || null,
    });
  });

  page.on("response", (res) => {
    const u = res.url();
    if (!shouldTrackUrl(u)) return;
    const status = res.status();
    if (status >= 400) {
      report.events.push({ kind: "response", url: u, status });
    }
  });

  try {
    // 1) Top (logged-out)
    await page.goto(url(`/${LOCALE}/`), { waitUntil: "networkidle2" });
    report.screenshots.top = await screenshot(page, "01_top.png", true);

    // 2) Login as buyer
    await page.goto(url(`/${LOCALE}/login`), { waitUntil: "networkidle2" });
    report.screenshots.login = await screenshot(page, "02_login.png", false);

    await page.type("#main_person_login", USERNAME, { delay: 10 });
    await page.type("#main_person_password", PASSWORD, { delay: 10 });

    await Promise.all([
      page.click("#main_log_in_button"),
      safeWaitForNavigation(page),
    ]);
    report.screenshots.after_login = await screenshot(page, "03_after_login.png", false);

    // 3) Listing detail
    await page.goto(url(`/${LOCALE}/listings/${LISTING_ID}-${LISTING_SLUG}`), {
      waitUntil: "networkidle2",
    });
    report.screenshots.listing_detail = await screenshot(page, "04_listing_detail.png", true);

    // 4) Try CTA purchase/start flow
    const clicked = await clickByText(page, "このスキルを利用する");
    report.notes.push({ kind: "cta_click", ok: clicked });
    if (clicked) {
      await safeWaitForNavigation(page, 20000);
      await sleep(1500);
      report.screenshots.after_cta = await screenshot(page, "05_after_cta.png", true);
    } else {
      report.issues.push({
        severity: "P0",
        title: "「このスキルを利用する」ボタンが検出できず購入フロー確認ができない",
        evidence: "自動操作でCTA要素を特定できなかった（UI変更/セレクタ変更の可能性）",
        screenshot: "04_listing_detail.png",
      });
    }

    // Detect payment setup warning (best-effort)
    const paymentWarning = await page.evaluate(() => {
      const text = document.body?.innerText || "";
      if (text.includes("決済を設定する")) return "決済を設定する";
      if (text.includes("PayPal")) return "PayPal";
      return null;
    });
    if (paymentWarning) {
      report.issues.push({
        severity: "P0",
        title: "決済未設定により購入フローがブロックされる可能性",
        evidence: `ページ内文言: ${paymentWarning}`,
        screenshot: clicked ? "05_after_cta.png" : "04_listing_detail.png",
      });
    }

    // 5) Open chat and send message (post-CTA attempt)
    const hasChatButton = await page.$('button[aria-label="Open AI chat"]');
    if (hasChatButton) {
      await page.click('button[aria-label="Open AI chat"]');
      await page.waitForSelector('[aria-label="AI Chat"]', { timeout: 15000 });
      report.screenshots.chat_open = await screenshot(page, "06_chat_open.png", true);

      await page.type('textarea[aria-label="Chat message input"]', CHAT_MESSAGE, {
        delay: 10,
      });
      await page.click('button[aria-label="Send message"]');
      await sleep(3000);
      report.screenshots.chat_after_send = await screenshot(
        page,
        "07_chat_after_send.png",
        true
      );

      const messages = await page.evaluate(() => {
        const nodes = Array.from(document.querySelectorAll(".chatPanel__message"));
        const last = nodes[nodes.length - 1];
        return {
          count: nodes.length,
          lastText: last?.textContent?.trim() || null,
        };
      });
      report.notes.push({ kind: "chat_messages", ...messages });
    } else {
      report.issues.push({
        severity: "P0",
        title: "チャット起動ボタンが見つからず、利用フローを確認できない",
        evidence: "button[aria-label=\"Open AI chat\"] が見つからない",
        screenshot: clicked ? "05_after_cta.png" : "04_listing_detail.png",
      });
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

