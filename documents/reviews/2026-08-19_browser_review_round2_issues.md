# Round 2 Issues（2026-08-19）

このファイルは、`documents/reviews/2026-08-19_browser_review_round2.md` の指摘を「Issue化しやすい形」に切り出したものです。

---

## P0

### BR2-P0-001 出品者の支払い詳細未設定で購入フローがブロックされる

- 影響: 買い手が「購入→利用開始」できず、プロダクト価値を体験できない
- 再現:
  1. 買い手でログイン（例: `buyer1`）
  2. スキル詳細（例: `/ja/listings/20-tesuto-raiteingu-asisutanto`）を開く
  3. 「このスキルを利用する」をクリック
- 期待: 購入/決済フローへ遷移（または明確な代替導線がある）
- 実際: 「この出品の作成者はお支払い詳細を追加していないので…」のバナーが表示され、先に進めない
- 証跡: `screenshots/20260819/browser_round2/05_after_cta.png`

### BR2-P0-002 購入前ユーザーのチャット開始が 403 で拒否される

- 影響: スキル利用（AIチャット）が成立しない
- 再現:
  1. 買い手でログイン
  2. スキル詳細で 💬 からチャットを開く
  3. メッセージ送信
- 期待: 購入が必要なら購入導線へ案内（または購入済みなら応答が返る）
- 実際: `POST /api/v1/chat_sessions` が `403 Forbidden`（UIは「購入してください」+「接続できない」）
- 証跡: `screenshots/20260819/browser_round2/07_chat_after_send.png`, `screenshots/20260819/browser_round2/report.json`

---

## P1

### BR2-P1-001 購入要件と接続エラーが混在し、ユーザーが原因を判断できない

- 影響: 離脱・サポート問い合わせ増
- 再現: BR2-P0-002 と同様
- 期待: 403（購入要件）なら購入誘導に一本化、接続系エラーは抑止
- 実際: 「このペルソナを購入してください」+ `"Could not connect to chat."` が同時表示
- 証跡: `screenshots/20260819/browser_round2/07_chat_after_send.png`

### BR2-P1-002 日本語UIに英語エラーメッセージが混在

- 影響: 不信感・分かりづらさ
- 再現: BR2-P0-002 と同様
- 実際: `"Could not connect to chat."`
- 証跡: `screenshots/20260819/browser_round2/07_chat_after_send.png`

