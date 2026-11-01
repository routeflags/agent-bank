# Issue #135 CSV インポート経路（ユーザー / 商品 = ペルソナ出品）実装計画書（BDD）

- 作成日: 2026-11-01
- 対象: `routeflags/agent-bank` / ブランチ `feat/135-csv-import`（基点 `origin/main` = `18fa78d27`）
- 根拠ツール:
  - `read_file/grep: app/models/person.rb・email.rb・listing.rb・listing_shape.rb・category.rb` で必須属性・バリデーション・既定値を確認
  - `read_file: app/services/listing_index_service/search/database_search_helper.rb` で `/browse` の抽出条件（`Listing.currently_open`）を確認
  - `read_file: lib/tasks/lamprey_demo_personas.rake` で既存のペルソナ出品の実データ（title / price_cents / category_id / open）を確認
  - `bin/rails runner: Community.first / ListingShape / Listing / Category` で実測（community_id=6、既定 shape = `order_type`(id 14)、既存ペルソナ出品は price_cents=1000・currency=JPY・open=true・state=approved）
  - `grep: app/services/result.rb` → **トップレベル `Result`（Success/Error モナド）が既存**。名前衝突を避けるため戻り値は `DataImport::Result` に置く
- 決定事項（オーナー確認なしで決めた仮定）:
  1. ロジックは `app/services/data_import/` に置き、`DataImport::` 名前空間にする（`app/services` は Zeitwerk の autoload root なので `data_import/` 配下は `DataImport::` になる）
  2. 冪等キーは users = `email`（`emails.address` + `community_id`）、listings = `(title, author_id)`
  3. `listing_shape` は既定で `ListingShape::DEFAULT_BASENAME`（`order_type`）。CSV で上書き可（name or id）
  4. `category` 空欄時の既定は「`default-category`（システム用）を除く先頭のメインカテゴリ」
  5. ドライランは「書き込みをしないフラグ」だけを分岐に使い、レコード生成・バリデーション・重複判定のロジックは共通
  6. パスワードは生成しても出力しない（`Result` に値を持たせない）

## T1: CSV 読み込み（`DataImport::CsvReader`）

- 振る舞い: UTF-8(BOM 可) の CSV を読み、ヘッダーを `strip` + `downcase` で正規化し、必須列が揃っていることを検証する。行は「正規化ヘッダー => 値を strip した文字列（空文字は nil）」に変換し、物理行番号（1 始まり・ヘッダー行を 1 とする）を持つ。
  - 正常系: `email,given_name,family_name` + 1 行 → 1 行（line=2）が返る。BOM 付き・ヘッダーの前後空白・大文字ヘッダーでも同じ結果。
  - 異常系: ファイル無し / 空ファイル / 必須列欠落 / ヘッダー重複 / CSV 構文エラー → `InvalidFileError`（メッセージは日本語）。
  - エッジ: 全列空の行は無視。宣言していない列は `ignored_columns` として返し、行の処理は継続（typo を見逃さないため rake が警告表示）。
- 実装: `app/services/data_import/csv_reader.rb`
- 検証: importer spec 経由（生成した一時 CSV）+ runner での実ファイル読み込み

## T2: ユーザー投入（`DataImport::UserImporter`）

- 振る舞い: 1 行 = 1 ユーザー。`Person` + `Email`（`confirmed_at` 済み）を作る。`commit: false` では一切書き込まない。
  - 正常系: 必須 3 列が揃った行 → `Person` 1 件 + `Email` 1 件（`community_id` は作成先コミュニティ）。`display_name` 省略時は `"姓 名"`、`locale` 省略時 `ja`、`is_admin` 省略時 `0`、`password` 省略時はランダム（出力しない）。`username` 省略時は email ローカル部から `[a-z0-9_]` に正規化して生成し、衝突時は `_2`, `_3` … を付ける。
  - 異常系: email 空 / 形式不正、`given_name`・`family_name` 空、`is_admin` が真偽値でない、`username` の書式不正・他者と重複、`password` が 4 文字未満 → その行だけ `errors`（行番号つき）にし、他行は続行。
  - エッジ: 既存 email の行は `ON_CONFLICT=skip`（既定）で `skipped`、`update` でプロフィール更新（`updated`）。パスワードは CSV 指定時のみ更新。氏名の長さ超過（given/family 30 / display 100 文字）は行エラー。
