# Issue #106 Phase 2a — ペルソナ評価の集計基盤（`avg_rating` / `reviews_count`）

- 対象: `routeflags/agent-bank` / Issue #106（案A: 既存 `Testimonial` 流用）
- 起点: `origin/main` = `8b92582b0`（Phase 1 完了済み）
- スコープ: **Phase 2a = 集計基盤のみ**。ランキング／カード／詳細／プロフィールの表示改修（Phase 2b）は**やらない**
- 作業ブランチ: `feat/106-phase2a-rating-aggregation`

## 0. 前提調査（実測・コード確認済み）

| 確認対象 | 手段 | 結果 |
|---|---|---|
| `Testimonial` の構造 | `read_file app/models/testimonial.rb` | `grade` 0..1（inclusion）、`blocked`、`listing_id`（nullable）、`displayed_grade = (grade*4+1).to_i`、`scope :non_blocked`。コールバックは未定義 |
| `listings` の評価系カラム | `grep db/structure.sql` | `avg_rating float DEFAULT 0` のみ。`reviews_count` は**存在しない** |
| 既存サービス規約 | `app/services/listing_stats_service.rb` | `class XxxService` + `self.` のモジュール関数、日本語コメントで「なぜ」を書くスタイル |
| rake 規約 | `lib/tasks/*.rake` | `lamprey_*.rake` に `namespace :lamprey`。`import.rake` が `ENV["COMMIT"] == "1"` をドライラン既定の判定に使用 |
| spec 規約 | `spec/support/database_cleanup.rb` | DatabaseCleaner。既定は `:transaction`、`:'no-transaction' => true` のタグで `:truncation` |
| 開発 DB 実測 | `mysql` | `listings` 10 件（うち `avg_rating > 0` が 6 件: 4.5/3.9/4.3/4.4/3.9/4.4）、`testimonials` 0 件 |
| 既存表示の前提 | `grep reviews_count` | `app/views/listings/show.haml:254` が `@listing.reviews_count` を参照しているが、`average_rating` を `respond_to?` で門番しているため現状は実行されない（カラム追加で自然に解消） |

---

## 1. 振る舞い（BDD シナリオ）

### 1-1. 集計サービス `ListingRatingService.recalculate!`

集計対象は `testimonials` のうち `listing_id = 対象` かつ `blocked = false` かつ `grade` が NULL でない行。
`avg_rating` の尺度は **1〜5**（既存手動値 4.5 等と同じ）。

| # | 入力（grade の集合） | `reviews_count` | `avg_rating` |
|---|---|---|---|
| S1 | 空（0 件） | 0 | 0.0 |
| S2 | `[0.75]`（4★1件） | 1 | 4.0 |
| S3 | `[0.0]`（1★1件） | 1 | 1.0 |
| S4 | `[1.0]`（5★1件） | 1 | 5.0 |
| S5 | `[0.75, 0.5, 1.0]` → 平均 0.75 | 3 | 4.0 |
| S6 | `[1.0, 0.75]` → 平均 0.875 | 2 | 4.5（`.round(1)` の丸め） |
| S7 | `[0.5, 0.25]` → 平均 0.375 | 2 | 2.5 |
| S8 | blocked な行が混在（`[0.75]` + blocked `[0.0]`） | 1 | 4.0（blocked は除外） |
| S9 | 取引レビュー（`listing_id` NULL）だけが存在 | 0 | 0.0（対象外） |
| S10 | 存在しない listing_id | — | 例外を投げず `nil` を返す |
| S11 | 既に同じ値が入っている | 変化なし（無駄な UPDATE をしない。冪等） |

### 1-2. `Testimonial` の after_commit 連動

| # | 操作 | 期待する振る舞い |
|---|---|---|
| T1 | `listing_id` 付きで create | 該当 listing の `avg_rating` / `reviews_count` が再計算される |
| T2 | `listing_id` 付きを destroy | 再計算され、件数が 1 減り、0 件なら 0.0 に戻る |
| T3 | `blocked` を true に update | 除外され、件数・平均が変わる |
| T4 | `listing_id` を別の出品へ update | **移動元と移動先の両方**が再計算される |
| T5 | `listing_id` が NULL（取引レビュー）で create/destroy | どの listing の `avg_rating` / `reviews_count` も変化しない |
| T6 | 再計算中に例外が発生（DB エラー等） | 例外を握りつぶしてログに残し、レビュー保存自体は成功したまま |

