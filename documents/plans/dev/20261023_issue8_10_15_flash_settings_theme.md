# Issue #8 / #10 / #15: フラッシュ通知の文字コントラストと設定画面ボタンのダークテーマ整合 — 実装計画

作成日: 2026-10-23
対象: routeflags/agent-bank（AI ペルソナマーケットプレイス「楽市楽問」/ Lamprey）
ブランチ: `feat/agent-bank`
関連 Issue: routeflags/agent-bank#8, #10, #15
関連ドキュメント: `DESIGN.md`、`docs/scss-coding-guidelines.md`、`docs/accessibility-report.md`

---

## 1. 背景と現状（コードで確認した事実）

| # | 事実 | 根拠 |
|---|------|------|
| F1 | ダークテーマは全ページ固定（`application.haml` が常に `%body.dark-theme` を出力し、ライトテーマ切替は存在しない） | `app/views/layouts/application.haml:8` |
| F2 | `.flash-notice` / `.flash-warning` の背景は `$highlight` = `#e8e8e8`（両テーマ共通） | `app/assets/stylesheets/partials/_flash.scss:29-34`、`app/assets/stylesheets/mixins/default-colors.scss:39` |
| F3 | `.flash-success` の背景は `$light-green` = `#b2d9ab`、文字色指定なし | `_flash.scss:35-39`（コンパイル後 `background: #b2d9ab`） |
| F4 | `.flash-error` は `color: white; background: $error-red` = `#c81f1f`（文字色は明示済み） | `_flash.scss:41-46`（コンパイル後 `color: white`） |
| F5 | ダークテーマの本文色は `--text-primary` = `#ffffff`。フラッシュ本文はこれを継承する | `themes/_dark_variables.scss:22,55-57`、コンパイル後 `body.dark-theme { color: var(--text-primary) }` |
| F6 | 文字色パッチは `.flash-notice .flash-text` / `.ajax-notice .ajax-text` のみ。**warning / success は未対応**（#8 の原因） | `components/_raku_utils.scss:115-120`、コンパイル後 CSS に warning/success の `.flash-text` パッチが存在しないことを確認 |
| F7 | 通知内リンクは notice / warning のみ対応（`#1f6f60` + 下線）。error のリンクは `body.dark-theme a`（teal `#59b3a2`）が `.flash-error-link`（`#ccc`）に勝ち、赤背景 `#c81f1f` 上で **2.3:1** 相当になっている | `_raku_utils.scss:130-146`、`themes/_dark_variables.scss:59-62`、`partials/_flash.scss:48-53` |
| F8 | #10 の `.flash-notice` パッチ（`c8a4cf595`）は既に導入済みで、コンパイル後 CSS にも `body.dark-theme .flash-notice .flash-text { color: #333333 !important }` が存在する | コンパイル後 CSS、`git log c8a4cf595` |
| F9 | マーケットプレイスのフラッシュは notice / warning / error の 3 種のみ（`flash-success` / `ajax-*` は到達するビューが無いレガシー CSS） | `app/views/layouts/_notifications.haml:16-23`（grep で `flash[:success]` / `flash-success` の描画箇所なし） |
| F10 | 設定画面の保存ボタンは `.send_button_account`（`#email_submit` / `#password_submit`）と `.send_button_notifications`。`main.scss` の dark-theme ブロックが `#email_submit` のみ `#2f6fc4` に固定し、他は汎用 `button` の `#4a90e2` のまま | `app/views/settings/account.haml:91,106`、`notifications.haml:23`、`app/assets/stylesheets/main.scss:2291-2299,422` |
| F11 | 既存のゴールドボタンパッチは `.send_button`（プロフィール設定）と `button.button` のみ。`.send_button_account` / `.send_button_notifications` はクラス名不一致で適用されない | `_raku_utils.scss:100-108,122-128`、`app/views/settings/show.haml:118` |
| F12 | アカウント削除ボタンは `button_tag` で id のみ（無効時は `.disabled-button` + `disabled` 属性）。`.disabled-button` は背景 `$border` のグレー | `account.haml:122`、`partials/_buttons.scss:29-33` |
| F13 | スタイルの読み込み順は `main → calendar → partials → views → themes → components`（`//= require_tree`）。`_raku_utils.scss`（components）が最後に来るため、同一詳細度のルールは後勝ちで上書きできる | `app/assets/stylesheets/application.scss` |
| F14 | DESIGN.md §10: Primary = Gold background + dark text、Destructive = Red。§4 Red usage: Red は Error / destructive action に限定し通常 CTA に使わない | `DESIGN.md:83-105,285-315` |

