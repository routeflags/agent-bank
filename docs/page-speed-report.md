# PageSpeed / Lighthouse 実測レポート

実測日: 2026-10-08 / 対象: 開発サーバー `http://agent-bank.lvh.me:3000`（Puma dev・アセット非圧縮）
ツール: Lighthouse 13.5.0（ローカルChrome headless、Google PSI APIは社内ドメイン到達不可のためローカル実行）

## スコアサマリ

| ページ | Perf | A11y | Best Practices | SEO |
|---|---|---|---|---|
| `/ja`（ホーム・モバイル4G） | 54 | 98→**100*** | 78† | 69† |
| `/ja/listings/14`（出品+チャット・モバイル4G） | 33 | 98 | 78† | 69† |
| `/ja`（ホーム・デスクトップ） | **96** | 98 | 78† | 69† |

\* `<main>` ランドマーク修正後（本レポートと同じコミット）。† は開発環境由来（下記）。

## 主要メトリクス

| 指標 | home mobile | listing mobile | home desktop |
|---|---|---|---|
| FCP | 1.9s | 16.4s | 0.4s |
| LCP | 19.5s | 17.7s | 1.0s |
| TBT | 510ms | 1,000ms | 100ms |
| CLS | 0 | 0 | 0 |

CLS=0は全ページ良好。モバイルの低スコアは主に開発サーバーのTTFB（〜980ms・シングルスレッドPuma+debugモード）と4Gスロットリングの複合によるもので、デスクトップ96が実装品質の目安。

## コード分割後の再計測（2026-10-08 実施）

webpackエントリ分割（vendor / common / sections / アプリ別）+ 本番minifyビルド導入後の同一条件再計測:

| 指標 | home mobile 前→後 | listing mobile 前→後 |
|---|---|---|
| Performance | 54 → **69** | 33 → **79** |
| LCP | 19.5s → 6.8s | 17.7s → **5.4s** |
| TBT | 510ms → **80ms** | 1,000ms → **40ms** |
| FCP | 1.9s → 3.4s | 16.4s → **1.7s** |
| Accessibility | 98 → **100** | 98 → **100** |
| 未使用JS削減見込み | 813KiB → 616KiB | 806KiB → 545KiB |

残る最大の未使用JSは vendor-bundle（react等1.15MB・全ページ共通ロード）。次段階は vendor のアプリ別再分割。
バンドル配信は `ClientAssetsHelper`（vendor + common + sections + アプリ別、未指定ページは従来のフルバンドルfallback）。

## 判明した改善ポイント

1. **未使用JavaScript約813KiB**（webpackが全機能を単一バンドルに同梱）— 本番影響大。チャット/管理/オンボーディング等の領域別コード分割が次の一手。
2. **未使用CSS約82KiB・CSS非圧縮約50KiB** — devは非圧縮のため本番では縮小。同梱CSSの圧縮・不要分の分離を検討。
3. **`<main>` ランドマーク欠落（a11y98→100で解消）** — `layouts/application.haml` / `react_page.haml` のコンテンツ領域を `<main>` 化（本コミットで修正）。
4. **preload警告**（`application.css`がpreload後に未使用扱い）— Rails8 sprocketsの自動preloadヘッダ運用。実害は「読み込み警告のみ」でCSS自体は適用されている。ヘッダ無効化の要否は本番計測後に判断。

## 開発環境由来と判定した項目（本番では対応不要/別途確認）

- **HTTPS系（is-on-https / redirects-http）**: devはHTTP。本番は `EnforceSsl` ミドルウェアがHTTPS強制。
- **robots（SEO69の `is-crawlable`）**: `RobotsGenerator` が環境依存でdevは `Disallow: /`（正しい開発運用）。本番は許可+`/*auth$` 等の除外ルールを配信。
- **source maps欠落（valid-source-maps）**: 本番バンドルは意図的に非公開。必要ならhidden sourcemapを別配信。
- **sitemap.xml 404**: devでは未生成。admin2のSEO管理（sitemap-and-robots）で本番公開可。

## セキュリティヘッダ（curl実測）

- あり: `X-Frame-Options: SAMEORIGIN` / `X-Content-Type-Options: nosniff` / `Referrer-Policy: strict-origin-when-cross-origin`
- なし: CSP / HSTS / Permissions-Policy（HSTSは本番HTTPS運用時に、CSPは将来の hardening 案）

## 推奨ロードマップ

1. （影響大）webpack コード分割で未使用JSを削減
2. （中）本番相当環境（assets precompiled + Puma workers）での再計測
3. （小）CSP/HSTS の本番導入検討
4. （小）preloadヘッダ運用の見直し判断
