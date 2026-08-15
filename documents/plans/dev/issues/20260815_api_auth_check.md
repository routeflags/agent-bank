# Issue: API 未認証時の 401 応答

## 優先度
🟢 低（正常動作の確認）

## 対象
- 計画書: `documents/plans/dev/20260815_phase3_sse_streaming.md`
- 対象ファイル: `app/controllers/api/v1/chat_sessions_controller.rb`

## 状態
✅ 正常動作確認済み

## 内容

### 期待される振る舞い
`GET /api/v1/chat_sessions` に未認証でアクセスした場合、`401 Unauthorized` と `{"error":"Authentication required"}` を返すこと。

### 実際の振る舞い
- HTTP ステータス: `401`
- レスポンスボディ: `{"error":"Authentication required"}`
- スクリーンショット: `screenshots/20260815/01_api_auth_required.png`

### 根拠
`before_action :ensure_authenticated` が `ChatSessionsController` の全アクションに適用されている。`current_user` が nil の場合、`render json: { error: "Authentication required" }, status: :unauthorized` を実行。

### 結論
問題なし。認証チェックが正しく機能している。