**結論**:
- #8 は「パッチのセレクタ列挙漏れ」であり、warning / success の本文と success / error のリンクを同じスコープ（`body.dark-theme`）で補えば解消する。
- #15 は「ボタンのクラス / id に応じたパッチの不足」であり、既存ゴールドパッチの適用範囲拡大＋破壊的ボタンの Red 化で解消する。
- #10 はコード変更不要の見込み。コンパイル後 CSS とブラウザ実測で「解決済み」を確定させる。

---

## 2. スコープ

### 実施する

1. **#8**: ダークテーマのフラッシュ通知（notice / warning / success）本文と、success / error のリンクのコントラストを WCAG AA（4.5:1）以上にする。
2. **#15**: 設定画面（account / notifications）の保存ボタンをゴールド＋ダーク文字に、アカウント削除ボタンを Red（破壊的）に統一する。
3. **#10**: コード変更なし。コンパイル後 CSS と実測によるクローズ判定材料を報告する。
4. 検証スクリプト（コンパイル確認・コントラスト比の数値実測）と回帰スペック。

### 実施しない（フォローアップ候補）

- ライトテーマ向けの変更（F1 のとおりライトテーマは現状到達不能。パッチは `body.dark-theme` スコープに限定し、ライト側のスタイルを一切変えない）。
- 他画面の `input[type="submit"].button`（`main.scss:2294` で `#2f6fc4` のまま。白文字 5.0:1 で基準は満たす）のゴールド統一。
- `.flash-error-link` のライトテーマ相当（`#ccc` on `#c81f1f` = 3.6:1）の是正。ダークテーマ（実運用）のみ修正する。
- `admin2` 管理画面のフラッシュ（別レイアウト・別スタイルのため対象外）。
- GitHub Issue へのコメント・クローズ、push（親エージェントが実施）。

---

## 3. 振る舞い定義（BDD）

### T1 (#8): ダークテーマのフラッシュ通知

DOM は `_notifications.haml:16-23` の `.flash-notification.flash-{type} > .flash-icon + .flash-text` とし、背景は親要素の `background-color` を解決して判定する。

| # | 前提 | 操作 | 期待する振る舞い（実測値は §9 に記録） |
|---|------|------|--------------------------------------|
| T1-1 | `body.dark-theme` | `.flash-warning .flash-text` の computed color / 背景を実測 | `rgb(51, 51, 51)` / `#e8e8e8`、コントラスト比 ≥ 4.5:1（約 10.3:1） |
| T1-2 | `body.dark-theme` | `.flash-notice .flash-text`（#10 の回帰） | `rgb(51, 51, 51)` / `#e8e8e8`、≥ 4.5:1 |
| T1-3 | `body.dark-theme` | `.flash-success .flash-text`（レガシー定義の点検） | `rgb(51, 51, 51)` / `#b2d9ab`、≥ 4.5:1（約 8.1:1） |
| T1-4 | `body.dark-theme` | `.flash-error .flash-text`（点検。変更なしが期待値） | `rgb(255, 255, 255)` / `#c81f1f`、≥ 4.5:1（約 5.7:1） |
| T1-5 | `body.dark-theme` | `.ajax-warning .ajax-text` / `.ajax-success .ajax-text`（レガシー定義の点検） | `rgb(51, 51, 51)`、各背景で ≥ 4.5:1 |
| T1-6 | `body.dark-theme` | `.flash-error` 内のリンク（`a.flash-error-link`）の通常 / hover | `rgb(255, 255, 255)` + 下線、≥ 4.5:1（hover 含む） |
| T1-7 | `body.dark-theme` | `.flash-success` 内のリンクの通常 / hover | 本文と同じ `rgb(51, 51, 51)` + 下線、≥ 4.5:1 |
| T1-8 | `body.dark-theme` | `.flash-notice` / `.flash-warning` 内のリンク（既存パッチの回帰） | `#1f6f60` + 下線、≥ 4.5:1 |
| T1-9 | `body`（dark-theme なし = ライト相当） | 上記すべて | **変更前後で同一**であること（本タスクはライト側を変えない） |
| T1-10 | 通知が空文字 / `flash[:warning]` なし | 描画 | `.flash-notification` 自体が出力されない（既存挙動、変更なし） |

