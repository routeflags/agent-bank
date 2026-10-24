# Phase 5: UI 実装 — AI ペルソナチャット

## 概要

Phase 4 で構築した AI ペルソナ実装基盤のフロントエンド UI を構築する。
listing ページにチャットパネルを追加し、ユーザーが AI ペルソナとリアルタイムでチャットできるようにする。

## プロジェクト構造の理解

### フロントエンド構成

| レイヤー | 技術 | 場所 |
|---------|------|------|
| テンプレート | HAML | `app/views/` |
| JS バンドル | Webpack (React) | `client/app/` |
| JS レガシー | jQuery | `app/assets/javascripts/` |
| CSS | SCSS (PostCSS) | `client/app/` |
| 統合ページ | React コンポーネント | `client/app/components/` |
| エントリーポイント | startup | `client/app/startup/` |

### 既存のパターン

- React コンポーネントは `client/app/components/` に配置
- エントリーポイントは `client/app/startup/` に `XxxApp.js` として配置
- HAML テンプレートから `react_component` ヘルパーで React をマウント
- Action Cable は `/api/cable` でマウント済み

## 振る舞い定義（BDD）

### チャットパネル（listing ページ内）

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| ページ表示 | listing ページにチャットボタンを表示 | persona_card の `default_run_mode` が `run_online` の場合のみ表示 |
| クリック | チャットパネルが開く | チャット入力欄 + メッセージ一覧が表示 |
| メッセージ送信 | ユーザーがメッセージを入力して送信 | Action Cable 経由で PersonaExecutorJob がキューイング |
| ストリーミング受信 | AI の応答がチャンクごとに届く | リアルタイムでテキストが追加表示される |
| 履歴表示 | 過去のメッセージが表示される | ChatSessionsController#index から取得 |
| セッション管理 | チャットを閉じる / 新しいセッションを開始 | status: 'closed' / 新規 ChatSession 作成 |

### チャットメッセージ表示

| 操作 | 振る舞い | 期待結果 |
|------|---------|---------|
| ユーザーメッセージ | ユーザーが送信したメッセージ | 右寄せ、バブル表示 |
| アシスタントメッセージ | AI の応答 | 左寄せ、バブル表示。ストリーミング中はアニメーション |
| システムメッセージ | エラー・通知 | センター寄せ、グレー表示 |
| トークン表示 | 使用量 | アシスタントメッセージ下に small text で表示 |

### レスポンシブ

| ブレークポイント | 振る舞い |
|----------------|---------|
| デスクトップ (>= 768px) | listing ページ右側にチャットパネル |
| モバイル (< 768px) | フルスクリーンオーバーレイ |

## 作成対象ファイル

### React コンポーネント

1. `client/app/components/ChatPanel/ChatPanel.js` — チャットパネルメイン
2. `client/app/components/ChatPanel/ChatMessage.js` — メッセージバブル
3. `client/app/components/ChatPanel/ChatInput.js` — 入力欄
4. `client/app/components/ChatPanel/ChatHeader.js` — ヘッダー（ペルソナ名、閉じるボタン）
5. `client/app/components/ChatPanel/useChatSession.js` — チャットセッション管理フック
6. `client/app/components/ChatPanel/useActionCable.js` — Action Cable 接続フック
7. `client/app/components/ChatPanel/chatPanel.css` — スタイル

### エントリーポイント

8. `client/app/startup/ChatPanelApp.js` — React マウント用

### HAML テンプレート（修正）

9. `app/views/listings/show.haml` — チャットパネルのマウントポイント追加

## アーキテクチャ

```
Listing ページ (show.haml)
  │
  ├─ React: ChatPanelApp.js
  │   └─ ChatPanel.js
  │       ├─ ChatHeader.js（ペルソナ名、閉じるボタン）
  │       ├─ メッセージ一覧
  │       │   └─ ChatMessage.js（ユーザーアシスタント・システム）
  │       ├─ ChatInput.js（入力欄、送信ボタン）
  │       └─ useChatSession.js（API 呼び出し管理）
  │           └─ useActionCable.js（WebSocket 接続管理）
  │
  ├─ API: /api/v1/chat_sessions
  │   ├─ POST /api/v1/chat_sessions（新規セッション）
  │   ├─ GET /api/v1/chat_sessions/:id（セッション詳細 + メッセージ履歴）
  │   └─ PATCH /api/v1/chat_sessions/:id（セッション終了）
  │
  └─ Action Cable: /api/cable
      └─ PersonaChatChannel（WebSocket チャット）
          ├─ receive: ユーザーメッセージ送信
          ├─ stream_chunk: AI 応答のチャンク受信
          ├─ stream_done: AI 応答完了
          └─ stream_error: エラー通知
```

## コードベース規約

- React コンポーネントは `client/app/components/` に配置
- エントリーポイントは `client/app/startup/` に `XxxApp.js` として配置
- HAML テンプレートから `react_component` ヘルパーで React をマウント
- CSS は `chatPanel.css` としてファイル分割
- Action Cable は `/api/cable` でマウント済み
- API は `/api/v1/` namespace

## テスト計画

### コンポーネントテスト (React)

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| `ChatPanel` | 初期表示時にチャット入力欄が表示されること | 正常系 |
| `ChatMessage` | role に応じたバブル表示がされること | 正常系 |
| `ChatInput` | 送信ボタンが無効になる条件（空メッセージ） | 正常系 |
| `useChatSession` | セッション作成・取得が正しいこと | 正常系 |
| `useActionCable` | Action Cable 接続・切断が正しいこと | 正常系 |

### E2E テスト

| テスト対象 | テスト内容 | 種別 |
|-----------|-----------|------|
| チャットフロー | ページ表示 → メッセージ送信 → ストリーミング受信 | 正常系 |
| チャットフロー | 未認証でチャットボタンが表示されないこと | 異常系 |

## 既知の制約

- Phase 5 ではチャットパネルのみ（管理画面は別途対応）
- モバイル対応はフルスクリーンオーバーレイ
- i18n は後回し（英語ハードコード）
- ファイルアップロード対応なし
