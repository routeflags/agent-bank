# デッドコード監査タスクの使い方と判定基準（Issue #60）

> **対象**: `lamprey:audit:dead_code`（`lib/tasks/lamprey_dead_code_audit.rake`）
> **方針**: 出力はレポートのみ。自動削除しない。
> 「参照ゼロ = 即削除」ではない。データ移行と依存の確認は別途行う。

---

## 1. 使い方

```bash
bin/rails 'lamprey:audit:dead_code'
```

出力例:

```
[lamprey:audit:dead_code] デッドコード監査レポート（Issue #60。削除はしない）
  対象: 86 テーブル・994 列

## 参照ゼロの列（63 件）
  - ai_models.context_window
  ...

## 参照ゼロのテーブル（0 件）
  なし

## 参照ゼロクラス（4 件）
  - PageLoadedJob
  ...
```

DB への書き込みは行わない（`db/structure.sql` とコードの読み取りだけ）。
本番・開発どちらの checkout でも実行できる。

---

## 2. 何を数えているか

| 監査対象 | 正本 | 参照の探索範囲 |
|----------|------|----------------|
| 列 | `db/structure.sql` の `CREATE TABLE` 配下の列定義 | `app` / `lib` / `config` / `client/app` の全文 |
| テーブル | 同上 | モデルクラス名（`people` → `Person`）またはテーブル名そのものへの言及 |
| クラス | `app/models` / `app/services` / `app/jobs` / `app/presenters` 配下の `.rb` | 定数名・スネークケース・複数形（`ShippingAddress` / `shipping_address` / `shipping_addresses`）への言及 |

クラス参照は表記ゆれを吸収する。Rails の流儀では定数ではなく
`has_many :chat_attachments` や `transaction.shipping_address` の形で
参照されるため（Issue #60 の実測で `ChatAttachment` 等の誤検知を確認し対応）。

---

## 3. 除外リスト（誤検知対策）

| 除外 | 理由 |
|------|------|
| モデルの `# == Schema Information` 注釈ブロック | 列名が必ず書かれるため、数えると全列が「参照あり」になる。`strip_schema_annotation` で除去してから数える |
| `active_storage_*` / `delayed_jobs` / `schema_migrations` / `ar_internal_metadata`（テーブルとその列） | フレームワークが名前で管理し、コード参照が無いのが正常 |
| `app/helpers` / `app/view_utils` / `app/utils` 配下のクラス定義（監査対象から除外） | Rails が名前解決・自動読み込み・文字列参照で読み込むため、参照ゼロ判定が誤検知になりやすい |
| `db/migrate` | 履歴であり現行コードの参照ではない。削除済み列に言及する古い migration があると「参照あり」に見えてしまうため数えない |
| `node_modules` / `vendor` / `tmp` / `log` / `.git` / 生成物（`.min.js` / `.map`） | 依存物・生成物のため |

注意: `app/helpers` 等は**監査対象からのみ除外**し、**参照元としては数える**。
含めないと、ヘルパー経由でしか呼ばれないクラス（例: `JsTranslations` は
`ApplicationHelper` から呼ばれる）を未参照と誤検知するため。
除外するのは「監査対象」であって「参照元」ではない。

---

## 4. 既知の限界（レポートに載らない・載りすぎる場合）

- **動的参照は拾えない**: `send(column)`、`constantize`、`"#{name}".classify` 等の
  動的解決は文字列としてしか現れない。削除前に対象名で全文検索すること。
- **locale キー**: `config/locales/*.yml` は探索範囲に含まれるため、翻訳キーに
  列名が残っていると「参照あり」になる。逆に、キーだけ残ってコード参照が無い
  列はレポートに載る。`ja.yml` の掃除は別途行う。
- **`db/seeds.rb`・`db/data` の投入口**: 探索範囲外。seed が列に値を入れている
  場合はレポートに載る（＝「参照ゼロ」でも seed が壊れる）。削除前に seed・
  factory（`spec/factories`）の言及を確認すること。
- **`delayed_jobs.handler`（実行時ペイロード）**: enqueue は定数で行う流儀
  （例: `Delayed::Job.enqueue(EmailConfirmationJob.new(...))`）のためコード側は
  拾えるが、DB に残った古いペイロードは別途確認すること。
- **テーブル判定は甘め**: モデルファイルが存在すれば「使用中」とみなす。
  モデル自体が未参照の場合は「参照ゼロクラス」に載るので、両方を見比べること。
- **名前空間の短縮参照**: 同一名前空間内の短縮参照は basename で拾えるが、
  別名（`alias`）や `delegate` 経由は拾えない。最終判断は目視。

---

## 5. 削除の判定基準（参照ゼロが出たら）

1. レポートの行を起点に、対象名で全文検索（動的参照・seed・factory・locale を確認）。
2. 列・テーブルは**データ移行の要否**を判断する。値のある行があれば Issue に記録する
   （前例: Issue #60 Phase A で `listings.publisher_name` / `version_number` の6件は
   表示・利用箇所が無いため失ってよいと判断し Issue に記録）。
3. migration は1本にまとめ、`db/structure.sql` の差分が対象だけか確認する
   （AUTO_INCREMENT 等のノイズが混ざったら戻す）。
4. 監査タスクを再実行し、消した列・テーブルが出力に出てこないことを確認する。
5. 関連 spec のみ実行（全体 `bundle exec rspec` は flake のため実行しない）。
6. 実行した監査コマンドと出力（件数）を Issue に残す。

---

## 6. 実績（Issue #60 Phase A）

- 削除: `listings.publisher_name` / `listings.version_number` /
  `people.otp_required_for_login` / `contact_requests.plan_type` /
  `checkout_accounts` テーブル。`Listing#persona_card` から2項目を除外。
- `publisher_name` / `version_number` に値のある6件は表示・利用箇所が無いため
  失ってよいと判断し、Issue #60 に記録。
- `db/structure.sql` の差分は対象のみ（AUTO_INCREMENT のノイズ6件を手戻し）。
- 再実行した監査レポート（86 テーブル・994 列）:
  参照ゼロの列 63 件・テーブル 0 件・クラス 4 件。
  削除した列・テーブルは出力に出てこない。