### 1-3. 正規化タスク `lamprey:normalize_listing_ratings`

| # | 入力 | 期待する振る舞い |
|---|---|---|
| R1 | 既定（`COMMIT` 未設定） | **ドライラン**: 対象件数と内訳を出力し、DB を書き換えない |
| R2 | `COMMIT=1` | 不整合のあった出品だけを更新し、更新件数を出力する |
| R3 | 0 件なのに `avg_rating > 0` の出品 | 対象として検出（`avg_rating` を 0.0 にする） |
| R4 | `reviews_count` が実件数とずれている出品 | 対象として検出（実件数に合わせる） |
| R5 | すでに整合している出品 | 対象に数えない |
| R6 | 2 回実行（`COMMIT=1` → `COMMIT=1`） | 2 回目は対象 0 件（冪等） |

---

## 2. 実装タスク

- [x] **T1 マイグレーション** `db/migrate/*_add_reviews_count_to_listings.rb`
  - `add_column :listings, :reviews_count, :integer, default: 0, null: false`
  - 理由: 一覧カード・ランキングで「★4.2 (3件)」を出すたびに COUNT すると N+1 になるため、`avg_rating` と同時に更新する集計カラムを持つ
  - 検証: `db/structure.sql` の差分が `listings` の 1 行のみであること（`AUTO_INCREMENT` のノイズは破棄）

- [x] **T2 集計サービス** `app/services/listing_rating_service.rb`
  - `ListingRatingService.recalculate!(listing_or_id)` → 更新後の `Listing` か `nil`
  - 1 クエリで件数と平均を取得（`COUNT(*)` / `AVG(grade)`）
  - `avg_rating = (平均grade * 4 + 1).round(1)`、0 件なら `0.0` / `0`
  - `update_columns` を使い、`updated_at`・バリデーション・コールバックを巻き込まない（集計値の同期は「表示用キャッシュ」であり、出品の更新ではないため）
  - 既に同値なら書き込まない（冪等・`saved_changes` の汚染防止）

- [x] **T3 `Testimonial` のフック** `after_commit :refresh_listing_rating, on: [:create, :update, :destroy]`
  - `listing_id` が NULL のときは**何もしない**（取引レビューへの影響ゼロ）
  - update で `listing_id` が変わったときは移動元も再計算（`previous_changes`）
  - 例外は rescue して `Rails.logger.error` に残す。理由: after_commit の時点でレビューは確定済みで、ここで投げても巻き戻せない一方、投稿者に 500 を返して「投稿できたか分からない」状態を作る害が大きい。不整合は `lamprey:normalize_listing_ratings` で後から修復できる

- [x] **T4 正規化タスク** `lib/tasks/lamprey_listing_ratings.rake`
  - `bin/rails "lamprey:normalize_listing_ratings"` / `COMMIT=1` で適用
  - 対象: 「集計結果 ≠ 現在値」の出品すべて（＝0 件なのに `avg_rating > 0`、`reviews_count` 不一致を含む）
  - 出力: モード（dry-run / commit）、対象件数、出品ごとの `before → after`、内訳（`avg_rating` 変更 / `reviews_count` 変更）
  - 適用は `ListingRatingService` 経由（計算式の二重実装を避ける）

- [x] **T5 spec**
  - `spec/services/listing_rating_service_spec.rb` — S1〜S11
  - `spec/models/testimonial_rating_aggregation_spec.rb` — T1〜T6（after_commit を実際に発火させるため `:'no-transaction' => true`）
  - `spec/tasks/lamprey_normalize_listing_ratings_spec.rb` — R1〜R6

---

## 3. 非スコープ（Phase 2b へ引き継ぎ）

