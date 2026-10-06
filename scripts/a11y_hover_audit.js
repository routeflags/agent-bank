const { chromium } = require('playwright');
const BASE = 'http://agent-bank.lvh.me:3000';
const CHROME =
  '/Users/bookair18/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';

async function auditPage(page, label) {
  const n = await page.evaluate(() => {
    const els = [...document.querySelectorAll('a, button, input[type="submit"], .toggle')];
    let i = 0;
    for (const el of els) {
      const r = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      if (r.width < 4 || r.height < 4 || cs.visibility === 'hidden' || cs.display === 'none') continue;
      if (!el.textContent.trim() && el.getAttribute('aria-label') === null) continue;
      el.setAttribute('data-hp', String(i++));
    }
    return i;
  });

  const failures = [];
  let checked = 0;
  for (let i = 0; i < n; i++) {
    const sel = `[data-hp="${i}"]`;
    try { await page.locator(sel).first().hover({ timeout: 1500, force: true }); } catch (e) { continue; }
    await page.waitForTimeout(200);
    const res = await page.evaluate((s) => {
      const e = document.querySelector(s);
      if (!e) return null;
      const lum = (rr, gg, bb) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(rr) + 0.7152 * f(gg) + 0.0722 * f(bb); };
      const parse = (c) => { const m = c.match(/rgba?\(([^)]+)\)/); if (!m) return null; const p = m[1].split(',').map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; };
      const candidates = [];
      const selfText = [...e.childNodes].some((nd) => nd.nodeType === 3 && nd.textContent.trim());
      if (selfText) candidates.push(e);
      for (const d of e.querySelectorAll('*')) {
        if ([...d.childNodes].some((nd) => nd.nodeType === 3 && nd.textContent.trim())) candidates.push(d);
      }
      const results = [];
      let imageBg = false;
      for (const c of candidates.slice(0, 6)) {
        const fg = parse(getComputedStyle(c).color);
        if (!fg || fg[3] < 0.5) continue;
        const chain = [];
        let nn = c;
        while (nn) {
          const cs2 = getComputedStyle(nn);
          if (cs2.backgroundImage && cs2.backgroundImage !== 'none') imageBg = true;
          const bg = parse(cs2.backgroundColor);
          if (bg && bg[3] > 0) chain.push(bg);
          nn = nn.parentElement;
        }
        let [r, g, b] = parse(getComputedStyle(document.body).backgroundColor) || [255, 255, 255, 1];
        for (let k = chain.length - 1; k >= 0; k--) {
          const [lr, lg, lb, la] = chain[k];
          r = lr * la + r * (1 - la); g = lg * la + g * (1 - la); b = lb * la + b * (1 - la);
        }
        const l1 = lum(fg[0], fg[1], fg[2]), l2 = lum(r, g, b);
        const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
        const cs3 = getComputedStyle(c);
        const fs = parseFloat(cs3.fontSize), fw = parseInt(cs3.fontWeight) || 400;
        const large = fs >= 24 || (fs >= 18.66 && fw >= 700);
        results.push({ text: c.textContent.trim().slice(0, 20), fg: `rgb(${fg[0]},${fg[1]},${fg[2]})`, bg: `rgb(${Math.round(r)},${Math.round(g)},${Math.round(b)})`, ratio: +ratio.toFixed(2), need: large ? 3 : 4.5, fs, fw });
      }
      const cls = (e.className && typeof e.className === 'string') ? e.className.trim().split(/\s+/).slice(0, 4).join('.') : '';
      return { results, imageBg, el: e.tagName.toLowerCase() + (e.id ? '#' + e.id : '') + (cls ? '.' + cls : ''), html: e.outerHTML.slice(0, 110) };
    }, sel);
    if (!res || !res.results || !res.results.length) continue;
    checked++;
    for (const rr of res.results) {
      if (rr.ratio < rr.need) failures.push({ el: res.el, hoverBgImage: res.imageBg, ...rr });
    }
  }
  console.log(`\n=== ${label}: checked ${checked} ===`);
  if (!failures.length) { console.log('  ✅ all pass'); return 0; }
  const seen = new Set();
  let count = 0;
  for (const f of failures) {
    const key = f.el + '|' + f.fg + '|' + f.bg + '|' + f.ratio;
    if (seen.has(key)) continue;
    seen.add(key); count++;
    console.log(`  ❌ ${f.el}  "${f.text}" fg=${f.fg} on ${f.bg} = ${f.ratio}:1 (need ${f.need}) ${f.fs}px/${f.fw}${f.hoverBgImage ? ' [image-bg]' : ''}`);
  }
  return count;
}

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: CHROME });
  const token = process.env.AUDIT_TOKEN;
  let total = 0;

  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'ja-JP' });
  const page = await ctx.newPage();
  await page.goto(BASE + '/?auth=' + token, { waitUntil: 'networkidle' });
  await page.waitForTimeout(400);
  total += await auditPage(page, 'トップ（ログイン中）');

  // real listing detail from grid
  const href = await page.evaluate(() => {
    const a = document.querySelector('.fluid-thumbnail-grid-image-item-link, .home-fluid-thumbnail-grid a[href*="/listings/"], a[href*="/l/"]');
    return a ? a.getAttribute('href') : null;
  });
  if (href) {
    await page.goto(BASE + href, { waitUntil: 'networkidle' });
    await page.waitForTimeout(300);
    total += await auditPage(page, 'ペルソナ詳細 (' + href + ')');
  }

  await page.goto(BASE + '/ja/people/pTRjZXZwIWlAMwb_7wFjMQ', { waitUntil: 'networkidle' });
  await page.waitForTimeout(300);
  total += await auditPage(page, 'プロフィール');

  await page.goto(BASE + '/ja/inbox', { waitUntil: 'networkidle' });
  await page.waitForTimeout(300);
  total += await auditPage(page, 'メールボックス');

  const ctx2 = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'ja-JP' });
  const page2 = await ctx2.newPage();
  await page2.goto(BASE + '/', { waitUntil: 'networkidle' });
  await page2.waitForTimeout(400);
  total += await auditPage(page2, 'トップ（匿名）');

  const ctx3 = await browser.newContext({ viewport: { width: 375, height: 812 }, locale: 'ja-JP', isMobile: true, hasTouch: true });
  const page3 = await ctx3.newPage();
  await page3.goto(BASE + '/?auth=' + token, { waitUntil: 'networkidle' });
  await page3.waitForTimeout(400);
  total += await auditPage(page3, 'モバイル 375px');

  console.log(`\nTOTAL unique hover failures: ${total}`);
  await browser.close();
})();