### T2 (#15): 設定画面のボタン

| # | 前提 | 操作 | 期待する振る舞い |
|---|------|------|------------------|
| T2-1 | `body.dark-theme` | `#email_submit`（account メール保存）の通常 / hover / active | 背景 `--accent-gold`(`#d4a853`)、文字 `#1a1a1a`、≥ 4.5:1（約 8.9:1）。hover / active は `--accent-gold-hover`(`#c09840`)、≥ 4.5:1 |
| T2-2 | `body.dark-theme` | `#password_submit`（パスワード保存） | 同上 |
| T2-3 | `body.dark-theme` | `.send_button_notifications`（通知設定の保存） | 同上 |
| T2-4 | `body.dark-theme` | `.send_button`（プロフィール設定の保存。既存パッチの回帰） | 同上（背景 `--accent-gold` / 文字 `#1a1a1a`） |
| T2-5 | `body.dark-theme` | `#delete_account_button`（有効時）の通常 / hover | 背景 `--accent-red`(`#c41e3a`) / `--accent-red-hover`(`#a81830`)、文字 `#ffffff`、≥ 4.5:1（5.8:1 / 7.4:1） |
| T2-6 | `body.dark-theme`・`has_unfinished` または `only_admin` | `#delete_account_button`（`.disabled-button` + `disabled`） | 背景は `.disabled-button` のグレー（`$border` = `#c3c3c3`）を維持。Red を適用しない |
| T2-7 | `body`（ライト相当） | 上記 4 ボタン | **変更前後で同一**（`#email_submit` = `#2f6fc4`、他 = `#4a90e2`、削除 = `#4a90e2`） |
| T2-8 | 実ページ | `GET /ja/:username/settings/account` / `/settings/notifications` / `/settings` | 200 を返し、CSS フック（`#email_submit` / `#password_submit` / `#delete_account_button` / `.send_button_account` / `.send_button_notifications` / `.send_button`）が HTML に存在する |

### T3 (#10): クローズ判定

| # | 操作 | 期待する振る舞い |
|---|------|------------------|
| T3-1 | 変更前のコンパイル後 CSS を検査 | `body.dark-theme .flash-notice .flash-text { color: #333333 !important }` が存在（`c8a4cf595` 由来） |
| T3-2 | T1-2 の実測 | `rgb(51, 51, 51)` / 10.3:1 で解決済みを確認 |

---

## 4. 実装方針

### 4.1 変更ファイル

| 種別 | ファイル | 内容 |
|------|----------|------|
| 変更 | `app/assets/stylesheets/components/_raku_utils.scss` | ① flash 本文パッチに warning / success（+ ajax 版）を追加。② 通知内リンクパッチに success（`#333333` + 下線）/ error（`#ffffff` + 下線）を追加。③ 設定画面ボタンの Gold / Red パッチを追加 |
| 新規 | `scripts/compile_application_css.rb` | Sprockets で `application.css` をコンパイルして書き出す検証用ヘルパ |
| 新規 | `scripts/theme_contrast_check.js` | コンパイル後 CSS + 実 DOM 構造を読み込み、computed style から WCAG コントラスト比を実測するスクリプト（Playwright / Chromium） |
| 新規 | `spec/requests/settings_theme_spec.rb` | 設定画面 3 ページが 200 を返し、CSS フックの id / class が描画されることの回帰ガード |
| 新規 | 本文書 | 計画・検証記録 |

ビュー（`.haml`）とコントローラは変更しない。

### 4.2 設計判断