1. ランキング `app/controllers/rankings_controller.rb` の `order(avg_rating: :desc, ...)` — 未評価 0.0 が最下位に並ぶ／「高評価」タブの扱い
2. `app/views/listings/show.haml` の `respond_to?(:average_rating)` 門番（カラムは `avg_rating`。現状は常に「評価なし」）
3. 一覧カード・プロフィール（`people_controller.rb:44`）の表示と「評価なし」の出し分け
4. `app/models/listing.rb` の `persona_card` が `avg_rating` を返すため、API 応答の表示仕様確認
5. **「評価があるか」の判定は `reviews_count` を正とする**（`avg_rating`）で判定しない。
   migrate 直後〜`normalize` 前は「`avg_rating > 0` だが `reviews_count == 0`」という過渡状態が
   現実に存在する（既存 6 件の手動値）。`reviews_count > 0` で判定すれば過渡状態でも誤表示しない

### 3-1. リリース順序（重要）

`lamprey:normalize_listing_ratings` を Phase 2b より**先に本番実行してはいけない**。実行すると
既存 6 件の手動 `avg_rating` が 0.0 になり、2b 前の表示側（ランキングの `★ 0.0`、一覧の
「評価順」ソート、プロフィールの評価 KPI）が一時的にデグレするため。

```
1. migrate（reviews_count 追加。既存行は 0、avg_rating の手動値はそのまま残る）
2. Phase 2b をデプロイ（表示判定を reviews_count 基準にする）
3. COMMIT=1 bin/rails "lamprey:normalize_listing_ratings"   # 手動値を 0.0 へ
```

---

## 3-2. 既知の制限・判断を残した点

| 項目 | 判断 |
|---|---|
| 同時投稿での集計ずれ | 「集計 SELECT → UPDATE」は出品行をロックしない。同時 commit で古い値が残り得るが、投稿頻度が低く、次の評価イベントか `normalize` で自己修復できるため許容（`ListingRatingService` のコメントに明記） |
| `previous_changes` は直近 save のみ | 同一トランザクション内で 2 回 save し 1 回目だけ紐付けを変えた場合は移動元が漏れる。現状その経路が無いため未対応（`Testimonial` のコメントに明記） |
| `reviews_count` に counter_cache を使わない | `belongs_to :listing, counter_cache:` を後から足すと二重計上し、`listing_id` が NULL の取引レビューまで数えてしまうため（コメントに明記） |
| 再計算の失敗を握りつぶす | after_commit 時点でレビューは確定済み。投げ直しても巻き戻せず、投稿者に 500 を返す害が大きい。`Rails.logger.error`（backtrace 5 行付き）に残し、`normalize` で修復する |

---

## 4. Plan Architect レビュー結果（コードベース照合）

| 優先度 | 指摘 | 対応 |
|---|---|---|
| 🔴 | `Testimonial#grade` は DB 上 NULL 可（検証は AR のみ）。NULL 行を件数に含めると `reviews_count` と平均が食い違う | 集計対象を `grade IS NOT NULL` に限定し、計画 S1/1-1 に反映 |
| 🟡 | `lib/tasks/lamprey.rake` は**存在しない**。既存規約は `lamprey_*.rake` ごとに `namespace :lamprey` を開く複数ファイル構成（grep で 8 ファイル確認） | 新規 `lib/tasks/lamprey_listing_ratings.rake` に配置（計画 T4 を更新） |
| 🟡 | DatabaseCleaner は既定 `:transaction`。after_commit は発火しない可能性 | **実測の結果、Rails 8.1 では `:transaction` でも発火する**ため、特別なタグは不要だった（spec は既定のまま） |
| 🟡 | 集計クエリ用のインデックスは `index_testimonials_on_listing_id` のみ。`(listing_id, blocked)` 複合は無い | 現データ規模（出品 10 件）では不要と判断。本番で評価が増えたときの検討事項として 2b へ記録 |
| 🟢 | 既存 `app/services/listing_stats_service.rb` と同じ「`self.` のモジュール関数 + 日本語のなぜコメント」スタイルに揃える | そのとおり実装 |
| 🟢 | `Listing\.update_columns` は `updated_at` を更新しない | 意図どおり（表示用キャッシュの同期で出品の更新ではない）。`updates_email_at` 等にも影響なし |
| 🟢 | 命名衝突なし（`Rating` を含むクラスは `app/` `lib/` に存在しない） | `ListingRatingService` で確定 |
