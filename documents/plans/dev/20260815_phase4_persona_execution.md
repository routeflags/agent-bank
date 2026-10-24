# Phase 4: ペルソナ実装基盤 実装計画

## 概要

Phase 3 で構築したチャット基盤（Action Cable + SSE + チャットモデル）の上に、実際の AI プロバイダー（OpenAI / Anthropic）を接続し、ペルソナチャットを実現する。

## 既存コードベースの状態

### 既に存在するもの

| コンポーネント | ファイル | 状態 |
|---------------|---------|------|
| AI プロバイダー | `app/models/ai_provider.rb` | ✅ API キー暗号化・管理済み |
| AI モデル | `app/models/ai_model.rb` | ✅ コスト計算・ストリーミング対応フラグあり |
| Listing ↔ AI モデル | `app/models/listing_ai_model.rb` | ✅ デフォルトモデル紐付け済み |
| ペルソナフィールド | `app/models/listing.rb` | ✅ run_mode, external_apis, short_description |
| チャットセッション | `app/models/chat_session.rb` | ✅ status, total_tokens |
| チャットメッセージ | `app/models/chat_message.rb` | ✅ role, seq, token カウント |
| Action Cable | `app/channels/persona_chat_channel.rb` | ✅ WebSocket 通信基盤 |
| SSE | `app/controllers/api/v1/chat_stream_controller.rb` | ✅ ストリーミング |
| ジョブ | `app/jobs/persona_executor_job.rb` | ⏳ スタブ（placeholder応答） |
| 課金 | `app/models/wallet.rb`, `app/models/usage_record.rb` | ✅ deduct_for_usage! / 使用量記録 |
| 暗号化 | `app/services/encryption_service.rb` | ✅ API キー暗号化 |

### 欠けているもの

| コンポーネント | 必要性 |
|---------------|--------|
| AI プロバイダーアダプター | 🔴 必須 — OpenAI / Anthropic API 呼び出し |
| PersonaExecutorJob 実装 | 🔴 必須 — スタブ → 実際の API 呼び出し |
| ストリーミング応答 | 🔴 必須 — AI の応答をチャンク配信 |
| 課金統合 | 🟡 推奨 — 使用量に応じた課金 |
| システムプロンプト構築 | 🟡 推奨 — listing の persona フィールドからプロンプト生成 |

## 振る舞い定義（BDD）

### AI プロバイダーアダプター

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| create | プロバイダーとモデルを指定してチャットコンテキストを構築 | OpenAI / Anthropic API 形式のメッセージ配列を生成 |
| stream | AI にストリーミングリクエスト | チャンクごとにブロックをコール |
| sync | AI に同期リクエスト | 完全な応答テキストとトークン使用量を返す |

### PersonaExecutorJob（実装版）

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| perform | ユーザーメッセージを受け取り AI 呼び出し | assistant メッセージを作成し Action Cable で配信 |
| perform | 残高不足の場合 | system メッセージ「残高が不足しています」を配信 |
| perform | API エラーの場合 | system メッセージ「申し訳ありません。エラーが発生しました」を配信 |

### ストリーミング配信

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| chunk | AI がチャンクを返すたびに | Action Cable で `{ type: "stream_chunk", content: "..." }` を配信 |
| done | AI 応答完了 | `{ type: "stream_done", messageId: ..., tokens: ... }` を配信 |
| error | API エラー | `{ type: "stream_error", error: "..." }` を配信 |

### 課金統合

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| before | AI 呼び出し前に残高チェック | 残高不足なら早期リターン |
| after | AI 応答後に使用量記録 | UsageRecord 作成 + Wallet 払い引き |

## 作成対象ファイル

### サービス層

1. `app/services/ai/chat_completions_builder.rb` — メッセージ配列の構築
2. `app/services/ai/openai_adapter.rb` — OpenAI API アダプター
3. `app/services/ai/anthropic_adapter.rb` — Anthropic API アダプター
4. `app/services/ai/provider_factory.rb` — プロバイダー選択ファクトリ

### ジョブ

5. `app/jobs/persona_executor_job.rb` — スタブ → 実装版に置き換え

### モデル（修正）

6. `app/models/chat_session.rb` — system_prompt ヘルパー追加

### ルーティング（修正）

7. `config/routes.rb` — 特定の変更不要（Phase 3 で API namespace 済み）

## コードベース規約

- `listings.id` は `int`（32-bit）。FK は `t.integer` + 手動 `add_foreign_key`
- `people.id` は `varchar(22)`。FK は `t.string` + アプリレベル整合性
- 認証は `current_user`（ApplicationController の `before_action`）
- Action Cable の `ApplicationCable::Connection` では `env['warden'].user` で認証
- HTTP クライアントは `faraday`（v1.10.5）を使用（Gemfile に既存）
- API キーは `AiProvider#api_key` で復号化して取得
- 金銭操作は必ず `lock!` + `transaction` でアトミック化（Wallet パターン）
- Struct ベースのジョブパターンに従う

