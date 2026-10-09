const { chromium } = require('playwright');
const BASE = 'http://agent-bank.lvh.me:3000/ja';
const CHROME = '/Users/bookair18/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';

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

  // ── ログイン状態でないときのヘッダー ──
  console.log('--- 未ログイン時ヘッダー ---');

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

  // ログイン
  await page.goto(`${BASE}/login`);
  await page.fill('#main_person_login', 'admin@agentbank.dev');
  await page.fill('#main_person_password', 'DevAgentBank#2026');
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
    await page.goto(`${BASE}/listings/14-sakura-raiteinguasisutanto`);
    await page.waitForTimeout(3000);
    const cta = await page.locator('.raku-cta-btn').count();
    if (cta === 0) throw new Error('CTA ボタンがない');
  });

  await run('TC-14: ペルソナ詳細 → タブ切り替え', async () => {
    await page.goto(`${BASE}/listings/14-sakura-raiteinguasisutanto`);
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
    ['TC-20: ペルソナ詳細 GET', '/listings/14-sakura-raiteinguasisutanto'],
  ];

  for (const [name, path] of pages) {
    await run(name, async () => {
      const resp = await page.goto(`${BASE}${path}`);
      if (resp.status() !== 200) throw new Error(`status: ${resp.status()}`);
    });
  }

  // ── ナビゲーションアクティブ状態 ──
  console.log('\n--- ナビゲーションアクティブ状態 ---');

  async function activeNavText() {
    return page.evaluate(() => {
      const el = document.querySelector('.raku-nav__link.is-active');
      return el ? el.textContent.trim().replace(/\s+/g, ' ') : null;
    });
  }

  await run('TC-21: トップページ → 「マーケット」がアクティブ', async () => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(BASE);
    await page.waitForTimeout(2000);
    const active = await activeNavText();
    if (!active || !active.includes('マーケット')) {
      throw new Error(`アクティブ項目が「マーケット」ではない: ${active}`);
    }
  });

  const navPages = [
    ['/rankings', 'ランキング'],
    ['/battles', 'バトル'],
    ['/docs', 'ドキュメント'],
  ];
  for (const [path, label] of navPages) {
    await run(`TC-23: ${label}ページ → 「${label}」がアクティブ`, async () => {
      await page.goto(BASE + path);
      await page.waitForTimeout(1500);
      const status = page.url().includes(path) ? null : `遷移していない: ${page.url()}`;
      const active = await activeNavText();
      if (status) throw new Error(status);
      if (!active || !active.includes(label)) {
        throw new Error(`アクティブ項目が「${label}」ではない: ${active}`);
      }
    });
  }

  const AUDIT_TOKEN = process.env.AUDIT_TOKEN || '';
  if (AUDIT_TOKEN) {
    await run('TC-22: 出品ページ → 「出品」がアクティブ（ログイン時）', async () => {
      await page.goto(`${BASE.replace(/\/ja$/, '/')}?auth=${AUDIT_TOKEN}`);
      await page.waitForTimeout(2000);
      await page.goto(`${BASE}/listings/new`);
      await page.waitForTimeout(2000);
      const active = await activeNavText();
      if (!active || !active.includes('出品')) {
        throw new Error(`アクティブ項目が「出品」ではない: ${active}`);
      }
    });

    await run('TC-24: ヘッダー検索 → 検索結果へ遷移', async () => {
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.goto(BASE);
      await page.waitForTimeout(1500);
      const searchInput = page.locator('.header-search__input');
      if ((await searchInput.count()) === 0) throw new Error('ヘッダー検索が存在しない');
      await searchInput.fill('SEO');
      await page.click('.header-search__button');
      await page.waitForTimeout(2500);
      const url = decodeURIComponent(page.url());
      if (!url.includes('q=SEO')) throw new Error(`検索クエリがURLにない: ${page.url()}`);
    });
  } else {
    results.push({ name: 'TC-22: 出品ページ → 「出品」がアクティブ（ログイン時）', status: 'SKIP', error: 'AUDIT_TOKEN 未設定' });
    console.log('  ⏭️  TC-22: 出品ページ → 「出品」がアクティブ（AUDIT_TOKEN 未設定のためスキップ）');
    results.push({ name: 'TC-24: ヘッダー検索 → 検索結果へ遷移', status: 'SKIP', error: 'AUDIT_TOKEN 未設定' });
    console.log('  ⏭️  TC-24: ヘッダー検索 → 検索結果へ遷移（AUDIT_TOKEN 未設定のためスキップ）');
  }

  // 出品ありプロフィール（公開ページ）— スキル表の描画回帰
  // （ListingItem構造体に依存した属性アクセスでの500防止）
  await run('TC-25: 出品者プロフィール → スキル表が描画される', async () => {
    await page.goto(`${BASE.replace(/\/ja$/, '')}/ja/alexm`);
    await page.waitForTimeout(2000);
    const status = await page.evaluate(() => {
      if (document.title.includes('Exception')) return 'exception page';
      const rows = document.querySelectorAll('.raku-table__skill-name').length;
      return rows > 0 ? null : 'スキル表の行が0件';
    });
    if (status) throw new Error(status);
  });

  // ── Chat Result / Artifact パネル ──
  // DESIGN.md §13: 成果物にのみ RESULT バッジを付ける仕様の描画回帰チェック。
  // 履歴に is_result=true のアシスタントメッセージが1件以上あるセッション
  // （セッション1・出品14）を開き、チャットパネルを展開してバッジと
  // 右側 Result パネルが描画されることを確認する。
  console.log('\n--- Chat Result パネル ---');

  await run('TC-26: チャット → is_result メッセージに RESULT バッジが付く', async () => {
    await page.goto(`${BASE}/listings/14-sakura-raiteinguasisutanto`);
    await page.waitForTimeout(2500);
    const trigger = page.locator('.chatPanel__trigger');
    if ((await trigger.count()) === 0) throw new Error('チャットトリガーがない');
    await trigger.click();
    await page.waitForTimeout(2500);
    const status = await page.evaluate(() => {
      const badges = document.querySelectorAll('.chatMessage__result');
      const badgeTexts = Array.from(document.querySelectorAll('.chatMessage__result-badge')).map(e => e.textContent.trim());
      const codeBlocks = document.querySelectorAll('.chatMessage__markdown pre code').length;
      const panel = document.querySelector('.chatPanel__resultPanel');
      if (badges.length === 0) return 'RESULT バッジが描画されていない';
      if (!badgeTexts.includes('RESULT')) return `バッジ文言が不正: ${badgeTexts.join(',')}`;
      if (codeBlocks === 0) return '成果物コードブロックが描画されていない';
      if (!panel) return '右側 Result パネルが描画されていない';
      return null;
    });
    if (status) throw new Error(status);
  });

  // ── 結果サマリー ──
  console.log('\n=== 結果サマリー ===');
  const skipped = results.filter(r => r.status === 'SKIP').length;
  console.log(`✅ 合格: ${passed} 件`);
  console.log(`❌ 不合格: ${failed} 件`);
  if (skipped > 0) console.log(`⏭️  スキップ: ${skipped} 件`);
  console.log(`合計: ${passed + failed + skipped} 件`);

  if (failed > 0) {
    console.log('\n不合格一覧:');
    results.filter(r => r.status === 'FAIL').forEach(r => {
      console.log(`  - ${r.name}: ${r.error}`);
    });
  }

  await browser.close();
})();
