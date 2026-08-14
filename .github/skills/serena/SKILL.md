---
name: serena
description: |
  Serena MCP を使ったシンボルレベルのコード探索・リファクタリング・診断。
  「シンボル見つけて」「この関数を呼んでる箇所」「リネームして」「エラーある？」「ファイルの構造教えて」
  など、grep より構造的・正確なコード操作が必要なときに使う。
  Codebase Memory（ナレッジグラフ）と違い、Serena は LSP ベースでシンボルレベルの操作が可能。
---

# Serena — シンボルレベルのコード操作

Serena は LSP（Language Server Protocol）ベースの MCP で、grep/read では難しい「シンボルの宣言・参照・リネーム・body 置換」を正確に行える。

## grep/read vs Serena — 使い分け

| やりたいこと | grep/read | Serena | 推奨 |
|------------|-----------|--------|------|
| キーワード検索 | ✅ 高速 | ❌ 遅い | grep |
| シンボルの宣言元を探す | ❌ 误 match 多発 | ✅ 精確 | **Serena** |
| 関数の呼び出し元を全件洗い出し | ❌ 文字列一致 | ✅ シンボル一致 | **Serena** |
| インターフェースの実装クラス検索 | ❌ 不可能 | ✅ `find_implementations` | **Serena** |
| リネーム（全箇所一括） | ❌ 危険 | ✅ LSP 連携 | **Serena** |
| ファイル構造の把握 | `cat` + 手動 | ✅ `get_symbols_overview` | **Serena** |
| エラー/警告の取得 | ❌ 不可能 | ✅ `get_diagnostics` | **Serena** |
| コードの置換（大量ファイル） | `sed` / Edit | ✅ `replace_in_files` | 状況による |
| ファイル検索 | Glob | `find_file` | ほぼ同等 |

## クイック判断マトリクス

| 質問 | ツール呼び出し |
|------|--------------|
| この関数の宣言はどこ？ | `serena_find_declaration` |
| この関数は誰が呼んでいる？ | `serena_find_referencing_symbols` |
| このインターフェースの実装は？ | `serena_find_implementations` |
| このファイルの全シンボル一覧は？ | `serena_get_symbols_overview` |
| このシンボルのパターンに一致するものは？ | `serena_find_symbol` |
| このファイルにエラーはある？ | `serena_get_diagnostics_for_file` |
| シンボルをリネームしたい | `serena_rename_symbol` |
| このシンボルの body を差し替えたい | `serena_replace_symbol_body` |
| このシンボルを安全に削除したい | `serena_safe_delete_symbol` |
| 複数ファイルで一括置換したい | `serena_replace_in_files` |
| 正規表現でパターン検索 | `serena_search_for_pattern` |

---

## ワークフロー 1: シンボル探索

### 1-1. 関数/クラスの宣言を探す

```
# 名前で検索（部分一致）
serena_find_symbol(name_path_pattern="TransactionProcessStateMachine")

# 絶対パスで検索
serena_find_symbol(name_path_pattern="/app/models/transaction.rb")

# ディレクトリを指定して検索
serena_find_symbol(name_path_pattern="transition_to", relative_path="app/")
```

**出力例:**
```json
{
  "name_path": "TransactionProcessStateMachine/transition",
  "location": {
    "relative_path": "app/state_machines/transaction_process_state_machine.rb",
    "start_line": 23,
    "end_line": 29
  }
}
```

### 1-2. メソッドの宣言を詳細に取得

```
serena_find_declaration(
  relative_path="app/state_machines/transaction_process_state_machine.rb",
  regex="def (transition)"
)
```

`include_body=True` を付けるとボディも返す。

### 1-3. ファイルのシンボル構造を概観

```
serena_get_symbols_overview(relative_path="app/models/transaction.rb")
```

**出力例:**
```json
{
  "classes": [{"name": "Transaction", "methods": ["current_state", "status"]}],
  "modules": [],
  "methods": []
}
```

---

## ワークフロー 2: 依存関係の追跡

### 2-1. この関数を誰が呼んでいるか（inbound）

```
serena_find_referencing_symbols(
  name_path="TransactionProcessStateMachine",
  relative_path="app/state_machines/transaction_process_state_machine.rb"
)
```

### 2-2. この関数が何を呼んでいるか（outbound）

```
serena_find_symbol(
  name_path_pattern="transition_to!",
  depth=1,
  include_body=True
)
```

### 2-3. インターフェースの実装クラスを探す

```
serena_find_implementations(
  name_path="Statesman::Adapters::ActiveRecordTransition",
  relative_path="app/models/transaction_transition.rb"
)
```

---

## ワークフロー 3: リファクタリング

### 3-1. シンボルリネーム（全箇所一括）

```
serena_rename_symbol(
  name_path="Wallet#deduct_for_usage!",
  relative_path="app/models/wallet.rb",
  new_name="deduct_for_ai_usage!"
)
```

**⚠️ 注意**: リネーム前必ず `serena_find_referencing_symbols` で影響範囲を確認。