| 論点 | 判断 | 理由 |
|------|------|------|
| `_flash.scss` の配色自体を見直すか | **見直さない**（スコープ付きパッチを継続） | `_flash.scss` は admin など非ダーク領域でも使われる共有パーツ。既存プロジェクトの確立パターン（`_raku_utils.scss` 冒頭コメント「同一スコープ + !important で優先」）に従う。Issue #8 の受け入れ条件「ライトテーマ表示に影響しない」も満たす |
| 追加パッチのスコープ | `body.dark-theme` に限定 | ライト相当の表示を 1px も変えないため（F1 により実質は全画面ダーク） |
| warning / success の文字色 | 既存パッチと同じ `#333333` | 既存値の再利用（マジックナンバーを増やさない）。明色背景 `#e8e8e8` / `#b2d9ab` 上で 10.3:1 / 8.1:1 |
| error 内リンク | `#ffffff` + 下線 | 赤背景上で teal が 2.3:1 に落ちるため。本文（`color: white`）と同値 |
| success 内リンク | `#333333` + 下線 | 明色背景では dark teal `#1f6f60` でも 3.8:1 にしかならないため、本文と同色 + 下線で識別（色だけに頼らない） |
| 設定ボタンのセレクタ | ID（`#email_submit` / `#password_submit`）+ クラス（`.send_button_notifications`） | `main.scss` の `#email_submit` 上書きが ID セレクタのため、クラスでは詳細度が足りない（F10 / F13）。ID で揃えて後勝ちにする |
| 削除ボタンの無効状態 | `:not(.disabled-button)` で Red を除外 | ID セレクタ（1,1,1）は `.disabled-button`（0,1,0）より強いため、除外しないと無効時のグレーが Red に上書きされ壊れる（T2-6） |
| hover / active | `--accent-gold-hover` / `--accent-red-hover` を明示 | 汎用 `button:hover`（`darken($link, 5%)` + 白文字）が残るとコントラストが崩れるため |

### 4.3 詳細度・カスケードの設計（F13 の読み込み順に依存）

| 対象 | 競合するルール | 競合の詳細度 | 本パッチの詳細度 | 勝敗 |
|------|----------------|--------------|------------------|------|
| `.flash-text` | `body.dark-theme`（色継承） | (0,1,1) | (0,2,2) + `!important` | 勝ち |
| `#email_submit` | `body.dark-theme #email_submit`（main.scss） | (1,1,1) | (1,1,1)・components が後 | 勝ち（後勝ち） |
| `#email_submit:hover` | `body.dark-theme #email_submit:hover`（main.scss） | (1,2,1) | (1,2,1)・後 | 勝ち |
| `#password_submit` 等 | `button` / `button:hover`（main.scss） | (0,0,1) / (0,1,1) | (1,1,1) / (1,2,1) | 勝ち |
| `#delete_account_button` | `button`、及び `.disabled-button`（無効時） | (0,0,1) / (0,1,0) | (1,2,1) だが `:not(.disabled-button)` で無効時は不一致 | 有効時は勝ち / 無効時は `.disabled-button` が維持 |
| `.flash-error a` | `body.dark-theme a` / `a:hover` | (0,1,2) / (0,2,2) | (0,2,2)・後 | 勝ち（hover も同値で維持） |

---

## 5. 検証計画

| # | 検証 | コマンド（作業ディレクトリ: リポジトリ直下） | 受入基準 |
|---|------|--------------------------------------------|----------|
| V1 | SCSS コンパイル | `bundle exec rails runner scripts/compile_application_css.rb /tmp/application.css` | エラーなく完了。`application.css` を出力 |
| V2 | コントラスト実測 | `node scripts/theme_contrast_check.js --css /tmp/application.css --json /tmp/contrast.json` | T1-1〜T1-8 / T2-1〜T2-6 がすべて ≥ 4.5:1 で PASS、失敗時は exit 1 |
| V3 | ライト相当の非変更 | 変更前後で `theme_contrast_check` のライト節を diff | T1-9 / T2-7（差分なし） |
| V4 | 回帰スペック | `bundle exec rspec spec/requests/settings_theme_spec.rb` | 3 examples, 0 failures |
| V5 | 既存テスト | `bundle exec rspec spec/requests`、可能なら `bundle exec rspec` | 0 failures |
| V6 | クライアントビルド（SCSS 周辺の確認） | `cd client && npx webpack --mode=development --config webpack.client.config.js`（Node 18.16.0） | コンパイル成功（警告は既存） |
| V7 | E2E（任意） | `node spec/e2e/navigation_spec.js` | 稼働サーバーがある場合のみ。無ければ未実行理由を記録 |

