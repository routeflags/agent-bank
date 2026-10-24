# Phase 3: SSE ストリーミング 実装計画

## 概要

AI ペルソナとのチャット機能を構築する。Action Cable（WebSocket）で双方向通信、SSE でストリーミング応答を提供する。

## 振る舞い定義（BDD）

### チャットセッション

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| create | ユーザーがペルソナとチャット開始 | ChatSession レコード作成、status: 'active' |
| close | ユーザーがチャット終了 | status: 'closed' |
| list | ユーザーのセッション一覧取得 | 該当する ChatSession の一覧 |

### チャットメッセージ

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| create | ユーザーがメッセージ送信 | ChatMessage レコード作成（sender_type: 'Person'） |
| stream | AI の応答をストリーミング | Action Cable でリアルタイム配信 |
| history | 過去のメッセージ取得 | 時系列でメッセージ一覧 |

### Action Cable Channel

| 振る舞い | 期待結果 |
|---------|---------|
| subscribed | チャットセッションに参加、ストリーム開始 |
| unsubscribed | ストリーム停止 |
| receive_message | ユーザー受信 → PersonaExecutorJob へキューイング |

### SSE エンドポイント

| 振る舞い | 期待結果 |
|---------|---------|
| リクエスト | `text/event-stream` ヘッダーで応答 |
| イベント配信 | `message` イベントで JSON データ送信 |
| クライアント切断 | `ClientDisconnected` でハンドリング |

## 作成対象ファイル

### マイグレーション
1. `db/migrate/20260815000006_create_chat_sessions.rb`
2. `db/migrate/20260815000007_create_chat_messages.rb`

### モデル
3. `app/models/chat_session.rb`
4. `app/models/chat_message.rb`

### Action Cable
5. `app/channels/application_cable/connection.rb`
6. `app/channels/application_cable/channel.rb`
7. `app/channels/persona_chat_channel.rb`

### コントローラー
8. `app/controllers/api/v1/chat_sessions_controller.rb`
9. `app/controllers/api/v1/chat_stream_controller.rb`

### ルーティング
10. `config/routes.rb` に API namespace 追加

## コードベース規約

- `listings.id` は `int`（32-bit）。FK は `t.integer` + 手動 `add_foreign_key`
- `people.id` は `varchar(22)`。FK は `t.string` + アプリレベル整合性
- `messages` テーブルは既存（Sharetribe のメッセージング）。`chat_messages` は別テーブル
- マイグレーションは `ActiveRecord::Migration[6.1]`
- 認証は `current_user`（ApplicationController の `before_action`）
- Action Cable の `ApplicationCable::Connection` では `env['warden'].user` で認証
- `cable.yml` は既存（dev: async, prod: redis）

## 既知の制約

- Phase 4 の `PersonaExecutorJob` は未作成。`chat_message.created` の後処理はスタブ
- SSE の `ClientDisconnected` は StandardError のサブクラス。rescue で補足
- 本番環境では Redis アダプターを使用。`cable.yml` の `channel_prefix` を `capafy_production` に変更

## テスト計画

### 単体テスト (Unit)

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| `ChatMessage` | role 検証（user/assistant/system のみ有効） | 正常系 |
| `ChatMessage` | sender が optional でも保存できること | 正常系 |
| `ChatMessage` | sender なし（assistant メッセージ）でも保存できること | 正常系 |
| `ChatMessage` | chronological スコープが seq 順で返すこと | 正常系 |
| `ChatMessage` | token 数が親セッションにロールアップされること | 正常系 |
| `ChatSession` | close! で status が closed になり ended_at が記録されること | 正常系 |
| `ChatSession` | STATUSES 以外の値でバリデーションエラーになること | 異常系 |

### 統合テスト (Integration)

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| `PersonaExecutorJob` | placeholder レスポンスが chat_messages に保存されること | 正常系 |
| `PersonaExecutorJob` | broadcast が Action Cable 経由で送信されること | 正常系 |
| `PersonaChatChannel#receive` | 不正な session_id で early return されること | 異常系 |
| `PersonaChatChannel#receive` | 他人のセッションへのメッセージ送信が拒否されること | 異常系 |

### ウェブテスト (Functional)

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| `ChatSessionsController#index` | 未認証で 401 が返ること | 異常系 |
| `ChatSessionsController#create` | 存在しない listing_id で 404 が返ること | 異常系 |
| `ChatSessionsController#show` | 他人のセッションにアクセスできないこと | 異常系 |
| `ChatStreamController#show` | 未認証で SSE エラーイベントが返ること | 異常系 |
| `ChatStreamController#show` | 認証済みで event-stream が返ること | 正常系 |

### E2E テスト

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| チャットフロー | ユーザー送信 → ジョブキューイング → assistant レスポンス受信 | 正常系 |
| SSE 再接続 | last_event_id 指定で途切れなくメッセージが取得できること | 正常系 |

## コードレビュー修正履歴

| 日付 | 優先度 | 修正内容 | 対象ファイル |
|------|--------|---------|-------------|
| 2026-08-15 | 🔴 高 | sender_type: "System" → nil（sender optional 化） | persona_executor_job.rb, chat_message.rb, 新規マイグレーション |
| 2026-08-15 | 🔴 高 | SSE polling 間隔を環境変数 SSE_POLL_INTERVAL で制御可能に、seq ベースのフィルタリング追加 | chat_stream_controller.rb |
| 2026-08-15 | 🔴 高 | Channel#current_user の attr_reader 削除、private → protected | channel.rb |
| 2026-08-15 | 🟡 中 | ensure_authenticated に早期リターン追加 | chat_stream_controller.rb |
| 2026-08-15 | 🟡 中 | receive で find → find_by + nil チェック | persona_chat_channel.rb |
| 2026-08-15 | 🟡 中 | テスト計画の追記 | 本ドキュメント |
