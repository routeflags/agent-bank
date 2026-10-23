# Issue #21 webpack 分割ビルド後のレガシー CSS 修正計画

## 目的

webpack のクリーンビルドで生成されない `app-bundle.css` への参照を解消し、
React アプリ未提供ページと旧 `react_page` レイアウトが、実際に生成される最新の
`sections-bundle.css` を読み込んで正常応答する状態にする。

## 調査根拠

- `grep` / ファイル読解: `ClientAssetsHelper#react_bundle_css_tags` と
  `layouts/react_page.haml` が `app-bundle` を参照していることを確認した。
- `grep`: `layouts/react_page.haml` は `HomepageController` の検索ページで現役で
  あることを確認した。
- webpack 設定読解: `sections` cacheGroup が
  `client/app/(components|assets)` を `sections` chunk に集約することを確認した。
- Node 18.16.0 で `npm run clean` と development webpack build を実行し、
  `sections-bundle.css` は生成され、`app-bundle.css` は生成されないことを実測した。
- MCP / プロジェクト固有スキルは当環境で提供されていないため、ファイル検索・読解、
  Researcher / Plan Architect 相当のサブエージェントレビューで代替する。

## 判断

生成側を変更せず、参照側を `sections-bundle.css` のみに合わせる。
現在の全コンポーネント CSS が既に `sections` chunk に集約されているため、
空の CSS を生成するためのダミー import や cacheGroup 再設計を加えるより変更が小さく、
古い `app-bundle.css` への依存も確実に除去できる。

## BDD タスク

- [x] **レガシーページの CSS 解決**
  - Given: React アプリが `provide_react_app` で指定されていない
  - When: 共通 head が CSS タグを生成する
  - Then: `sections-bundle.css` だけを参照し、生成されない `app-bundle.css` を参照しない
  - 例: `GET /ja/login` はクリーンビルド後に 200 を返す

- [x] **現役旧 React レイアウトの CSS 解決**
  - Given: 検索ページが `layouts/react_page.haml` を使用する
  - When: head を描画する
  - Then: `react_page/styles.css` と `sections-bundle.css` を参照し、
    `app-bundle.css` は参照しない

- [x] **React 分割バンドルの維持**
  - Given: `topbar` 等の React アプリが指定される
  - When: JS/CSS タグを生成する
  - Then: CSS は `sections-bundle`、JS は vendor / common / sections /
    per-app（必要時 vendor_dates）を従来どおり読み込む
  - エッジケース: 複数アプリ指定時も各 per-app bundle を一度ずつ列挙する

- [x] **不要設定の整理**
  - Given: webpack が `app-bundle.css` を生成しない
  - When: Sprockets の precompile 対象を確認する
  - Then: 不要な `app-bundle.css` 指定を削除し、生成される
    `sections-bundle.css` は維持する

- [x] **回帰テスト**
  - helper spec で、React アプリ未指定・指定ありの CSS/JS タグ契約を確認する
  - request spec で `/ja/login` が 200、HTML が `sections-bundle.css` を参照し、
    `app-bundle.css` を参照せず、参照元ファイルが実在することを確認する
  - 旧 React レイアウトの直接参照について静的な契約テストを設ける

## 再現・検証手順

1. `nodenv exec npm run clean`
2. `bundle exec rake i18n:js:export && bundle exec rake js:routes`
3. `cd client && nodenv exec npx webpack --mode=development --config webpack.client.config.js`
4. `test ! -f app/assets/webpack/app-bundle.css`
5. `test -f app/assets/webpack/sections-bundle.css`
6. 修正前後で一時サーバー（常設しない）または request spec から
   `GET /ja/login` の応答と HTML 内 stylesheet href を確認する
7. 追加した対象 spec、続いて `bundle exec rspec` 全体を実行する

## 受入条件

- クリーンビルド後に `/ja/login` が 200
- レガシーページが生成済みの最新 `sections-bundle.css` を参照
- `app-bundle.css` のビュー・helper・precompile 参照がゼロ
- React ページの vendor / common / sections / per-app 読み込みが維持される
- 回帰テストおよび全 RSpec に新規失敗がない

---

## 実装結果（2026-10-23）

### 計画からの変更点

計画時点で把握していなかった参照を 1 件追加で修正した。

- `app/views/landing_page/landing_page.erb:134`（CLP のトップバー有効時のみ描画）も
  `asset_path('app-bundle', type: :stylesheet)` を直接参照しており、`landing_pages_spec`
  13 件 + `landing_page_controller_spec` 4 件が失敗していた。同じルール（生成される
  `sections-bundle` のみ参照）で置換した。JS 側の `app-bundle`（= `app-bundle.js`）は
  生成されるため変更していない。

### 変更ファイル

| ファイル | 変更 |
|---|---|
| `app/helpers/client_assets_helper.rb` | `react_bundle_css_tags` を全ケースで `sections-bundle` のみに。ヘッダーコメント更新 |
| `app/views/layouts/react_page.haml` | 直接参照から `app-bundle` を削除（`react_page/styles` は維持） |
| `app/views/landing_page/landing_page.erb` | 同上（CSS のみ） |
| `config/application.rb` | precompile リストから `app-bundle.css` を削除 |
| `config/initializers/assets.rb` | 同上 |
| `spec/helpers/client_assets_helper_spec.rb`（新規） | 参照バンドル名の契約テスト（アセット実体に依存しない） |
| `spec/requests/legacy_page_assets_spec.rb`（新規） | `/login` が 200 かつ HTML が `sections-bundle` を参照し `app-bundle` を含まないこと |

### 検証（実測）

検証環境はクリーンビルド相当（`app/assets/webpack` から `app-bundle.css` を削除した状態）を再現した。

| 手順 | 結果 |
|---|---|
| 修正前の helper spec（`sections-bundle` のみ期待） | 失敗（実際は `app-bundle`, `sections-bundle` を要求） |
| 修正前の `/login`（request spec） | **500**（`The asset "app-bundle.css" is not present in the asset pipeline`） |
| 修正後の同 2 本 | **6 examples, 0 failures** |
| 修正後の landing 系（`landing_pages_spec` / `landing_page_controller_spec` / `listings_controller_spec` / `listing_images_controller_spec`） | **45 examples, 0 failures** |
| 全件（修正前ベースライン / 修正後、同一環境） | 失敗 **143 → 66 件**（資産参照起因 79 件を解消、新規 0 件） |

補足（環境依存の flaky）: 全件実行時は PayPal 系（FakePal ストア）や mailer / settings 等が
実行順序で入れ替わりに失敗する。isolated 実行（`settings_controller_spec` / `person_mailer_spec` /
`listings_controller_spec` / `manage_users_controller_spec`）では **65 examples, 0 failures**。
本変更は CSS 参照のみで、これらの領域には触れていない。

### 補足（ローカル環境の後始末）

メインのチェックアウトには古い `app/assets/webpack/app-bundle.css`（2026-10-08）が残っている。
参照が無くなったため害はないが、`cd client && npm run clean` で掃除できる。