実測は「対象要素の computed color / 実効背景色をブラウザ（Chromium）で解決 → WCAG 2.x コントラスト比を計算」する方式とし、スクリプトに固定する（§6 が再利用可能な成果物）。

---

## 6. 成果物（検証の再現手順）

```bash
# 1) CSS をコンパイル
bundle exec rails runner scripts/compile_application_css.rb /tmp/application.css

# 2) コントラストを実測（dark / light の両方を出力、dark は閾値判定）
node scripts/theme_contrast_check.js --css /tmp/application.css --json /tmp/contrast.json

# 3) CSS フックの回帰スペック
bundle exec rspec spec/requests/settings_theme_spec.rb
```

`scripts/theme_contrast_check.js` は実 DOM（`_notifications.haml` と設定フォーム）を再現したフィクスチャに対し、実際のコンパイル CSS を適用して `getComputedStyle` を計測する。`:hover` は Playwright の `hover()` で発生させる。

---

## 7. リスクと対処

| リスク | 影響 | 対処 |
|--------|------|------|
| `:not(.disabled-button)` の対応 | 古いブラウザで無効化される | 対象は Chromium 系の実運用。CSS Selectors L3 の `:not()` は全モダンブラウザ対応。プレフィックス不要 |
| `--accent-gold` / `--accent-red` がスコープ外 | 変数未定義でボタンが透明化 | 変数は `:root`（`themes/_dark_variables.scss:4-46`）でグローバル定義。V2 で実測確認 |
| `!important` の追加 | 保守性低下 | flash 本文は既存 `!important` のセレクタ追加のみ。ボタンには追加しない（詳細度で解決） |
| スタイル差分の副作用 | 他画面のボタンが変わる | 追加セレクタは id / 固有クラスに限定（grep で他用途が無いことを確認: F10 / F11） |
| E2E は稼働サーバーが必要 | 未実行の可能性 | 未実行時は理由を §9.4 に記録し、V1〜V5 で代替 |

---

## 8. Plan Architect レビュー

### 8.1 レビュー結果（2026-10-23）

**判定: 承認**（指摘 3 件。うち 1 件 🟡 は記録のみ、2 件 🟢 はスコープ外として申し送り）

| 観点 | 確認内容 | 結果 |
|------|----------|------|
| 規約整合 | `docs/scss-coding-guidelines.md`（`components` は CSS 出力可、`partials`/`views` を `@import` しない）に準拠 | ✅ |
| 重複防止 | 既存の flash パッチ / ゴールドボタンパッチの**拡張**として実装し、同種のパッチを新設しない | ✅ |
| 再利用 | 新規リテラル色ゼロ。`#333333`（既存パッチ値）/ `#1a1a1a`（既存）/ `white`（`_flash.scss` と同値）/ `--accent-gold(-hover)`・`--accent-red(-hover)`（既存トークン、`:root` 定義）のみ | ✅ |
| 編集範囲 | `app/assets/stylesheets/components/`・`scripts/`・`spec/`・`documents/` のみ。Sharetribe コア由来ファイルの変更なし | ✅ |
| カスケード | §4.3 の詳細度監査。`#email_submit`（`main.scss` の ID 上書き）に components の後勝ちで勝利することを確認 | ✅ |
| セレクタの他用途 | `#email_submit` / `#password_submit` / `.send_button_notifications` / `#delete_account_button` は grep で settings ビュー以外に使用なし | ✅ |
| 無効ボタンの維持 | `:not(.disabled-button)` により `has_unfinished` / `only_admin` 時の `.disabled-button`（グレー）を維持 | ✅ |
| テスト計画 | 数値実測（V2）+ 回帰スペック（V4）+ 既存スペック（V5） | ✅ |
| セキュリティ / 性能 | 純粋なスタイル変更。入力・秘密情報の扱いなし。追加セレクタは数十行でリフロー影響なし | ✅ |

