/**
 * アクセシビリティ監査スクリプト（axe-core）
 *
 * html-validate（静的 HTML 検証）とは別軸で、Playwright + axe-core による
 * 動的アクセシビリティ監査を各画面で実施し、docs/accessibility-report.md
 * にレポートを出力する。
 *
 * Run: node scripts/a11y_audit.js
 */

const { chromium } = require('playwright');
const { AxeBuilder } = require('@axe-core/playwright');
const fs = require('fs');
const path = require('path');

const BASE = 'http://agent-bank.lvh.me:3000';
const CHROME =
  '/Users/bookair18/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const REPORT = path.join(__dirname, '..', 'docs', 'accessibility-report.md');

const SLUGS = {
  14: 'sakura-raiteinguasisutanto',
  15: 'kodotai-lang-kodosheng-cheng-rebiyu',
  16: 'mizutama-ri-ying-fan-yi',
  17: 'hanako-kasutamasapoto',
  18: 'yuki-rorupureihui-hua',
  19: 'kenzi-detafen-xi',
};

// [name, path, auth?]
const PAGES = [
  ['トップページ', '/', false],
  ['ログイン', '/ja/login', false],
  ['新規登録', '/ja/signup', false],
  ['パスワード再設定', '/ja/people/password/new', false],
  ['購入者プロフィール', '/ja/gourutailangte', false],
  ...Object.entries(SLUGS).map(([id, slug]) => [
    `ペルソナ詳細（${id}）`,
    `/ja/listings/${id}-${slug}`,
    false,
  ]),
  ['メールボックス', '/ja/gourutailangte/inbox', true],
  ['ペルソナ問い合わせフォーム', `/ja/listings/14-${SLUGS[14]}/contact`, true],
  ['ペルソナランキング', '/ja/rankings', false],
  ['ペルソナバトル', '/ja/battles', false],
  ['ドキュメント', '/ja/docs', false],
];

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: CHROME });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    locale: 'ja-JP',
  });
  const page = await context.newPage();

  // 購入者ログイン（auth token はスクリプト先頭で発行）
  const token = process.env.AUDIT_TOKEN;
  if (!token) {
    console.error('AUDIT_TOKEN env is required (login auth token)');
    process.exit(1);
  }
  await page.goto(`${BASE}/?auth=${token}`);
  await page.waitForTimeout(1000);

  const results = [];

  for (const [name, p, needsAuth] of PAGES) {
    const resp = await page.goto(`${BASE}${p}`, { waitUntil: 'networkidle' });
    const status = resp.status();
    if (status !== 200) {
      results.push({ name, path: p, status, violations: [], error: `HTTP ${status}` });
      console.log(`${status} ${name}: skipped (HTTP ${status})`);
      continue;
    }

    // axe 実行（既知の誤検知が多いルールは除外しないが、レビューで精査する）
    const audit = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
      .analyze();

    const violations = audit.violations.map((v) => ({
      id: v.id,
      impact: v.impact,
      help: v.help,
      count: v.nodes.length,
      targets: v.nodes.slice(0, 3).map((n) => n.target.join(' ')),
    }));

    results.push({ name, path: p, status, violations });
    const total = violations.reduce((s, v) => s + v.count, 0);
    console.log(`${status} ${name}: ${violations.length} rules / ${total} nodes`);
  }

  await browser.close();

  // ---- レポート出力 ----
  const ts = new Date().toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' });
  const impactOrder = ['critical', 'serious', 'moderate', 'minor'];
  const totals = {};
  for (const r of results) {
    for (const v of r.violations) {
      totals[v.impact] = (totals[v.impact] || 0) + v.count;
    }
  }

  const lines = [];
  lines.push('# アクセシビリティ監査レポート（axe-core）');
  lines.push('');
  lines.push(`- **実施日時**: ${ts}`);
  lines.push('- **対象**: Agent Bank フロントエンド（日本語版 /ja）');
  lines.push('- **ツール**: axe-core（@axe-core/playwright 11.x）+ Chromium（Playwright）');
  lines.push('- **ルールセット**: wcag2a / wcag2aa / wcag21a / wcag21aa');
  lines.push(`- **対象ページ数**: ${results.length}`);
  const sumStr = impactOrder
    .filter((i) => totals[i])
    .map((i) => `${i}: ${totals[i]}`)
    .join(' / ');
  lines.push(`- **違反合計ノード数**: ${Object.values(totals).reduce((a, b) => a + b, 0)}（${sumStr || 'なし'}）`);
  lines.push('');
  lines.push('## サマリ');
  lines.push('');
  lines.push('| # | ページ | HTTP | 違反ルール数 | 違反ノード数 |');
  lines.push('|---|--------|:----:|-------------:|-------------:|');
  results.forEach((r, i) => {
    const nodes = r.violations.reduce((s, v) => s + v.count, 0);
    lines.push(`| ${i + 1} | ${r.name} | ${r.status} | ${r.violations.length} | ${nodes} |`);
  });
  lines.push('');

  for (const r of results) {
    if (!r.violations.length) continue;
    lines.push(`## ${r.name} (\`${r.path}\`)`);
    lines.push('');
    lines.push('| 深刻度 | ルール | 説明 | 件数 | 対象（抜粋） |');
    lines.push('|--------|--------|------|-----:|-------------|');
    const sorted = [...r.violations].sort(
      (a, b) => impactOrder.indexOf(a.impact) - impactOrder.indexOf(b.impact)
    );
    for (const v of sorted) {
      const targets = v.targets.map((t) => `\`${t.replace(/\|/g, '\\|')}\``).join('<br>');
      lines.push(`| ${v.impact} | \`${v.id}\` | ${v.help} | ${v.count} | ${targets} |`);
    }
    lines.push('');
  }

  lines.push('## 再実行方法');
  lines.push('');
  lines.push('```bash');
  lines.push('AUDIT_TOKEN=<buyer login token> node scripts/a11y_audit.js');
  lines.push('```');
  lines.push('');

  fs.writeFileSync(REPORT, lines.join('\n'), 'utf8');
  console.log(`\nReport written: ${REPORT}`);
})();
