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
| create | ユーザーがメッセージ送信 | ChatMessage レコード作成（sender_type: 'User'） |
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
