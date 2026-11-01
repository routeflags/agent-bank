# Issue #106 Phase 2b — ペルソナ評価の表示（★ 4.2 (3)）

- 対象: `routeflags/agent-bank` / Issue #106
- 起点: `origin/main` = `f6eacda3e`（Phase 1 投稿導線 + Phase 2a 集計基盤 完了済み）
- 作業ブランチ: `feat/106-phase2b-rating-display`
- スコープ: **表示のみ**。`ListingRatingService`（集計式）とマイグレーションは変更しない

## 0. 前提調査（実測・コード確認済み）

| 確認対象 | 手段 | 結果 |
|---|---|---|
| 評価系カラム | `grep db/structure.sql` | `avg_rating` float DEFAULT 0 / `reviews_count` int(11) NOT NULL DEFAULT 0。**マイグレーション不要** |
| 集計の意味 | `app/[REDACTED]/listing_rating_service.rb` | `reviews_count` = `listing_id` 一致・`blocked=false`・`grade` 非 NULL の件数。0 件なら `avg_rating=0.0` |
| 出品詳細の評価表示 | `app/views/listings/show.haml:251-256` | `@listing.respond_to?(:average_rating)` 門番（カラム名は `avg_rating`）で**常に false** → 常に「評価なし」 |
| 一覧カード | `app/views/homepage/_persona_card.haml` | `★` を意図的に出さない（Issue #129 でいいね数に置換）。`.meta` に `♡ N` と価格 |
| カードの要素型 | `app/view_utils/listing_index_view_utils.rb` | `ListingItem` Struct は `reviews_count` / `avg_rating` を**持たない**（Sphinx 経由）。`respond_to?` ガードが必須 |
| ランキング | `app/controllers/rankings_controller.rb:10` | `order(avg_rating: :desc, total_sold: :desc, times_viewed: :desc)` |
| ランキング表示 | `app/views/rankings/index.haml:19-21` | 常に `★ #{avg_rating.round(1)}` → 未評価が「★ 0.0」 |
| プロフィール KPI | `app/controllers/people_controller.rb:44` | `person_listings.where("avg_rating > 0").average(:avg_rating)` |
| プロフィール KPI 表示 | `app/views/people/show.haml:81-87` | `- if @raku_stats[:avg_rating]` で**項目ごと非表示** |
| スキル表の評価列 | `app/views/people/show.haml:174-179` | `listing.avg_rating.to_f > 0` 判定 → 手動値で誤表示 |
| 既存 CSS | `_listing_detail.scss` / `_persona_cards.scss` / `_raku_pages.scss` / `_skill_table.scss` / `_monthly_summary.scss` | 既存クラス（`raku-price-box__rating[-count]` / `.agent .likes` / `.raku-rank-item__rating` / `.raku-table__rating` / `.raku-summary__value`）を再利用 |
| 既存 i18n | `config/locales/ja.yml` | `lamprey.listings.rating_none: 評価なし` / `rating_none` 系は既存。`★ 4.2 (3)` の形式に合うキーは無い |
| 開発 DB 実測 | `rails runner` | `listings=10`（`avg_rating` 手動値 6 件・`reviews_count` 全件 0）/ `testimonials=0` |

---

## 1. 決定事項（親エージェント決定・この通りに実装）

1. 「評価あり」の判定は **`reviews_count > 0`**。`avg_rating > 0` は使わない
2. 未評価は **`—`**。`★ 0.0` は出さない
3. 表示フォーマットは **`★ 4.2 (3)`**（星 + 小数 1 桁 + 件数を丸括弧）
4. ランキングの並び順は **`total_sold DESC, times_viewed DESC, avg_rating DESC`**（評価はタイブレーク）
5. 一覧カード・出品詳細・プロフィールに評価を出す。**評価が無ければカードと詳細は何も出さない**／プロフィール KPI は `—`
6. `show.haml:252` の `respond_to?(:average_rating)` 門番を `reviews_count > 0` 判定へ置換
7. i18n は `ja.yml` / `en.yml` に追加

---

## 2. 振る舞い（BDD シナリオ）

### 2-1. 判定と整形（`ListingRatingHelper`）

判定を 5 テンプレートに散らさないため、**判定と整形をヘルパーに集約**する。
公開 API は `listing_rated?` / `listing_rating_stars` / `listing_rating_count` /
`listing_rating_text` の 4 つ（すべて `preloaded:` を受ける）。

一覧カードの `@listings` は検索結果の Struct（`ListingIndexViewUtils::ListingItem`）
で集計カラムを持たないため、`HomepageController#preload_listing_rating_data` が
`{ listing_id => { avg_rating:, reviews_count: } }` を 1 クエリで先に読み、
カードが `preloaded:` で渡す（いいね数の `@listing_like_counts` と同じ形。N+1 回避）。

| # | 入力 | 期待 |
|---|---|---|
| H1 | `reviews_count=0` / `avg_rating=4.5`（正規化前の手動値） | `listing_rated? == false` / 表示は `—` |
| H2 | `reviews_count=3` / `avg_rating=4.25` | `rated? == true` / `★ 4.3 (3)`（小数 1 桁へ丸め） |
| H3 | `reviews_count=1` / `avg_rating=4.0` | `★ 4.0 (1)`（`4` ではなく `4.0`） |
| H4 | 集計カラムを持たない Struct（`ListingItem`）で `preloaded` なし | `rated? == false` / 例外を投げない |
| H5 | 同上で `preloaded: { id => 4.25/3 }` | `★ 4.3 (3)` |
| H6 | `avg_rating=nil` かつ `reviews_count=2`（異常データ） | `★ 0.0 (2)`（判定は件数なので表示は出る。不整合は正規化タスクで修復） |

