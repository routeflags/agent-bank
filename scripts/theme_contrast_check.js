/**
 * テーマ配色コントラスト実測スクリプト（Issue #8 / #10 / #15 の検証用）
 *
 * 目的:
 *   コンパイル済み application.css を、実 DOM（layouts/_notifications.haml と
 *   settings/*.haml）を再現したフィクスチャへ適用し、実際の Computed Style から
 *   文字色・実効背景色を解決して WCAG 2.x コントラスト比を数値で実測する。
 *   「見た目で良さそう」ではなく、再現可能な数値で判定するためのレポートツール。
 *
 * 判定:
 *   - body.dark-theme のケースのみ合否判定（閾値 4.5:1）。失敗時は exit 1
 *   - ライト相当（body class なし）は記録のみ。変更前後の差分比較に使う
 *     （ライトテーマは現状到達しないが、非変更の証跡として保存）
 *   - 無効ボタン（.disabled-button）は WCAG 1.4.3 の適用除外のため記録のみ
 *
 * 前提:
 *   bundle exec rails runner scripts/compile_application_css.rb /tmp/application.css
 *
 * Run:
 *   node scripts/theme_contrast_check.js --css /tmp/application.css [--json out.json] [--no-axe]
 */

const fs = require('fs');
const { chromium } = require('playwright');

const DEFAULT_CHROME =
  '/Users/bookair18/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const CHROME = process.env.CHROME_PATH || DEFAULT_CHROME;

// ── 引数 ────────────────────────────────────────────────
const args = process.argv.slice(2);
const readArg = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : null;
};
const CSS_PATH = readArg('--css');
const JSON_PATH = readArg('--json');
const RUN_AXE = !args.includes('--no-axe');
if (!CSS_PATH) {
  console.error('usage: node scripts/theme_contrast_check.js --css <application.css> [--json out.json] [--no-axe]');
  process.exit(2);
}

// ── フィクスチャ ────────────────────────────────────────
// 実 DOM（app/views/layouts/_notifications.haml:16-23 と
// app/views/settings/account.haml / notifications.haml / show.haml）の構造を再現。
// disabled 状態の #delete_account_button は同じ id を重複させて再現する
// （CSS セレクタの :not(.disabled-button) と .disabled-button をそれぞれ検証するため）。
const FLASH_TYPES = ['notice', 'warning', 'success', 'error'];
const ICON = { notice: 'ss-check', warning: 'ss-info', success: 'ss-check', error: 'ss-alert' };
const FLASH_TEXT = {
  notice: 'ようこそ。プロフィールを設定しましょう。',
  warning: 'メンテナンスモード中です。',
  success: '変更を保存しました。',
  error: '入力内容を確認してください。',
};

function flashBlock(type) {
  return `
    <div class="flash-notifications">
      <div class="flash-notification flash-${type}">
        <div class="flash-icon ${ICON[type]}"></div>
        <div class="flash-text">${FLASH_TEXT[type]}</div>
      </div>
    </div>`;
}

function ajaxBlock(type) {
  return `
    <div class="ajax-notification ajax-${type}">
      <div class="ajax-icon ${ICON[type]}"></div>
      <div class="ajax-text">${FLASH_TEXT[type]}</div>
    </div>`;
}

function linkFlashBlock(type) {
  const link = type === 'error' ? '<a class="flash-error-link" href="#">お問い合わせ</a>' : '<a href="#">詳細を確認</a>';
  return `
    <div class="flash-notifications">
      <div class="flash-notification flash-${type}">
        <div class="flash-icon ${ICON[type]}"></div>
        <div class="flash-text">${FLASH_TEXT[type]} ${link}</div>
      </div>
    </div>`;
}

function buildFixture(bodyClass) {
  return `<!doctype html>
<html lang="ja">
<head><meta charset="utf-8"><title>theme contrast check</title></head>
<body ${bodyClass}>
<main class="page-content">
  <div class="wrapper">
    ${FLASH_TYPES.map(flashBlock).join('\n')}
    ${FLASH_TYPES.map(ajaxBlock).join('\n')}
    ${FLASH_TYPES.map(linkFlashBlock).join('\n')}

    <!-- account settings (#account_email_form / #account_password_form / delete)。
         実ページでは「変更」クリックまで display:none（_account-settings.scss）のため、
         クリック後と同じくインライン style で表示状態にして hover 計測する -->
    <div class="account-settings">
      <div class="account-settings-row">
        <form id="account_email_form" class="email-form" style="display: block">
          <button class="send_button_account" id="email_submit" name="button" type="submit">保存</button>
        </form>
        <form id="account_password_form" class="password-form" style="display: block">
          <button class="send_button_account" id="password_submit" name="button" type="submit">保存</button>
        </form>
        <form method="post" action="#">
          <button class="" id="delete_account_button" name="button" type="submit">アカウントを永久に抹消する</button>
        </form>
        <form method="post" action="#">
          <button class="disabled-button" id="delete_account_button" name="button" type="submit" disabled>アカウントを永久に抹消する</button>
        </form>
      </div>
    </div>

    <!-- 汎用のフォーム送信ボタン（devise 系など。Issue #22） -->
    <div class="login-form">
      <form method="post" action="#">
        <input class="button" type="submit" value="ログイン">
      </form>
    </div>

    <div id="person_settings_form" class="left-navi-section settings-section notification-settings">
      <form>
        <button class="send_button_notifications" name="button" type="submit">保存する</button>
      </form>
    </div>
    <div id="person_settings_form" class="left-navi-section settings-section">
      <form>
        <button class="send_button" name="button" type="submit">保存する</button>
      </form>
    </div>
  </div>
</main>
</body>
</html>`;
}

