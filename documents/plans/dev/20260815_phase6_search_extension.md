# Phase 6: 検索拡張 — AI ペルソナ検索

## 概要

既存の Sphinx/DB 検索に AI ペルソナ固有のフィルタリング機能を追加する。
ユーザーが「run_online」ペルソナだけを検索したり、特定の AI モデルを持つペルソナを絞り込んだりできるようにする。

## 既存コードベースの状態

### 検索基盤

| コンポーネント | ファイル | 状態 |
|---------------|---------|------|
| SearchEngineAdapter | `app/services/listing_index_service/search/search_engine_adapter.rb` | ✅ インターフェース定義済み |
| SphinxAdapter | `app/services/listing_index_service/search/sphinx_adapter.rb` | ✅ Sphinx 検索 |
| DatabaseSearchHelper | `app/services/listing_index_service/search/database_search_helper.rb` | ✅ DB 検索 |
| Listing スコープ | `app/models/listing.rb` | ✅ `search_title_author_category` 等 |

### AI ペルソナ関連

| コンポーネント | ファイル | 状態 |
|---------------|---------|------|
| ペルソナフィールド | `app/models/listing.rb` | ✅ `default_run_mode`, `supported_run_modes`, `external_apis` |
| AI モデル紐付け | `app/models/listing_ai_model.rb` | ✅ `is_default` フラグ |
| AI モデル | `app/models/ai_model.rb` | ✅ `name`, `model_id`, `is_active` |

### 欠けているもの

| コンポーネント | 必要性 |
|---------------|--------|
| ペルソナ用スコープ | 🔴 必須 — `run_online` フィルタ |
| ペルソナ用検索パラメータ | 🔴 必須 — `run_mode`, `ai_model_id` |
| 検索結果にペルソナ情報を付与 | 🟡 推奨 — `persona_card` |

## 振る舞い定義（BDD）

### 検索パラメータ

| パラメータ | 振る舞い | 期待結果 |
|-----------|---------|---------|
| `run_mode=run_online` | run_online ペルソナのみ検索 | `default_run_mode == 'run_online'` の listing のみ返す |
| `run_mode=download` | download ペルソナのみ検索 | `default_run_mode == 'download'` の listing のみ返す |
| `ai_model_id=1` | 特定 AI モデルを持つペルソナを検索 | `listing_ai_models.ai_model_id == 1` の listing のみ返す |
| `has_persona=true` | ペルソナを持つ listing のみ検索 | `default_run_mode IS NOT NULL` の listing のみ返す |

### 検索結果

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| ペルソナ検索 | ペルソナフィルタ付きで検索 | 結果に `persona_card` が含まれる |
| 通常検索 | フィルタなしで検索 | 従来通りの動作 |

## 作成対象ファイル

### スコープ（修正）

1. `app/models/listing.rb` — ペルソナ用スコープ追加

### 検索サービス（修正）

2. `app/services/listing_index_service/search/database_search_helper.rb` — ペルソナパラメータ対応

### テスト

3. `spec/models/listing_persona_scope_spec.rb` — スコープのテスト

## コードベース規約

- `listings.id` は `int`（32-bit）。FK は `t.integer` + 手動 `add_foreign_key`
- 既存の `SearchEngineAdapter` パターンに従う
- `DatabaseSearchHelper` の `needs_search?` にパラメータを追加
- `src/Eccube/` は編集しない

## テスト計画

### 単体テスト (Unit)

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| `Listing.run_online` | `default_run_mode == 'run_online'` のみ返すこと | 正常系 |
| `Listing.with_ai_model` | 指定した AI モデルを持つ listing のみ返すこと | 正常系 |
| `Listing.persona_only` | ペルソナを持つ listing のみ返すこと | 正常系 |
| `DatabaseSearchHelper` | ペルソナパラメータが正しくフィルタされること | 正常系 |

### 統合テスト (Integration)

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| 検索フロー | `run_mode=run_online` で検索した結果が正しいこと | 正常系 |
| 検索フロー | `ai_model_id=1` で検索した結果が正しいこと | 正常系 |

## 既知の制約

- Phase 6 では検索フィルタのみ（セマンティック検索は別途対応）
- Sphinx インデックスの再構築は手動（Phase 6 では対象外）