**指摘事項**:

| # | 優先度 | 指摘 | 対応 |
|---|--------|------|------|
| A1 | 🟡 記録 | `.flash-success` / `.ajax-success` は現行ビューから到達しない（F9）。防御的パッチとして追加するが、検証はフィクスチャでのみ可能 | 計画に明記済み（§9.4 に未検証範囲として記録） |
| A2 | 🟢 | success / error 内リンクは「本文と同色 + 下線」「白 + 下線」で色だけに頼らない識別にする。Red は削除ボタン限定を維持すること | 設計に反映済み |
| A3 | 🟢 | `input[type="submit"].button`（他画面）の配色統一は本件スコープ外 | フォローアップ候補として §2 に記録 |

---

## 9. 実装・検証記録（2026-10-23）

### 9.1 変更ファイル

| 種別 | ファイル | 内容 |
|------|----------|------|
| 変更 | `app/assets/stylesheets/components/_raku_utils.scss` | flash 本文（warning / success + ajax）・通知内リンク（success / error）・設定画面ボタン（Gold / Red）のパッチ（+68 −−2 行） |
| 新規 | `scripts/compile_application_css.rb` | Sprockets で `application.css` をコンパイルするヘルパ |
| 新規 | `scripts/theme_contrast_check.js` | フィクスチャ + コンパイル CSS によるコントラスト実測（dark は合否判定、light は記録。axe color-contrast 付き） |
| 新規 | `spec/requests/settings_theme_spec.rb` | 設定 3 ページの CSS フック契約（id / class）の回帰ガード |
| 新規 | 本文書 | 計画・検証記録 |

ビュー・コントローラ・JS は未変更。

### 9.2 Reviewer 観点の確認

| 観点 | 結果 |
|------|------|
| 意図しない変更の混入 | `git diff` は `_raku_utils.scss` のみ（+68/−2）。全ての追加ルールが `body.dark-theme` スコープまたは既存パッチの拡張 |
| 重複実装 | 新規パッチの新設なし。既存の flash / ゴールドパッチへのセレクタ追加で実現 |
| 詳細度・カスケード | コンパイル後 CSS で確認: main.scss の `body.dark-theme #email_submit { background-color: #2f6fc4 }`（出力 6041 行付近）に対し、components の同詳細度ルール（出力 25774 行付近）が後勝ち |
| 無効状態の回帰 | `:not(.disabled-button)` により `disabled` 時は `.disabled-button` のグレー（`rgb(195,195,195)`) のまま（実測 1.76:1、変更前後で同一。非活性は WCAG 1.4.3 の適用除外） |
| ライト相当の非変更 | 実測 JSON の全 16 項目で pre/post 差分なし（同一値） |
| セレクタの他用途 | `#email_submit` / `#password_submit` / `.send_button_notifications` / `#delete_account_button` は grep で設定画面以外に使用なし |
| 秘密情報 | 新規ファイルにハードコードされた認証情報なし（ログインは既存の `UserService::API::AuthTokens` を利用） |
| 脆弱性（セキュリティ） | 純粋な CSS |
| 性能 | 追加セレクタのみ。レイアウト・描画への影響なし |

### 9.3 QA: 実行したコマンドと結果

