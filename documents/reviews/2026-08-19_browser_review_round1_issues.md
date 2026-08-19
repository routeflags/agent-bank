# Round 1 Issues（2026-08-19）

このファイルは、`documents/reviews/2026-08-19_browser_review_round1.md` の指摘を「Issue化しやすい形」に切り出したものです。

---

## P0

### BR1-P0-001 検索が停止中（探索導線が機能していない）

- 影響: 新規ユーザーがスキルを発見できない
- 再現:
  1. `/ja/` を開く
  2. 赤バナーに「現在検索が使用できません…」が表示される
- 期待: 検索が利用できる（または検索UIを無効化/非表示にして代替導線を提示）
- 実際: 検索停止バナーが表示され、検索入力UIも残る
- 証跡: `screenshots/20260819/browser_round1/01_top.png`

### BR1-P0-002 チャットが接続できず、スキル利用が成立しない

- 影響: コア価値（AIペルソナを利用する）が体験できない
- 再現:
  1. ログイン
  2. スキル詳細（例: `/ja/listings/20-tesuto-raiteingu-asisutanto`）を開く
  3. 右下の 💬 を押す
  4. メッセージ送信
- 期待: 接続完了 → 応答が返る / もしくは「購入が必要」なら購入導線へ案内
- 実際: 「接続中...」から進まない、または `"Could not connect to chat."` が表示される。同時に「このペルソナを購入してください」も出る
- 証跡: `screenshots/20260819/browser_round1/06_chat_open.png`, `screenshots/20260819/browser_round1/07_chat_after_send.png`

### BR1-P0-003 `/listings/new` が空表示に見える（出品フロー不成立の可能性）

- 影響: 出品者が商品（スキル）を追加できない
- 再現:
  1. ログイン
  2. `/ja/listings/new` を開く
- 期待: 出品フォームが表示される
- 実際: フォームが確認できない（空表示に見える）
- 証跡: `screenshots/20260819/browser_round1/04_listings_new.png`

---

## P1

### BR1-P1-001 エラー文言の英語混在（日本語UI）

- 影響: 不信感・不親切
- 再現: BR1-P0-002 と同様
- 期待: 日本語で原因と次アクションが表示される
- 実際: `"Could not connect to chat."`
- 証跡: `screenshots/20260819/browser_round1/07_chat_after_send.png`

### BR1-P1-002 通貨表示の整合性が不明（価格: `€` / 残高: `¥`）

- 影響: 課金UXの信頼性が落ちる
- 再現:
  1. スキル詳細を開く（右ペインに `€15`）
  2. チャットUI（右ペインに `残高¥10,000`）
- 期待: 同一の通貨・単位体系（または明確な換算/注記）
- 実際: 通貨が混在
- 証跡: `screenshots/20260819/browser_round1/05_listing_detail.png`, `screenshots/20260819/browser_round1/07_chat_after_send.png`

### BR1-P1-003 「決済を設定する」警告の表示範囲が広く、役割ごとの出し分けが不明

- 影響: ユーザーの混乱（買い手が見ても意味が薄い可能性）
- 再現: ログイン後にトップ/詳細へ遷移
- 期待: 売り手（出品者）に限定して表示、または管理画面へ明確に誘導
- 実際: トップや詳細にも表示
- 証跡: `screenshots/20260819/browser_round1/03_after_login.png`, `screenshots/20260819/browser_round1/05_listing_detail.png`

