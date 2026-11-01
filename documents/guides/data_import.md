# CSV インポート（ユーザー / 出品 = ペルソナ）

Issue #135。管理画面やコンソールでの手作業を置き換える、再現性のある投入経路。

- 対象: ユーザー（`Person` + `Email`）と出品（`Listing` = AI ペルソナ）
- 既定は**ドライラン**（検証だけ・書き込みなし）。`COMMIT=1` で実書き込み
- 同じ CSV を 2 回流しても重複しない（冪等）

## 1. 実行手順

```bash
# ドライラン（件数と行別エラーだけ確認する）
bin/rails "import:users[db/import/users.csv]"
bin/rails "import:listings[db/import/listings.csv]"

# 実書き込み
COMMIT=1 bin/rails "import:users[db/import/users.csv]"
COMMIT=1 bin/rails "import:listings[db/import/listings.csv]"

# 既存レコードを更新する（既定は skip）
COMMIT=1 ON_CONFLICT=update bin/rails "import:users[db/import/users.csv]"
```

- 実行順は **users → listings**。listings は `author_email` でユーザーを引くため、先にユーザーが必要
- 出力は「1 行 1 イベント + 最後にサマリ」。行番号は CSV ファイル上の物理行番号（ヘッダー行 = 1）
- エラーが 1 件でもあれば終了ステータスは `1`（CI / バッチで検知できる）。他の正常行は引き続き処理される
- **パスワードは出力されない**（平文もハッシュも出さない）

出力例:

```
ユーザーインポート: ドライラン（ON_CONFLICT=skip）
[行2] 作成: sample.taro@example.com
[行3] スキップ: dup@example.com — 同じ email のユーザーが既に存在します（ON_CONFLICT=update で更新できます）
[行4] エラー: email の形式が正しくありません（not-an-email）
---
※ ドライランです。書き込みは行っていません（実行するには COMMIT=1 を付けてください）
作成: 1 / 更新: 0 / スキップ: 1 / エラー: 1 / 警告: 0
```

## 2. 列定義

### users.csv

| 列 | 必須 | 既定 | 備考 |
|----|:----:|------|------|
| `email` | ○ | — | 形式検証あり。小文字化して登録。**冪等キー** |
| `given_name` | ○ | — | 30 文字以内 |
| `family_name` | ○ | — | 30 文字以内 |
| `display_name` | | `姓 名` | 100 文字以内 |
| `username` | | email ローカル部から生成 | `[a-z0-9_]` のみ。一意。衝突時は `_2`, `_3` … を付与 |
| `locale` | | `ja` | そのまま保存 |
| `is_admin` | | `false` | `true/false`（`1/0` `yes/no` `on/off` も可） |
| `password` | | ランダム生成 | 指定時のみ採用（4 文字以上）。**出力しない** |

- 作成されるのは `Person` と `Email`（`confirmed_at` 済み）。ログインは `Email` 経由なので、そのままログインできる
- ランダム生成したパスワードはどこにも記録されない。パスワードを知りたい場合は CSV の `password` 列で指定する（または後でパスワード再設定）

### listings.csv

| 列 | 必須 | 既定 | 備考 |
|----|:----:|------|------|
| `title` | ○ | — | 2〜65 文字。**冪等キー（+ author）** |
| `price_cents` | ○ | — | 1 以上の整数（円建ては 1 円 = 1。カンマ・小数は不可） |
| `author_email` | ○ | — | `users.csv` で投入済みのユーザー（同一コミュニティ）| 
| `description` | | 空 | 5000 文字以内（モデルの制約） |
| `skill_markdown` | | 空 | system prompt。**空だと警告が出る**（ペルソナとして動かない） |
| `category` | | 先頭のメインカテゴリ | url スラッグ or id（`ライティングアシスタント` は url ではなく名前なので不可）|
| `open` | | `true` | `true/false`（`1/0` も可） |
| `currency` | | `JPY` | 3 文字の通貨コード |
| `listing_shape` | | コミュニティの `order_type` | 出品タイプの name or id（通常は指定不要） |

- `open: true` / `state: approved` / `deleted: false` / `valid_until: nil` で作成されるので、`/ja/browse` の一覧条件（`Listing.currently_open`）にそのまま載る
- `category` 空欄の既定は「`default-category`（システム用）を除く先頭のメインカテゴリ」

## 3. 冪等性