| # | コマンド | 結果 |
|---|----------|------|
| V1 | `bundle exec rails runner scripts/compile_application_css.rb /tmp/application_post.css` | 成功: 933,578 bytes（変更前 931,163 bytes） |
| V2 | `node scripts/theme_contrast_check.js --css /tmp/application_post.css --json /tmp/contrast_post.json` | **dark: 20 PASS / 0 FAIL / 1 記録のみ（exit 0）**、axe color-contrast 違反 0 |
| V2' | 同スクリプトを変更前 CSS（`/tmp/pre_change_application.css`）に適用 | dark: 7 PASS / **13 FAIL** / 1 記録のみ（exit 1）→ 修正対象の再現確認 |
| V3 | `node -e`（pre/post JSON の機械比較） | **ライト相当: 差分なし（同一）** |
| V4 | `bundle exec rspec spec/requests/settings_theme_spec.rb` | 3 examples, 0 failures |
| V5 | `bundle exec rspec spec/requests` | 304 examples, 0 failures |
| V5' | `bundle exec rspec`（全体） | **1412 examples, 0 failures** |
| V6 | `cd client && npx webpack --mode=development --config webpack.client.config.js`（Node 18.16.0） | webpack 5.84.1 compiled（警告は既存のもの） |
| V6' | `bundle exec rake i18n:js:export` / `bundle exec rake js:routes` | 成功（ビュー描画系スペックの前提アセット） |
| V7 | 自 worktree のサーバーを一時起動（`bin/rails server -p 3100`）+ `node /tmp/live_theme_check.js` | **実ページにて 8/8 PASS**（実測値は §9.5）+ axe color-contrast 違反 0（login / account / notifications / profile） |
| V7' | E2E `spec/e2e/navigation_spec.js`（BASE を `:3100` に差し替えたコピーを /tmp で実行） | 25 合格 / 1 不合格（TC-26: チャット RESULT バッジ。DOM 要素自体が無いという判定で CSS とは無関係）/ 2 スキップ（AUDIT_TOKEN 未設定） |
| - | `bundle exec rubocop scripts/compile_application_css.rb spec/requests/settings_theme_spec.rb` | no offenses |
| - | `node --check scripts/theme_contrast_check.js` / `ruby -c ...` | 構文エラーなし |

### 9.4 QA: 未実行の検証と理由

| 検証 | 理由 |
|------|------|
| `scripts/a11y_audit.js`（フル監査） | 常設サーバー（:3000）と `AUDIT_TOKEN` が前提。常設サーバーが無いため未実行。代わりに自 worktree の一時サーバーに対し、変更対象ページで axe `color-contrast` を実測（違反 0） |
| `docs/accessibility-report.md` の更新 | 恒常的な監査レポートは別運用（全ページ巡回）のため、本タスクでは更新しない |
| ライトテーマの実画面確認 | `application.haml` が常に `body.dark-theme` を出力するため実画面でのライト表示は不可能。フィクスチャで pre/post 同一を機械確認 |
| `.flash-success` / `.ajax-*` の実ページ確認 | これらを描画するビューが現行コードに存在しない（F9）。フィクスチャでのみ検証 |
| `:active` 状態の計測 | hover / active は同一宣言ブロック（コード確認済）。計測ハーネスは hover まで |

### 9.5 コントラスト比の実測（変更前 → 変更後、body.dark-theme）

実測コマンド: `node scripts/theme_contrast_check.js --css <コンパイル後 application.css>`
（Chromium で computed style を解決し、WCAG 2.x の相対輝度式で算出。背景は祖先要素を合成した実効値）

| 対象（セレクタ） | 変更前 | 変更後 | 判定 |
|------------------|:------:|:------:|:----:|
| `.flash-warning .flash-text`（#8） | 1.23:1 ❌ | **10.31:1** ✅ | PASS |
| `.flash-success .flash-text`（#8） | 1.57:1 ❌ | **8.07:1** ✅ | PASS |
| `.flash-error .flash-text`（変更なし） | 5.72:1 | 5.72:1 | PASS |
| `.flash-notice .flash-text`（#10 の確認） | 10.31:1 | 10.31:1 | PASS |
| `.ajax-warning .ajax-text`（#8） | 1.23:1 ❌ | **10.31:1** ✅ | PASS |
| `.ajax-success .ajax-text`（#8） | 1.57:1 ❌ | **8.07:1** ✅ | PASS |
| `.flash-success a`（#8） | 1.60:1 ❌ | **8.07:1** ✅ | PASS |
| `.flash-error a.flash-error-link`（#8） | 2.29:1 ❌（hover 2.82:1 ❌） | **5.72:1** ✅（hover 同値） | PASS |
| `.flash-notice a` / `.flash-warning a`（既存パッチ） | 4.90:1 | 4.90:1 | PASS |
| `#email_submit`（#15） | 5.01:1（青） | **7.89:1**（Gold） | PASS |
| `#password_submit`（#15） hover | 3.29:1 ❌（3.86:1 ❌） | **7.89:1** ✅（6.47:1 ✅） | PASS |
| `.send_button_notifications`（#15） hover | 3.29:1 ❌（3.86:1 ❌） | **7.89:1** ✅（6.47:1 ✅） | PASS |
| `#delete_account_button`（#15） hover | 3.29:1 ❌（3.86:1 ❌） | **5.84:1** ✅（7.40:1 ✅） | PASS |
| `.send_button`（プロフィール、回帰） | 7.89:1 | 7.89:1 | PASS |
| `#delete_account_button.disabled-button`（無効時） | 1.76:1 | 1.76:1（グレー維持） | 記録のみ（WCAG 適用除外） |
| `.flash-error .flash-text a:hover`（#8） | 2.82:1 ❌ | **5.72:1** ✅ | PASS |

