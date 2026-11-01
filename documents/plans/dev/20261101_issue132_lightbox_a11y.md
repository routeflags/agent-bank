# BDD 計画書 — Issue #132（Markdown ヘルプのライトボックスのアクセシビリティ）

作成日: 2026-11-01 / ブランチ: fix/132-lightbox-a11y（origin/main = 0154d7562 から分岐）
対象: `app/views/layouts/_lightbox.haml`, `app/views/layouts/_markdown_help.haml`,
`app/helpers/icon_helper.rb`, `app/assets/stylesheets/main.scss`,
`config/locales/ja.yml`, `config/locales/en.yml` の 6 ファイルのみ。

## 調査による前提（設計根拠）

- ライトボックスは jQuery の `jquery.lightbox_me`（`vendor/assets/javascripts/jquery.lightbox_me.js`）で
  開く。`.lightbox` 要素は開くときに `$('body').append(...)` で body 直下へ移動する（同 45 行）
  ため、スタイルも支援技術から見た位置も `body.dark-theme` の子になる。
- 開閉は `_markdown_help.haml:91`（`content_for :markdown_help_javascript`）で
  `$('#markdown-popup-link').click(...)` → `lightbox_me({centered: true, zIndex: 1000000})`。
  このブロックは `run_js_immediately` のときその場に、それ以外は
  `content_for :extra_javascript`（`application.haml:133`、body 内）で出力される。
- Esc は lightbox_me の既定動作が既に持つ（`closeEsc: true` = 同 215 行、
  `observeKeyPress` = 同 144-145 行、window の keyup で閉じる）。よって Esc は
  「無かった」のではなく「本文・フォーカスと合わせて保証されていなかった」。
  今回はフォーカスの入口（開いた時）と出口（閉じた時）だけを足し、Esc はプラグインに委ねる。
- 閉じるアイコンの色は `main.scss:663` `a.lightbox-x { color: #aaacad }`。
  ただし `themes/_dark_variables.scss:59-62` の `body.dark-theme a { color: var(--text-link) }`
  （特異性 0,1,2）が `a.lightbox-x`（0,1,1）に勝つため、実描画は `--text-link: #59b3a2`
  （同 25 行）。背景は `.lightbox-content { background: $background }` = `#fff`
  （`mixins/default-colors.scss:38` の `hsl($primary-hue, 0%, 100%)`）。
- 実描画 CSS は開発サーバーの `/assets/application-31bd6565….css` を取得して確認
  （`.lightbox-content` 4055 行付近、`a.lightbox-x` 4113 行付近、
  `body.dark-theme h1..h6 { color: var(--text-primary) }` 24311 行、
  `h1` / `h2` の実値 12848-12878 行）。
- 見出しの実値（＝置換後の目標値）: `reset.scss:25` で `h1..h6 { font-size: 1em }`。
  `partials/_texts.scss:24-53` が `h1`（weight 700 / mb 0.75em、≥37.5em で
  `large-type` = 1.625em・weight 600・mt 0.23077em・mb 0.46154em）と
  `h2`（`normal-type` / weight 500 / mb 0.75em、≥37.5em で `big-type` のあと
  weight 500 に戻す）を定義。`main.scss:621,625` の `.lightbox-content h2 / h3` が
  margin を上書き（h2 mb 0.375em、h3 mt 0.75em・mb 0.375em）し、
  `main.scss:642` の `@media(tablet)` が `.lightbox-content h2` に `big-type`
  （weight 600）を当てる。h3 は weight を誰も指定しないのでブラウザ既定の bold。
- `icon_tag` は `app/helpers/icon_helper.rb:12` で `<i>` を組み立てるだけ。
  属性を渡す口が無いので、後方互換の第3引数（html_options）を足す。

## タスク一覧（BDD）

### T1: 閉じるリンクのアクセシブル名（#132-1）

- Given ライトボックスを開いた状態 When 支援技術で閉じるリンクを読む
  Then 「閉じる」（ja）/「Close」（en）と読まれる。
- Given 同リンクの中の `<i class="icon-…">` When 支援技術で読む
  Then `aria-hidden="true"` で無視される。