- 実装: `app/services/data_import/user_importer.rb`
- 検証: `spec/services/data_import/user_importer_spec.rb`

## T3: 出品（ペルソナ）投入（`DataImport::ListingImporter`）

- 振る舞い: 1 行 = 1 出品。`author_email` から既存ユーザーを引き、`Listing` を作る。`commit: false` では一切書き込まない。
  - 正常系: `title` + `price_cents` + `author_email` → `Listing` 1 件（`open: true` / `state: approved` / `deleted: false` → `Listing.currently_open` に載る）。`currency` 省略時 `JPY`、`open` 省略時 `true`、`category` は url スラッグ or id、空欄は既定カテゴリ、`listing_shape` は既定 `order_type`。
  - 異常系: `title` 空 / 2 文字未満 / 65 文字超、`price_cents` が整数でない・0 以下、`author_email` のユーザーが居ない、`category` が見つからない、`currency` が 3 文字英大文字でない、`open` が真偽値でない → 行エラー（他行は続行）。
  - エッジ: `skill_markdown` 空は作成しつつ `warnings` に行番号つき警告。同一 `(title, author_id)` は `skip`（既定）/ `update`。`deleted: true` の同タイトルは重複と見なさない。
- 実装: `app/services/data_import/listing_importer.rb`
- 検証: `spec/services/data_import/listing_importer_spec.rb`

## T4: 結果オブジェクト（`DataImport::Result`）

- 振る舞い: `created` / `updated` / `skipped` / `errors` / `warnings` を行番号つきで保持し、`summary` で件数を返す。ドライランと実書き込みで同じ形を返す。
- 実装: `app/services/data_import/result.rb`

## T5: rake（薄いラッパー）+ コンソール出力

- 振る舞い: `bin/rails "import:users[path]"` / `bin/rails "import:listings[path]"`。既定はドライラン、`COMMIT=1` で実書き込み、`ON_CONFLICT=skip|update`（既定 `skip`）。出力は 1 行 1 イベント + 最後にサマリ。パスワードは出力しない。`errors` が 1 件以上なら終了ステータス 1。
  - 異常系: パス未指定 / 不正な `ON_CONFLICT` / 読み込み失敗 → 理由を出して終了ステータス 1。
- 実装: `lib/tasks/import.rake` + `app/services/data_import/console_reporter.rb`

## T6: サンプル CSV / ドキュメント

- `db/import/users.csv` / `db/import/listings.csv`（ヘッダー + 1 行、実在しないダミー）
- `documents/guides/data_import.md`（実行手順 / 列定義 / 冪等性 / よくあるエラー / 本番注意）

## 非ゴール（Issue 準拠）

- 管理画面 UI、画像の一括取り込み、既存データのエクスポート

## 検証結果（実測）

- `bundle exec rspec spec/services/data_import` → 37 examples, 0 failures
- `bundle exec rubocop app/services/data_import lib/tasks/import.rake spec/services/data_import` → 10 files, no offenses
- 開発 DB での E2E（サンプル CSV）: ドライラン 1 件 → COMMIT 1 件 → 2 回目 1 件 skipped。`ON_CONFLICT=update` で 1 件 updated
- 作った出品は `Listing.currently_open` に含まれ、`curl http://localhost:3000/ja/browse` の HTML にもタイトルが出ることを確認（検証後に削除済み）
- 発見した落とし穴: `Person` は `before_validation` 内で `save` を呼ぶ（`set_default_preferences`）ため、
  ドライランで `valid?` を呼ぶだけで INSERT が走る。`DataImport::DryRun` でトランザクション＋ロールバックして回避している