### 2-2. 出品詳細 `app/views/listings/show.haml`

| # | 状態 | 期待 |
|---|---|---|
| D1 | `reviews_count=3` / `avg_rating=4.25` | `.raku-price-box__rating` が出る。値 `★ 4.3`、件数 `(3)` |
| D2 | `reviews_count=0` / `avg_rating=4.5` | `.raku-price-box__rating` が**描画されない**（罫線だけの空ブロックも残さない） |
| D3 | 出品詳細の他要素 | 価格・CTA・販売者カードの描画は不変（回帰） |

### 2-3. 一覧カード `app/views/homepage/_persona_card.haml`

| # | 状態 | 期待 |
|---|---|---|
| C1 | `reviews_count=3` | `.meta` に `★ 4.3 (3)`（`.agent .rating`）が出る |
| C2 | `reviews_count=0` / `avg_rating=4.5` | `★` を**出さない**。`♡ N` と価格は不変 |
| C3 | `ListingItem` Struct（`/browse` のスライダー経由） | `★` を出さず例外も出さない |

### 2-4. ランキング `rankings_controller.rb` + `rankings/index.haml`

| # | 状態 | 期待 |
|---|---|---|
| R1 | 未評価（`reviews_count=0`・手動 `avg_rating=4.5`） | 表示は `—`（`★ 4.5` も `★ 0.0` も出さない） |
| R2 | 評価あり | `平均評価: ★ 4.3 (3)` |
| R3 | `total_sold` が違う | `total_sold` の降順（`avg_rating` は見ない） |
| R4 | `total_sold` 同点・`times_viewed` が違う | `times_viewed` の降順 |
| R5 | `total_sold` / `times_viewed` 同点 | `avg_rating` の降順（評価ありが上） |
| R6 | 全キー同点 | `id` 昇順（順序を決定的にする） |
| R7 | 非公開・上限 | `currently_open` のみ・20 件上限は不変 |

### 2-5. プロフィール `people_controller.rb` + `people/show.haml`

| # | 状態 | 期待 |
|---|---|---|
| P1 | 評価のある出品が 1 件（`avg_rating=4.25`） | KPI「平均評価」= `★ 4.3`（評価ありの出品だけの平均） |
| P2 | 評価のある出品が 1 件も無い（手動 `avg_rating` のみ） | KPI 項目は**出る**。値は `—` |
| P3 | スキル表の評価列・評価あり | `★ 4.3 (3)` |
| P4 | スキル表の評価列・未評価（手動 `avg_rating=4.5`） | `—`（`★ 4.5` を出さない） |
| P5 | 出品が 0 件のユーザー | KPI は `—`、他 KPI（出品数・閲覧数・トークン）は不変 |

### 2-6. i18n

| キー | ja | en |
|---|---|---|
| `lamprey.listings.rating_stars` | `★ %{rating}` | `★ %{rating}` |
| `lamprey.listings.rating_count` | `(%{count})` | `(%{count})` |
| `lamprey.listings.rating_dash` | `—` | `—` |
| `lamprey.rankings.lead`（変更） | 販売実績・閲覧数・平均評価の順に並べたペルソナの一覧です。 | Personas ranked by sales, views, and average rating. |

既存の `lamprey.listings.rating_none`（評価なし）は未評価セルの `title` / 読み上げ用に再利用する。

---

## 3. 変更ファイル一覧（予定）

| ファイル | 役割 |
|---|---|
| `app/helpers/listing_rating_helper.rb` | 新規。`listing_rated?` / `listing_rating_stars` / `listing_rating_count` / `listing_rating_text`（`preloaded:` 付き） |
| `app/controllers/homepage_controller.rb` | 新規 `preload_listing_rating_data`（カード用の N+1 回避） |
| `app/views/listings/show.haml` | `respond_to?(:average_rating)` 門番を撤去し `listing_rated?` で出し分け |
| `app/views/homepage/_persona_card.haml` | `.meta` に評価（`.agent .rating`）を条件付きで追加 |
| `app/assets/stylesheets/components/_persona_cards.scss` | `.agent .rating` のスタイル（CSS 変数） |
| `app/controllers/rankings_controller.rb` | 並び順を `total_sold, times_viewed, avg_rating, id` に変更 |
| `app/views/rankings/index.haml` | `★ 0.0` をやめ、未評価は `—` |
| `app/assets/stylesheets/components/_raku_pages.scss` | `.raku-rank-item__rating-none` / `-count` |
| `app/controllers/people_controller.rb` | KPI の平均を `reviews_count > 0` 基準に |
| `app/views/people/show.haml` | KPI を常時表示（未評価は `—`）、スキル表の判定を差し替え |
| `config/locales/ja.yml` / `en.yml` | 上記 i18n キー追加 |
| spec 4〜5 本 | ヘルパー単体・出品詳細・カード・ランキング・プロフィール |

---

## 4. 検証方針

- `bundle exec rspec`（関連 spec + 既存回帰）。既存失敗は main と集合比較
- `rails runner` で「評価あり / なし」を実データで確認し、作成分は削除して件数を報告
  （**開発サーバーは起動しない**。親が `:3000` で稼働中）
- 正規化タスク（`lamprey:normalize_listing_ratings`）は **2b デプロイ後**に実行する運用のため、
  今回はドライランのみ（DB を書き換えない）