- Given 他のライトボックス（`#terms` / `#listing_popup` / `#paypal_fee_info_content` 等）
  When 開く Then リンクには同じ aria-label が付く（同じ partial のため）。
- Given 既存の `icon_tag(name)` / `icon_tag(name, classes)` 呼び出し（多数）When 描画
  Then 出力 HTML は従来と完全に同一（第3引数の既定値は空）。

### T2: 閉じるアイコンのコントラスト（#132-2）

- Given 白背景の `.lightbox-content` When 閉じるアイコンを描画
  Then 文字色は `#767676`（白背景 4.54:1）。
- Given hover When 描画 Then `#5f6163`（6.22:1）で、通常時より暗い。
- Given `body.dark-theme a`（0,1,2）When 詳細度を比較
  Then `.lightbox a.lightbox-x`（0,2,1）が勝ち、`!important` を使わない。
- Given 幅・位置・padding・icon サイズ（`big-type`）When 比較 Then 不変。

### T3: 見出し順序（#132-3）

- Given ライトボックスを開いた状態 When 見出しアウトラインを取る
  Then `h1` が存在せず、`h2`（タイトル）のみ。表セル内は見出しではない。
- Given 「結果」列 When 描画 Then `div.markdown-help-heading--h1/h2/h3` が
  h1/h2/h3 と同一の computed style（font-family / size / weight / margin / smoothing）で描画。
- Given 左列の markdown 記法と他の行（i / b / u / strike / a / ul / ol）When 比較
  Then 不変。

### T4: ダイアログのセマンティクスとフォーカス（#132-4）

- Given Markdown ヘルプを開く When DOM を見る Then `.lightbox` に
  `role="dialog"` / `aria-modal="true"` / `aria-labelledby="markdown-help-popup-title"` /
  `tabindex="-1"` が付き、参照先の `h2` が存在する。
- Given 開いた直後 When フォーカス位置を見る Then ダイアログ本体にフォーカスがある。
- Given ダイアログ内で Tab / Shift+Tab When 押す Then フォーカスはダイアログ内を循環する。
- Given Esc / × / オーバーレイクリック When 閉じる Then 閉じた後フォーカスは
  `#markdown-popup-link` に戻る。
- Given `labelledby` を渡さない他のライトボックス When 描画
  Then 従来どおり `role` / `aria-modal` / `tabindex` は付かない（名前のないダイアログを作らない）。

## 変更ファイル

| ファイル | 対応 |
|---|---|
| `app/views/layouts/_lightbox.haml` | #1（aria-label / aria-hidden）、#4（role / aria-modal / aria-labelledby / tabindex） |
| `app/helpers/icon_helper.rb` | #1（`icon_tag` に html_options を追加） |
| `app/views/layouts/_markdown_help.haml` | #3（h1/h2/h3 → div + クラス、h2 に id）、#4（フォーカス管理 JS） |
| `app/assets/stylesheets/main.scss` | #2（色・スコープ）、#3（見出し見本のクラス） |
| `config/locales/{ja,en}.yml` | #1（`layouts.lightbox.close`） |

触らない: `views/_account-settings.scss`（`.markdown-help-table` は `.account-settings`
配下でしか効かないため、ライトボックス内の見出し見本は `main.scss` に置く）、
`vendor/assets/javascripts/jquery.lightbox_me.js`（Esc は既定動作を利用）。

## 検証

- Haml: `Haml::Engine.new.call` でコンパイル → `RubyVM::InstructionSequence.compile`
- マークアップ: 生成 Ruby をスタブ環境で実行し、`labelledby` あり/なし両方の HTML を確認
- Ruby: `ruby -c`、`icon_tag` を実際に呼び出して出力文字列を確認
- SCSS: 変更ブロックを `@import "mixins/type"` 付きで切り出し、Ruby Sass 3.4.24 で
  コンパイル（compass 依存の `main.scss` 全体は origin/main でも単体コンパイル不可の既存問題）
- JS: `node --check`
- YAML: `YAML.load_file` とキー解決
- コントラスト: WCAG の相対輝度式で計算（Issue 記載の 2.50 / 2.28 と一致することを確認）
- 画面の最終確認（Playwright・スクショ）は親が実施