### 3-2. シンボルの body を置換

```
serena_replace_symbol_body(
  name_path="UserPlanSubscription#current_state",
  relative_path="app/models/user_plan_subscription.rb",
  body="def current_state\n  most_recent_transition&.to_state || 'active'\nend"
)
```

### 3-3. 安全なシンボル削除（参照チェック付き）

```
serena_safe_delete_symbol(
  name_path_pattern="OldServiceMethod",
  relative_path="app/services/old_service.rb"
)
```

参照があれば一覧が返され、削除は実行されない。

### 3-4. シンボルの前にコードを挿入

```
serena_insert_before_symbol(
  name_path="Wallet#topup!",
  relative_path="app/models/wallet.rb",
  body="# @deprecated Use topup_with_stripe! instead\ndeprecation_warning('topup! is deprecated')"
)
```

---

## ワークフロー 4: パターン検索

### 4-1. 正規表現でコード検索

```
serena_search_for_pattern(
  substring_pattern="include Statesman::Machine",
  context_lines_before=2,
  context_lines_after=2
)
```

**grep より優れている点**: シンボル境界を理解している。関数定義内の誤 match が少ない。

### 4-2. ファイル検索

```
serena_find_file(
  file_mask="*_state_machine.rb",
  relative_path="app/"
)
```

---

## ワークフロー 5: ファイル操作

### 5-1. ファイルの内容を読み込み

```
serena_read_file(relative_path="app/models/wallet.rb", start_line=1, end_line=50)
```

### 5-2. ファイルを作成

```
serena_create_text_file(
  relative_path="app/services/new_service.rb",
  content="# frozen_string_literal: true\n\nclass NewService\n  def call\n    # TODO\n  end\nend"
)
```

### 5-3. 複数ファイルで一括置換

```
serena_replace_in_files(
  needle="Statesman::Machine",
  repl="Statesman::Adapters::ActiveRecordTransition",
  mode="literal",
  relative_path="app/models/",
  dry_run=True  # まず確認
)
```

dry_run の結果を確認してから `dry_run=False` で実行。

---

## ワークフロー 6: 診断

### 6-1. ファイル単位のエラー/警告取得

```
serena_get_diagnostics_for_file(
  relative_path="app/models/user_plan_subscription.rb",
  min_severity=2  # Warning 以上
)
```

### 6-2. プロジェクト全体の診断

```
serena_get_current_config
```

---

## Sharetribe プロジェクト固有の使い方

### Statesman の transition パターン検索

```
serena_search_for_pattern(
  substring_pattern="transition from:.*to:",
  restrict_search_to_code_files=True
)
```

→ 既存のステートマシン定義が全て見つかる。

### EntityUtils パターン検索

```
serena_search_for_pattern(
  substring_pattern="EntityUtils.define_builder",
  restrict_search_to_code_files=True
)
```

### Sharetribe のサービス層パターン検索

```
serena_find_symbol(
  name_path_pattern="Store",
  relative_path="app/services/",
  depth=1
)
```

### `app/Customize/` vs `src/Eccube/` の使い分け確認

```
serena_list_dir(relative_path="app/", recursive=False)
```

→ `Customize/` にカスタマイズ、`Plugin/` にプラグイン。`src/Eccube/` はコア（触らない）。

---

## メモリ操作

Serena はプロジェクト固有のメモリを保持できる。

```
# メモリ一覧
serena_list_memories(topic="architecture")

# メモリ書き込み
serena_write_memory(
  memory_name="arch/state-machines",
  content="## Statesman パターン\n- モデルに include せず別クラスで定義\n- transition from:/to: のみ（on: なし）\n- transition_to! で遷移"
)

# メモリ読み込み
serena_read_memory(memory_name="arch/state-machines")

# メモリ編集
serena_edit_memory(
  memory_name="arch/state-machines",
  needle="transition from:/to: のみ",
  repl="transition from:/to: のみ（on: キーワードなし）",
  mode="literal"
)
```

---

## Gotchas

1. **`serena_find_symbol` は部分一致**: `name_path_pattern="transition"` は `transition_to!` もヒットする。正確な名前がわからない場合はまずこっちで探す。
2. **`relative_path` はプロジェクトルートからの相対**: `/Users/bookair18/...` ではなく `app/models/wallet.rb` のように。
3. **`depth` は子シンボルの取得深度**: クラスのメソッド一覧が欲しいなら `depth=1`。
4. **`include_body=True` は遅い**: C/C++ では特に。Ruby なら問題ないが、大量取得は避ける。
5. **`replace_in_files` は dry_run を必ず先に**: 予期しない置換を防ぐ。
6. **`serena_rename_symbol` は LSP 連携**: grep でのリネームより安全だが、文字列リテラル内の同名は変更されない。
7. **`serena_search_for_pattern` は `grep` より遅い**: 大量ファイル検索では grep を優先。
8. **Codebase Memory と組み合わせる**: Serena は「シンボル操作」、Codebase Memory は「構造クエリ（グラフ）」。両方使えば網羅的。
