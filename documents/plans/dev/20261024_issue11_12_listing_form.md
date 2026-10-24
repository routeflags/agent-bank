# Issue #11 / #12: 出品フォームの実行モード・場所入力削除 — 実装計画

作成日: 2026-10-24
対象: routeflags/agent-bank（Lamprey）
ブランチ: `feat/agent-bank`
関連 Issue: routeflags/agent-bank#11, #12

---

## 1. 背景と目的

AI ペルソナ出品では利用しない「AI実行モード」と「場所」を new / edit 共通フォームから削除する。
実行モード欄を単純に削除すると、DB と従来の組み立て処理の既定値 `download` により ChatPanel が表示されなくなるため、フォーム経由の新規出品を `run_online` に固定する。

## 2. スコープ

### 実施する

- `_form_content.haml` から `run_mode` と `origin` の partial 呼び出しを削除する。
- フォーム値がない場合の新規出品の既定を `run_online` にする。
- 編集時は既存の `default_run_mode` を維持する。
- origin パラメータがない create / update を安全に処理する。
- view utility とテンプレート構造の回帰テストを追加する。
- 到達経路が無くなった `_run_mode.haml` / `_origin.haml` / `_googlemap.haml`（フォーム用）を削除する。

### 実施しない

- `show_location?` の削除（一覧表示形式等でも利用されるため）。
- 既存出品のデータ移行（開発 DB の既存出品はすべて `run_online` と実測済み）。
- `_googlemap.haml`、`_origin.haml`、`_run_mode.haml` の共有元の将来利用を考慮した保持（→ 実際は削除した。フォームからの参照が無く、他画面からの参照も無いため。§6 参照）。
- 未使用になった翻訳キーの削除（全ロケール横断の変更になるため見送り）。

## 3. 振る舞い定義（BDD）

| # | 前提 | 操作 | 期待結果 |
|---|------|------|----------|
| B1 | ログイン済み | new / edit フォームを表示 | 場所・AI実行モード入力が描画されない |
| B2 | origin / default_run_mode なし | `POST /ja/listings` | 出品が作成され、`default_run_mode` は `run_online`、`supported_run_modes` は `["run_online"]` |
| B3 | `default_run_mode=download` の既存出品 | 両パラメータなしで `PATCH /ja/listings/:id` | 更新に成功し、実行モードと対応モード配列は `download` のまま |
| B4 | 場所表示設定が有効 | origin なしで POST / PATCH | nil 参照例外を起こさない |

## 4. 設計判断

`build_listing_params` に `default_run_mode:` キーワード引数（既定 `run_online`）を追加する。create は既定値を利用し、update は既存出品の値を渡す。
コントローラで params を改変する方式より、`default_run_mode` と `supported_run_modes` を同時に導出する既存の責務を view utility に保てるためである。

origin の create 前処理はフォームから送信されず、nil を直接参照していたため削除する。update の既存 origin 削除処理はレガシー入力との互換性のため維持し、location 更新のみパラメータがある場合に限定する。

## 5. 受入条件

- [x] 共通出品フォームから場所欄と実行モード欄の render が除去されている。
- [x] utility の新規既定・編集維持を unit spec で検証する。
- [x] フォーム構造（partial 参照が無いこと）を spec で検証する。
- [x] 指定された spec 群、RuboCop、Zeitwerk が成功する。
- [x] 可能であれば全 spec を実行し、失敗を切り分ける。

> 実 HTTP リクエストの spec は見送った。Sharetribe のセッションストア（`sessions` / `active_sessions`）
> がらみで、request spec からのトークンログインが POST 時に復元されず、本体コードと無関係な
> 不安定要因になるため（GET は 200、GET /listings/new は描画 500、POST は login へ 302 と挙動が揺れる）。
> 代わりに「入力欄が描画されない」ことを `spec/views/listings/form_content_structure_spec.rb` で、
> 「フォームが送らない value をサーバが run_online に確定する」「既存の download を維持する」
> ことを `spec/view_utils/listing_form_view_utils_spec.rb` で固定している（B2 / B3 相当）。
> HTTP レベルの通し確認（実フォーム送信）は自動化できていないので、リリース前に手作業で
> `/ja/listings/new` から出品し、`default_run_mode` が `run_online` になることを目視で確認すること。

## 6. 検証記録

検証環境: クリーンビルド相当（`app/assets/webpack` にビルド済みアセット、`i18n` エクスポート済み）、
ローカル MySQL。

| コマンド | 結果 |
|---|---|
| `bundle exec rspec spec/view_utils spec/views spec/controllers/listings_controller_spec.rb spec/requests spec/models` | **541 examples, 1 failure** |
| 上記失敗（`spec/models/numeric_field_value_spec.rb:80`）の isolated 再実行 | **3 examples, 0 failures**（既存の実行順序依存 flaky） |
| `bundle exec rubocop`（変更した rb 4 ファイル） | no offenses |
| `RAILS_ENV=test rails zeitwerk:check` | all is good |

判断の補足（計画からの変更）:

- 計画では未使用 partial の削除を「実施しない」としていたが、実際に削除した。
  `_run_mode.haml` / `_origin.haml` / `form/_googlemap.haml` は本変更でフォームからの
  参照がゼロになり、他画面からの参照も無い（grep 確認）。残すと「フォームに欄がある」
  と誤認しやすい死んだコードになるため。
- 翻訳キー（`listings.form.run_mode.*` 等）は全ロケール横断になるため削除していない。
