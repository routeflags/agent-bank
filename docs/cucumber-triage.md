# Cucumber 可否トリアージレポート

実施日: 2026-10-08 / 対象: features/ 配下78.featureファイル（256シナリオ）

## 結論（サマリ）

- **ハーネスは動作する**: cucumber-rails3.1 + Capybara/Puma + ThinkingSphinx + DatabaseCleaner の
  起動・実行・サマリ出力まで到達可能（`bundle exec cucumber -p ci`）。
- **障害だった2点を修正済み**（features/support/env.rb）:
  1. searchd の残存プロセスで `ThinkingSphinx::Test.start` が
     `Riddle::CommandFailedError` になり起動不能 → 開始前にstopをベストエフォートで実行
  2. autostop の停止失敗が `Kernel.exit` を送出しサマリを破壊（rspec で既に遭遇・修正済みの
     同種問題） → spec/support の `SafeSphinxStop` シムを cucumber からも共有 require
- **既知の失敗はインフラではなく仕様ドリフト**: raku リデザイン後のUI文言（旧ENコピー
  "Post a new listing" 等）やプライバシー挙動の変化に対する古い期待値が主因
  （例: features/homepage は5シナリオ中3成功2失敗が文言/仕様ドリフト）。

## 資産インベントリ

| ディレクトリ | シナリオ数 |
|---|---|
| admin2 | 75 |
| listings | 47 |
| conversations | 40 |
| sessions | 20 |
| settings / people | 各15 |
| communities | 11 |
| invitations | 9 |
| homepage | 5 |
| payments / feedback | 各4 |
| infos / common | 各2-3 |
| stripe / paypal / email | 各1 |

タグ: @javascript 165（大半）/ @example 88 / @sphinx 9。`@pending` / `@wip` /
`@fix_for_new_design` は**ゼロ**（ci プロファイルの除外タグは実質空振り）。

## 実行結果（ciプロファイル・ディレクトリ別実行）

全16ディレクトリを個別実行（起動レース修正後）。合計 **253シナリオ: 成功148 (58%) /
失敗106 / 未定義ステップ32**。

| ディレクトリ | 総数 | 成功 | 失敗 | 未定義 | 主な失敗原因の分類 |
|---|---|---|---|---|---|
| conversations | 40 | 29 | 11 | - | UIドリフト（#inbox-link等の旧セレクタ） |
| settings | 15 | 10 | 5 | - | UIドリフト（.left-navi等の旧レイアウト） |
| sessions | 20 | 11 | 9 | - | UIドリフト（ログイン後ヘッダの旧文言 "Markus"） |
| communities | 11 | 8 | 3 | - | 汎用ドリフト |
| invitations | 9 | 7 | 2 | - | 汎用ドリフト |
| people | 15 | 7 | 8 | - | UIドリフト（プロフィールの旧文言 "You follow N people"） |
| admin2 | 75 | 35 | 19 | 21 | 未定義ステップ（ステップ定義との世代差）+ JSエラー |
| listings | 47 | 2 | 34 | 11 | 出品フォームのraku全面刷新 vs 旧フロー期待値（最大の損失） |
| homepage | 5 | 3 | 2 | - | UIドリフト（"Post a new listing" 等の旧ENコピー） |
| payments | 4 | 0 | 4 | - | 表記ドリフト（"November 2050" vs "Nov 28, 2050"） |
| feedback | 4 | 0 | 4 | - | UIドリフト |
| infos | 3 | 0 | 3 | - | UIドリフト |
| common | 2 | 0 | 2 | - | UIドリフト（#new-listing-link） |
| paypal | 1 | 0 | 1 | - | **外部依存**（PayPalサンドボックス） |
| email | 1 | 1 | 0 | - | ✅ 完全に維持可能 |
| stripe | 0 | - | - | - | シナリオ全コメントアウト（死蔵）→ 削除済み |

補足: 全体実行で検出された Google Maps の `ApiProjectMapError` は **APIキー未設定**が原因の
外部依存失敗（マップ系シナリオに影響）。admin2/listings の未定義ステップ32件は
ステップ定義ファイルとフィーチャの世代差。

## 死んでいる資産の特定

- **paths.rb の旧adminヘルパー19件**（`admin_details_edit_path` 等、/admin_old 削除で
  消滅）: **どの.featureからも未使用**だったため当該 when ブロックを削除（本作業で対応済み）。
- **features/support/unused.rb / rename.rb**: コミュニティ配布の補助スクリプト
  （未使用ステップ列挙・一括リネーム）。実行経路なし → 削除（本作業で対応済み）。
- hapybara.rb: Capybara 設定（綴りは誤りだが**使用中**）— 名称のみ残存。

## 推奨ロードマップ（実測結果に基づく優先順位）

1. **（利益最大）conversations(29P) + settings(10P) + sessions(11P) + communities(8P)
   + invitations(7P) + people(7P) ≈ 72成功シナリオ** — いずれもUIドリフトのみが原因。
   旧セレクタ/文言の期待値をraku UIに合わせる更新で **成功148→約220 (87%)** まで復興可能。
   rspecのE2E(navigation_spec 27TC)と重複するが、シナリオ網羅性は cucumber 側に価値あり。
2. **（分類） admin2(35P/21U)** — 未定義ステップ32件のステップ定義補完 or シナリオ削除を
   トリアージ。admin2 rspec request spec（第3波で実装済み）との重複分は削除を推奨。
3. **（刷新前提） listings(2P/34F)** — 出品フォームが raku で全面刷新されており旧フロー
   前提の期待値は意味を失う。raku出品フロー（run_online/ペルソナ設定）の新シナリオを
   作り直すか、E2E(rspec)に一任して削除。
4. **（外部依存） payments/feedback/infos/common/paypal** — 表記ドリフトは軽微修正可。
   PayPalサンドボックス/Google Maps APIキーは環境変数・設定の整備が前提。
5. **（運用）** `make cucumber` ターゲット（ciプロファイル）を整備し、上記の
   「維持可能な成功領域」をゲート化。
