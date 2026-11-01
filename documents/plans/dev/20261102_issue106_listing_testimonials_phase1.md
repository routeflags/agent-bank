# Issue #106 Phase 1 — 既存 `Testimonial` を流用した「ペルソナ評価」投稿導線

- 対象: `routeflags/agent-bank` / Issue #106（案A: `Testimonial` 流用）
- スコープ: **Phase 1 のみ**（投稿導線）。`listings.avg_rating` の再計算・ランキング／カード表示の改修は Phase 2。
- 前提調査（本計画で実測・確認したもの）:
  - `app/models/testimonial.rb` — `grade` は `0..1` の inclusion 検証のみ。`transaction_id` は `tx` 経由（`belongs_to :tx`）。`displayed_grade` = `(grade*4+1).to_i`。
  - `app/controllers/testimonials_controller.rb` — 既存は取引（`params[:message_id]`）起点。`ensure_authorized_to_give_feedback` が `message_id` を要求するため、出品起点の投稿は同居できない。
  - `app/models/chat_session.rb` — `listing_id` / `person_id` / `status`。`person_id` は `Person#id`（varchar(22)）。
  - `app/models/chat_message.rb` — `role` は `user` / `assistant` / `system`。`assistant?` 述語あり。
  - `config/routes.rb` 118 行目 `scope "(/:locale)"` 配下、537 行目 `resources :listings` にネストを足せば `/ja/listings/:listing_id/...` になる（`resources :comments` と同じ形。`spec/requests/listing_comments_spec.rb` で実績あり）。
  - `app/[REDACTED]/policy/listing_policy.rb` — `Policy::` 名前空間の PORO が既存パターン。
  - `spec/factories.rb` — `:chat_session` / `:chat_message` / `:testimonial` ファクトリあり。
  - 開発 DB 実測: `testimonials` 0 件 / `chat_sessions` 28 件 / `listings` 10 件。

---

## 1. 振る舞い（BDD シナリオ）

### 1-1. 投稿条件の判定（`Policy::ListingReviewPolicy`）

| # | シナリオ | 期待する振る舞い |
|---|---------|------------------|
| S1 | 出品で AI 応答（assistant メッセージ）が 1 件以上ある `ChatSession` を持つ利用者 | `can_create? == true` |
| S2 | 出品者本人 | `can_create? == false`（`author? == true`） |
| S3 | チャット履歴はあるが assistant が 0 件（user のみ） | `can_create? == false` |
| S4 | チャット履歴が無い／別出品のセッションのみ | `can_create? == false` |
| S5 | 未ログイン | `can_create? == false`（nil 安全） |
| S6 | 同じ人が既に評価済み | `can_create? == false` / `already_reviewed? == true` |
| S7 | 他人の assistant 応答セッションがあるだけ（自分は user のみ） | `can_create? == false`（判定は本人のセッションに限る） |

### 1-2. 投稿（`ListingTestimonialsController#create`）

| # | 入力 | 期待する振る舞い |
|---|------|------------------|
| C1 | S1 の利用者が `stars=5, text="よかった"` | `Testimonial` が 1 件増える。`listing_id`=出品, `author_id`=評価者, `receiver_id`=出品者, `transaction_id`=NULL, `grade`=1.0。フラッシュ notice → 出品詳細へリダイレクト |
| C2 | 同条件で 2 回目 | 増えない。エラーフラッシュ → 出品詳細へリダイレクト |
| C3 | 出品者本人（S2） | 増えない。エラーフラッシュ |
| C4 | assistant 0 件のセッションのみ（S3/C4） | 増えない。エラーフラッシュ |
| C5 | 未ログイン | 増えない。ログインページへリダイレクト（既存 `ensure_logged_in`） |
| C6 | `text` 空（`stars=3`） | 保存できる（本文は任意） |
| C7 | `stars` 欠落 / `0` / `6` | 保存できない（`grade` が nil になり inclusion 検証で落ちる）。エラーフラッシュ |
| C8 | `text` が 1000 文字超 | 保存できない（長さ検証）。エラーフラッシュ |
| C9 | DB レベルの重複（同一 `listing_id` + `author_id` を直接 INSERT） | unique index で拒否される |