// ── 計測ケース ──────────────────────────────────────────
// min: 4.5 → 合否判定。null → 記録のみ（無効ボタン）
const CASES = [
  { id: 'flash-notice-text', label: '通知 notice 本文', selector: '.flash-notice .flash-text', min: 4.5 },
  { id: 'flash-warning-text', label: '警告 warning 本文（#8）', selector: '.flash-warning .flash-text', min: 4.5 },
  { id: 'flash-success-text', label: '成功 success 本文（#8 点検）', selector: '.flash-success .flash-text', min: 4.5 },
  { id: 'flash-error-text', label: 'エラー error 本文（#8 点検）', selector: '.flash-error .flash-text', min: 4.5 },
  { id: 'ajax-warning-text', label: 'ajax warning 本文（#8）', selector: '.ajax-warning .ajax-text', min: 4.5 },
  { id: 'ajax-success-text', label: 'ajax success 本文（#8 点検）', selector: '.ajax-success .ajax-text', min: 4.5 },
  { id: 'flash-notice-link', label: '通知 notice リンク', selector: '.flash-notice .flash-text a', min: 4.5 },
  { id: 'flash-warning-link', label: '警告 warning リンク', selector: '.flash-warning .flash-text a', min: 4.5 },
  { id: 'flash-success-link', label: '成功 success リンク（#8 点検）', selector: '.flash-success .flash-text a', min: 4.5 },
  { id: 'flash-error-link', label: 'エラー error リンク（#8 点検）', selector: '.flash-error .flash-text a.flash-error-link', min: 4.5 },
  { id: 'email-submit', label: '設定 メール保存 #email_submit（#15）', selector: '#email_submit', min: 4.5 },
  { id: 'generic-submit', label: 'フォーム送信 input[type=submit].button（#22）', selector: 'input[type="submit"].button', min: 4.5 },
  { id: 'password-submit', label: '設定 パスワード保存 #password_submit（#15）', selector: '#password_submit', min: 4.5 },
  { id: 'notifications-submit', label: '設定 通知保存 .send_button_notifications（#15）', selector: '.send_button_notifications', min: 4.5 },
  { id: 'profile-submit', label: '設定 プロフィール保存 .send_button（#15 回帰）', selector: '.settings-section .send_button', min: 4.5 },
  { id: 'delete-account', label: 'アカウント削除 #delete_account_button（#15）', selector: '#delete_account_button:not(.disabled-button)', min: 4.5 },
  { id: 'delete-account-disabled', label: 'アカウント削除（無効時）', selector: '#delete_account_button.disabled-button', min: null },
];

const HOVER_CASES = [
  { id: 'email-submit-hover', label: '設定 メール保存 hover（#15）', selector: '#email_submit', min: 4.5 },
  { id: 'generic-submit-hover', label: 'フォーム送信 hover（#22）', selector: 'input[type="submit"].button', min: 4.5 },
  { id: 'password-submit-hover', label: '設定 パスワード保存 hover（#15）', selector: '#password_submit', min: 4.5 },
  { id: 'notifications-submit-hover', label: '設定 通知保存 hover（#15）', selector: '.send_button_notifications', min: 4.5 },
  { id: 'delete-account-hover', label: 'アカウント削除 hover（#15）', selector: '#delete_account_button:not(.disabled-button)', min: 4.5 },
  { id: 'flash-error-link-hover', label: 'エラー error リンク hover（#8 点検）', selector: '.flash-error .flash-text a.flash-error-link', min: 4.5 },
];

// ── ページ内計測関数（ブラウザ文脈） ────────────────────
const MEASURE_FN = (selector) => {
  const parse = (c) => {
    const m = c.match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(',').map(Number);
    return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1];
  };
  const lum = (rr, gg, bb) => {
    const f = (v) => {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * f(rr) + 0.7152 * f(gg) + 0.0722 * f(bb);
  };
  const el = document.querySelector(selector);
  if (!el) return null;
  const fg = parse(getComputedStyle(el).color);
  if (!fg) return null;
  // 実効背景: 自身から祖先へ半透明を合成していく（既存の a11y_hover_audit.js と同じ方式）
  const chain = [];
  let node = el;
  while (node) {
    const cs = getComputedStyle(node);
    const bg = parse(cs.backgroundColor);
    if (bg && bg[3] > 0) chain.push(bg);
    node = node.parentElement;
  }
  let [r, g, b] = parse(getComputedStyle(document.body).backgroundColor) || [255, 255, 255, 1];
  for (let i = chain.length - 1; i >= 0; i--) {
    const [lr, lg, lb, la] = chain[i];
    r = lr * la + r * (1 - la);
    g = lg * la + g * (1 - la);
    b = lb * la + b * (1 - la);
  }
  const l1 = lum(fg[0], fg[1], fg[2]);
  const l2 = lum(r, g, b);
  const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
  const cs = getComputedStyle(el);
  return {
    fg: `rgb(${fg[0]}, ${fg[1]}, ${fg[2]})`,
    bg: `rgb(${Math.round(r)}, ${Math.round(g)}, ${Math.round(b)})`,
    ratio: +ratio.toFixed(2),
    fontSize: cs.fontSize,
    fontWeight: cs.fontWeight,
  };
};

