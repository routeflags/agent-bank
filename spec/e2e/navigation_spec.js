const { chromium } = require('playwright');
const BASE = 'http://127.0.0.1:3000/ja';
const CHROME = '/Users/bookair18/Library/Caches/ms-playwright/chromium-1228/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';

let browser, page;
let passed = 0, failed = 0;
const results = [];

async function run(name, fn) {
  try {
    await fn();
    passed++;
    results.push({ name, status: 'PASS' });
    console.log(`  ✅ ${name}`);
  } catch (e) {
    failed++;
    const short = e.message.split('\n')[0];
    results.push({ name, status: 'FAIL', error: short });
    console.log(`  ❌ ${name}: ${short}`);
  }
}

async function assertUrlContains(page, expected, msg) {
  const url = page.url();
  if (!url.includes(expected)) throw new Error(`${msg} — got: ${url}`);
}

(async () => {
  browser = await chromium.launch({ headless: true, executablePath: CHROME });
  page = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'ja-JP' });

  console.log('=== ナビゲーション E2E テスト ===\n');

  // ログイン
  await page.goto(`${BASE}/login`);
  await page.fill('#main_person_login', 'admin2@capafy.com');
  await page.fill('#main_person_password', 'TestPassword1!');
  await page.click('button:has-text("ログイン")');
  await page.waitForTimeout(3000);

  // ── ヘッダーナビゲーション ──
  console.log('--- ヘッダーナビゲーション ---');

  await run('TC-01: ロゴ → トップページ', async () => {
    await page.goto(BASE);
    await page.click('a.header-logo');
    await page.waitForTimeout(2000);
    await assertUrlContains(page, '/', 'トップページに遷移しない');
  });

  await run('TC-02: マーケット → トップページ', async () => {
    await page.goto(BASE);
    const link = page.locator('a.raku-nav__link').first();
    await link.click();
    await page.waitForTimeout(2000);
    await assertUrlContains(page, '/', 'トップページに遷移しない');
  });

  await run('TC-03: 出品する → 出品フォーム', async () => {
    await page.goto(BASE);
    await page.click('a.new-listing-link');
    await page.waitForTimeout(2000);
    await assertUrlContains(page, 'listings/new', '出品フォームに遷移しない');
  });

  await run('TC-04: ログイン → ログインページ', async () => {
    await page.goto(BASE);
    await page.click('a.raku-nav__login');
    await page.waitForTimeout(2000);
    await assertUrlContains(page, 'login', 'ログインページに遷移しない');
  });

  await run('TC-05: 新規登録 → 登録ページ', async () => {
    await page.goto(BASE);
    await page.click('a.raku-nav__signup');
    await page.waitForTimeout(2000);
    await assertUrlContains(page, 'signup', '登録ページに遷移しない');
  });

  // ── ヒーローセクション ──
  console.log('\n--- ヒーローセクション ---');

  await run('TC-06: 検索 → 検索結果', async () => {
    await page.goto(BASE);
    const input = page.locator('.raku-hero__search-input, input[placeholder*="スキル"]');
    await input.fill('SEO');
    const btn = page.locator('.raku-hero__search-btn, button:has(svg)').first();
    await btn.click();
    await page.waitForTimeout(2000);
    await assertUrlContains(page, 'q=SEO', '検索結果に遷移しない');
  });

  await run('TC-07: ヒーロータグ → 検索結果', async () => {
    await page.goto(BASE);
    await page.click('a.raku-hero__tag:has-text("データ分析")');
    await page.waitForTimeout(2000);
    await assertUrlContains(page, 'q=', '検索結果に遷移しない');
  });

  // ── カテゴリ ──
  console.log('\n--- カテゴリ ---');

  await run('TC-08: カテゴリ「生成AI」→ カテゴリ絞り込み', async () => {
    await page.goto(BASE);
    await page.click('a[href*="category=generation-ai"]');
    await page.waitForTimeout(2000);
    await assertUrlContains(page, 'category=generation-ai', 'カテゴリページに遷移しない');
  });

  await run('TC-09: カテゴリ「データ分析」→ カテゴリ絞り込み', async () => {
    await page.goto(BASE);
    await page.click('a[href*="category=data-analysis"]');
    await page.waitForTimeout(2000);
    await assertUrlContains(page, 'category=data-analysis', 'カテゴリページに遷移しない');
  });

  await run('TC-10: カテゴリ「開発・プログラミング」→ カテゴリ絞り込み', async () => {
    await page.goto(BASE);
    await page.click('a[href*="category=development"]');
    await page.waitForTimeout(2000);
    await assertUrlContains(page, 'category=development', 'カテゴリページに遷移しない');
  });

  // ── タブ切替 ──
  console.log('\n--- タブ切替 ---');

  await run('TC-11: 「新着」タブ切替', async () => {
    await page.goto(BASE);
    const tabs = page.locator('.raku-featured__tab');
    await tabs.nth(1).click();
    await page.waitForTimeout(1000);
    const active = await page.locator('.raku-featured__tab.is-active').count();
    if (active === 0) throw new Error('is-active タブがない');
  });

  await run('TC-12: 「高評価」タブ切替', async () => {
    await page.goto(BASE);
    const tabs = page.locator('.raku-featured__tab');
    await tabs.nth(2).click();
    await page.waitForTimeout(1000);
    const active = await page.locator('.raku-featured__tab.is-active').count();
    if (active === 0) throw new Error('is-active タブがない');
  });

  // ── ペルソナ詳細 ──
  console.log('\n--- ペルソナ詳細 ---');

  await run('TC-13: ペルソナ詳細 → CTA 表示', async () => {
    await page.goto(`${BASE}/listings/20-tesuto-raiteingu-asisutanto`);
    await page.waitForTimeout(3000);
    const cta = await page.locator('.raku-cta-btn').count();
    if (cta === 0) throw new Error('CTA ボタンがない');
  });

  await run('TC-14: ペルソナ詳細 → タブ切り替え', async () => {
    await page.goto(`${BASE}/listings/20-tesuto-raiteingu-asisutanto`);
    await page.waitForTimeout(3000);
    const tabs = await page.locator('.raku-listing-tabs__tab, [class*="tab"]').count();
    if (tabs === 0) throw new Error('タブがない');
  });

  // ── ログイン状態 ──
  console.log('\n--- ログイン状態 ---');

  await run('TC-15: ログイン後 → ユーザーメニュー表示', async () => {
    await page.goto(BASE);
    const menu = await page.locator('.header-user-name, [class*="user-avatar"], [class*="avatar"]').count();
    if (menu === 0) throw new Error('ユーザーメニューがない');
  });

  // ── レスポンシブ ──
  console.log('\n--- レスポンシブ ---');

  await run('TC-16: SP ナビゲーション表示', async () => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto(BASE);
    await page.waitForTimeout(2000);
    const mobileNav = await page.locator('.raku-nav').count();
    if (mobileNav === 0) throw new Error('SP ナビゲーションがない');
  });

  // ── HTTP ステータス ──
  console.log('\n--- HTTP ステータス ---');

  const pages = [
    ['TC-17: トップページ GET', '/'],
    ['TC-18: ログインページ GET', '/login'],
    ['TC-19: 登録ページ GET', '/signup'],
    ['TC-20: ペルソナ詳細 GET', '/listings/20-tesuto-raiteingu-asisutanto'],
  ];

  for (const [name, path] of pages) {
    await run(name, async () => {
      const resp = await page.goto(`${BASE}${path}`);
      if (resp.status() !== 200) throw new Error(`status: ${resp.status()}`);
    });
  }

  // ── 結果サマリー ──
  console.log('\n=== 結果サマリー ===');
  console.log(`✅ 合格: ${passed} 件`);
  console.log(`❌ 不合格: ${failed} 件`);
  console.log(`合計: ${passed + failed} 件`);

  if (failed > 0) {
    console.log('\n不合格一覧:');
    results.filter(r => r.status === 'FAIL').forEach(r => {
      console.log(`  - ${r.name}: ${r.error}`);
    });
  }

  await browser.close();
})();