### 1-3. 星 → grade 換算（`Testimonial.grade_from_stars`）

| stars | grade | displayed_grade |
|-------|-------|-----------------|
| 1 | 0.0 | 1 |
| 2 | 0.25 | 2 |
| 3 | 0.5 | 3 |
| 4 | 0.75 | 4 |
| 5 | 1.0 | 5 |
| ""/nil/0/6/"abc" | nil | — |

### 1-4. 表示（出品詳細 `listings/show`）

| # | 状態 | 期待する振る舞い |
|---|------|------------------|
| V1 | S1 の利用者 | 「このペルソナを評価する」フォーム（星セレクト＋本文＋送信）が出る |
| V2 | 出品者本人 | フォームは出ない |
| V3 | assistant 応答なしの利用者 | フォームは出ない |
| V4 | 未ログイン | フォームは出ない |
| V5 | 評価済み（S6） | フォームの代わりに「評価済み」文言 |

---

## 2. 実装タスク

- [x] **T1 マイグレーション**: `testimonials.listing_id`（integer, NULL 可）＋ `index_testimonials_on_listing_id`。「1人1出品1回」を DB でも担保するため `(listing_id, author_id)` の unique index も張る（MySQL は NULL を重複扱いしないので既存取引レビュー＝`listing_id NULL` には無影響）。
- [x] **T2 モデル（Testimonial）**: `belongs_to :listing, optional: true` / `TEXT_MAX_LENGTH = 1000` / `grade_from_stars` / 出品レビュー限定の任意本文長検証・重複検証（`if: -> { listing_id.present? }` で既存取引フローを汚さない）/ schema annotation 更新。
- [x] **T3 モデル（ChatSession）**: `scope :with_assistant_message`（assistant 応答ありの絞り込み）。
- [x] **T4 ポリシー**: `Policy::ListingReviewPolicy#can_create?` / `#already_reviewed?` / `#used_persona?` / `#author?`。
- [x] **T5 ルーティング**: `resources :listings do resources :testimonials, only: :create, controller: 'listing_testimonials' end`（`POST /:locale/listings/:listing_id/testimonials`）。既存 `/:person_id/testimonials` とはパス・ヘルパーとも非衝突。
- [x] **T6 コントローラ**: `ListingTestimonialsController#create`（ログイン必須 → 出品解決 → 適格判定 → 星→grade 換算して保存 → flash＋リダイレクト。`RecordNotUnique` は「評価済み」扱い）。
- [x] **T7 ビュー**: `app/views/listings/_listing_review_form.haml`（条件不成立なら何も出さない）を `show.haml` のチャットパネル直後に描画。
- [x] **T8 スタイル**: `_listing_review_form.scss`（テーマ非依存の CSS 変数で両テーマ対応）。
- [x] **T9 i18n**: `ja.yml` / `en.yml` に `lamprey.listings.review_*` と `layouts.notifications.listing_review_*` を追加。
- [x] **T10 spec**: モデル（換算・検証）、リクエスト（C1〜C9）、ビュー（V1〜V5）。
- [x] **T11 検証**: `bundle exec rspec` 対象 spec、`rails runner` で実測（作成→2回目拒否→出品者拒否→AI応答なし拒否）、`db:migrate` と `db/structure.sql` 差分確認、作成分の後始末。

---

## 3. 影響範囲と非目標

- 既存の取引レビュー（`/:person_id/messages/:message_id/feedbacks`、`TestimonialsController`）は**触らない**。
- `listings.avg_rating` の再計算、ランキング／カードの表示改修、`people/_testimonials.haml` のデッドコード整理は **Phase 2**。
- 投稿完了メール（`TestimonialGivenJob`）は Phase 1 では enqueue しない（宛先・文面が取引前提のため）。Phase 2 で判断。