async function measurePage(page, theme, cases, cssContent) {
  await page.setContent(buildFixture(theme === 'dark' ? 'class="dark-theme"' : ''));
  await page.addStyleTag({ content: cssContent });
  const results = [];
  for (const c of cases) {
    const m = await page.evaluate(MEASURE_FN, c.selector);
    if (!m) {
      results.push({ ...c, theme, state: 'static', pass: c.min === null ? null : false, error: `selector not found: ${c.selector}` });
      continue;
    }
    results.push({ ...c, theme, state: 'static', ...m, pass: c.min === null ? null : m.ratio >= c.min });
  }
  return results;
}

async function measureHover(page, theme, cases, cssContent) {
  await page.setContent(buildFixture(theme === 'dark' ? 'class="dark-theme"' : ''));
  await page.addStyleTag({ content: cssContent });
  const results = [];
  for (const c of cases) {
    try {
      await page.locator(c.selector).first().hover({ timeout: 2000 });
      await page.waitForTimeout(80);
    } catch (e) {
      results.push({ ...c, theme, state: 'hover', pass: false, error: `hover failed: ${e.message.split('\n')[0]}` });
      continue;
    }
    const m = await page.evaluate(MEASURE_FN, c.selector);
    if (!m) {
      results.push({ ...c, theme, state: 'hover', pass: false, error: `selector not found: ${c.selector}` });
      continue;
    }
    results.push({ ...c, theme, state: 'hover', ...m, pass: c.min === null ? null : m.ratio >= c.min });
  }
  return results;
}

// ── 実行 ────────────────────────────────────────────────
(async () => {
  const cssContent = fs.readFileSync(CSS_PATH, 'utf8');
  const browser = await chromium.launch({ headless: true, executablePath: CHROME });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'ja-JP' });
  const page = await context.newPage();

  const dark = [
    ...(await measurePage(page, 'dark', CASES, cssContent)),
    ...(await measureHover(page, 'dark', HOVER_CASES, cssContent)),
  ];
  const light = [await measurePage(page, 'light', CASES, cssContent)];

  // axe-core（color-contrast のみ）を dark フィクスチャで実行
  let axeViolations = [];
  if (RUN_AXE) {
    const { AxeBuilder } = require('@axe-core/playwright');
    await page.setContent(buildFixture('class="dark-theme"'));
    await page.addStyleTag({ content: cssContent });
    const audit = await new AxeBuilder({ page }).withRules(['color-contrast']).analyze();
    axeViolations = audit.violations.flatMap((v) =>
      v.nodes.map((n) => ({ id: v.id, target: n.target.join(' '), summary: n.failureSummary }))
    );
  }

  await browser.close();

  // ── レポート ──
  const lines = [];
  const fmt = (r) =>
    `${r.pass === false ? '❌' : r.pass === null ? '⬜' : '✅'} ${r.label} [${r.state}] fg=${r.fg || '-'} bg=${r.bg || '-'} = ${r.ratio ?? '-'}:1` +
    (r.min ? ` (need ${r.min})` : '') +
    (r.error ? ` ${r.error}` : '');

  lines.push(`# テーマ配色コントラスト実測 (css=${CSS_PATH})`);
  lines.push(`## dark theme (body.dark-theme) — 合否判定: 4.5:1`);
  dark.forEach((r) => lines.push(fmt(r)));
  lines.push(`## light baseline (body class なし) — 記録のみ`);
  light[0].forEach((r) => lines.push(fmt(r)));
  lines.push(`## axe-core color-contrast (dark fixture)`);
  lines.push(axeViolations.length === 0 ? '✅ violations: 0' : `❌ violations: ${axeViolations.length}`);
  axeViolations.forEach((v) => lines.push(`  - ${v.id} @ ${v.target}`));

  console.log(lines.join('\n'));

  const failures = dark.filter((r) => r.pass === false);
  const passCount = dark.filter((r) => r.pass === true).length;
  const recordOnly = dark.filter((r) => r.pass === null).length;
  console.log(`\ndark: pass ${passCount} / fail ${failures.length} / record-only ${recordOnly}`);

  if (JSON_PATH) {
    fs.writeFileSync(
      JSON_PATH,
      JSON.stringify({ css: CSS_PATH, dark, light: light[0], axeViolations }, null, 2) + '\n'
    );
    console.log(`json -> ${JSON_PATH}`);
  }

  if (failures.length || axeViolations.length) process.exit(1);
})();