## 実装方針

### AI アーキテクチャ

```
PersonaExecutorJob
  │
  ├─ Ai::ProviderFactory.for(listing)
  │   ├─ Ai::OpenAiAdapter
  │   └─ Ai::AnthropicAdapter
  │
  ├─ Ai::ChatCompletionsBuilder
  │   └─ system_prompt + history → messages 配列
  │
  ├─ adapter.stream(messages) do |chunk|
  │   └─ ActionCable.server.broadcast → stream_chunk
  │
  └─ adapter.sync(messages)
      └─ 残高チャージ + UsageRecord 作成
```

### プロバイダー選択ロジック

1. `ListingAiModel` からデフォルトモデルを取得
2. `AiModel` → `AiProvider` でプロバイダーを特定
3. `AiProvider.slug` に応じてアダプターを選択

### システムプロンプト構築

- `Listing#short_description` → ペルソナの性格・役割
- `Listing#external_apis` → 外部 API 連携情報
- `ChatSession` の履歴 → コンテキスト

### ストリーミング設計

- OpenAI: `stream: true` + SSE チャンク解析
- Anthropic: `stream: true` + SSE イベント解析
- 各チャンクを `ActionCable.server.broadcast` で配信
- 完了時に `stream_done` イベントでトークン使用量を通知

### 課金フロー

```
1. PersonaExecutorJob#perform
   ├─ wallet = person.wallet
   ├─ raise InsufficientBalanceError if wallet.below_threshold?
   │
   ├─ adapter.stream(messages) { |chunk| broadcast }
   │
   ├─ UsageRecord.create!(ai_model: model, input_tokens: ..., output_tokens: ...)
   ├─ cost = model.estimate_cost(input_tokens, output_tokens)
   └─ wallet.deduct_for_usage!(cost * 100, tokens_used: total_tokens)
```

## テスト計画

### 単体テスト (Unit)

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| `Ai::ChatCompletionsBuilder` | system_prompt + history が正しく配列化されること | 正常系 |
| `Ai::ChatCompletionsBuilder` | 空の履歴でもエラーにならないこと | 正常系 |
| `Ai::OpenAiAdapter` | OpenAI 形式のメッセージ配列が正しく送信されること | 正常系 |
| `Ai::OpenAiAdapter` | API キーが無効な場合にエラーが返されること | 異常系 |
| `Ai::AnthropicAdapter` | Anthropic 形式のメッセージ配列が正しく送信されること | 正常系 |
| `Ai::ProviderFactory` | listing のモデル設定に応じたアダプターが返されること | 正常系 |
| `Ai::ProviderFactory` | モデルが未設定の場合にエラーが返されること | 異常系 |

### 統合テスト (Integration)

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| `PersonaExecutorJob` | AI プロバイダーにリクエストが送信されること | 正常系 |
| `PersonaExecutorJob` | レスポンスが chat_messages に保存されること | 正常系 |
| `PersonaExecutorJob` | Action Cable でストリーミング配信されること | 正常系 |
| `PersonaExecutorJob` | 残高不足時に system メッセージが配信されること | 異常系 |
| `PersonaExecutorJob` | API エラー時に system メッセージが配信されること | 異常系 |
| `Wallet` | 使用量記録後に balance が減少すること | 正常系 |
| `UsageRecord` | cost_cents が正しく計算されること | 正常系 |

### ウェブテスト (Functional)

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| `ChatStreamController` | ストリーミング中に AI 応答が受信できること | 正常系 |
| `PersonaChatChannel` | メッセージ送信後にジョブがキューイングされること | 正常系 |

### E2E テスト

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| チャットフロー | ユーザー送信 → AI ストリーミング応答受信 → 使用量記録 | 正常系 |

## コードベース規約

- `src/Eccube/` はコアファイルなので編集しない
- 新規ファイルは `app/` 配下に配置
- Faraday v1.x API を使用（v2.0 互換ではない）
- API キーは `AiProvider#api_key` で復号化（EncryptionService 経由）
- Struct ベースのジョブパターンに従う
- ストリーミングは `ActionCable.server.broadcast` で配信

## 既知の制約

- Phase 4 では OpenAI と Anthropic の 2 プロバイダーのみ対応
- ストリーミングは Action Cable 経由のみ（SSE は別途対応検討）
- 本番環境では Redis アダプターを使用
- API キーの管理は管理画面から（Phase 5 で実装）

## コードレビュー修正履歴

| 日付 | 優先度 | 修正内容 | 対象ファイル |
|------|--------|---------|-------------|
| — | — | Phase 4 は未着手 | — |