| 対象 | キー | `ON_CONFLICT=skip`（既定）| `ON_CONFLICT=update` |
|------|------|--------------------------|----------------------|
| ユーザー | `email`（`emails.address` + コミュニティ）| スキップ | 氏名・表示名・locale・is_admin を更新（`username` / `password` は CSV 指定時のみ）|
| 出品 | `(title, author_id)`（`deleted: false` のみ）| スキップ | 説明・skill_markdown・価格・通貨・カテゴリ・出品タイプ・open を更新 |

- `deleted: true` の出品は重複とみなさない（同じ title で再作成される）
- 同じ CSV を 2 回流した場合、2 回目はすべて `skipped` になる（件数が増えない）

## 4. よくあるエラーと対処

| メッセージ | 原因 | 対処 |
|------------|------|------|
| `ファイルが見つかりません` | パス誤り | リポジトリルートからの相対パスで指定する |
| `必須の列がありません: ...` | ヘッダー名の typo / 欠落 | ヘッダーを揃える（大文字・前後空白は吸収される）|
| `見出し行に同じ列名が複数あります` | 同じヘッダーが 2 回 | どちらかを削除する |
| `email の形式が正しくありません` | 全角・空白混入など | 半角英数字のメールアドレスにする |
| `email が空です` | 空行ではなく空セル | 行ごと削除するか email を入れる |
| `author_email '...' のユーザーが見つかりません` | users 未投入 / コミュニティ違い / 削除済み | `import:users` を先に実行する |
| `price_cents は 1 以上の整数で指定してください` | 空・0・`1,000`・`1000円` | 半角数字のみにする |
| `category '...' が見つかりません` | url スラッグでも id でもない | 管理画面のカテゴリ URL（スラッグ）か ID を指定する |
| `username '...' は既に使われています` | 明示指定した username が衝突 | 別の名前を指定する（空欄にすれば自動生成）|
| `skill_markdown が空です`（警告）| skill_markdown 未設定 | system prompt を入れる（空でも作成自体は成功する）|
| `一意制約に違反しました` | 同時実行など | 時間を置いて再実行する |

## 5. 本番で流すときの注意

1. **必ずドライランを先に流す**（`COMMIT` なし）。件数とエラー行を確認してから `COMMIT=1`
2. **DB バックアップを取る**。`ON_CONFLICT=update` は既存レコードを書き換える
3. 1 行 = 1 トランザクション。エラー行があっても他の行は投入される（部分成功を許容する設計）。エラーがあれば終了ステータス 1 なので、バッチでは失敗として扱える
4. 実行順は `users` → `listings`。listings は既存ユーザーが居ないと全行エラーになる
5. コミュニティは `Community.first` 固定（現状 1 コミュニティ運用）。複数コミュニティ運用に広げる場合は `community:` を渡す経路を追加する
6. 投入したユーザーには**コミュニティメンバーシップを作らない**（`Person` + `Email` のみ）。メンバーシップが必要な運用ならフォローアップで追加する
7. 画像は取り込まない（非ゴール）。ペルソナの画像は別途設定する
8. パスワードは出力されない。CSV で指定しない限り、本人にはパスワード再設定の導線を案内する

## 6. 実装の場所

| ファイル | 役割 |
|----------|------|
| `app/services/data_import/csv_reader.rb` | BOM / ヘッダー検証 / 行の正規化 |
| `app/services/data_import/user_importer.rb` | users.csv の投入 |
| `app/services/data_import/listing_importer.rb` | listings.csv の投入 |
| `app/services/data_import/result.rb` | `created` / `updated` / `skipped` / `errors` / `warnings` の結果 |
| `app/services/data_import/console_reporter.rb` | 1 行 1 イベント + サマリの出力 |
| `app/services/data_import/coercion.rb` | 真偽値・整数の変換 |
| `app/services/data_import/dry_run.rb` | ドライラン用の検証（ロールバック付き）|
| `lib/tasks/import.rake` | rake の薄いラッパー |

ドライランと実書き込みは同じコードを通り、`commit:` フラグで書き込みの有無だけを分岐する。
ドライランは保存の代わりにモデルのバリデーションを実行して、同じエラーを行番号つきで返す。

> このリポジトリの `Person` は `before_validation` の中で `save` を呼ぶ（`set_default_preferences`）。
> そのためドライランでは `DataImport::DryRun` がトランザクションを張って必ずロールバックし、書き込みを残さない。

## 7. テスト

```bash
bundle exec rspec spec/services/data_import
```