実ページ（自 worktree のサーバー、`/ja/login` の実フラッシュ）でも同一値を実測:

- `.flash-warning .flash-text`（ログイン誘導の実警告）= `rgb(51,51,51)` / `rgb(232,232,232)` = **10.31:1**
- `#email_submit` / `#password_submit` = `rgb(26,26,26)` / `rgb(212,168,83)` = **7.89:1**
- `#delete_account_button` = `rgb(255,255,255)` / `rgb(196,30,58)` = **5.84:1**（hover 7.40:1）
- `.send_button_notifications` = 7.89:1（hover 6.47:1）/ `.send_button` = 7.89:1

### 9.6 #10 のクローズ判定材料

| 確認 | 結果 |
|------|------|
| パッチの存在 | 変更前コンパイル後 CSS に `body.dark-theme .flash-notice .flash-text { color: #333333 !important }` が存在（`c8a4cf595` 由来） |
| 実測 | dark で `rgb(51,51,51)` / 10.31:1（フィクスチャ・実ページ相当とも） |
| 結論 | **コード変更不要**。クローズ可（クローズ判定と実際のクローズは親が実施） |

### 9.7 環境差分の注記

作業コピーには git 管理外の設定・生成物が無いため、メインチェックアウトから以下を補った（コード変更ではない）: `config/database.yml` / `.env`（値の出力・コミットなし）、`vendor/bundle`、`node_modules`、`client/node_modules`。またビュー描画系スペックのために `bundle exec rake i18n:js:export`・`bundle exec rake js:routes`・webpack ビルドを実行し、参照されるレガシーアセット `app-bundle.css`（webpack 分割後は生成されないが `ClientAssetsHelper` が参照）をメインからコピーした。`app-bundle.css` / `sections-bundle.css` は本タスクの対象セレクタを含まないことを確認済（application.css のみでの実測が妥当）。

---

## 10. 受入条件の判定

| Issue | 受入条件 | 結果 |
|-------|----------|------|
| #8 | 警告表示時の本文コントラストが 4.5:1 以上 | ✅ 実測 10.31:1（実ページでも同一） |
| #8 | 既存のアクセシビリティ監査で違反が出ない | ✅ 変更対象ページの axe `color-contrast` 違反 0（フル監査は §9.4 参照） |
| #8 | ライトテーマに影響しない | ✅ pre/post 機械比較で差分なし |
| #10 | リロード・キャッシュクリア後も 4.5:1 以上 | ✅ コンパイル CSS を毎回生成して実測。実ページでも 10.31:1 |
| #15 | 「保存」がゴールド＋ダーク文字 | ✅ #email_submit / #password_submit / .send_button_notifications とも 7.89:1 |
| #15 | 削除ボタンの配色方針が決まり実装 | ✅ Destructive = Red（`--accent-red`）。5.84:1 / hover 7.40:1 |
| #15 | コントラスト 4.5:1 以上 | ✅ 全ボタンで達成 |
| #15 | 既存テストが通る | ✅ 1412 examples, 0 failures |


