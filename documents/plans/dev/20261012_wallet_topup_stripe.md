# 計画: ウォレットチャージ（Stripe）本番動作化

## 現状調査結果

チャットパネル右上の「追加する（準備中）」ボタンの裏側を調査した。

### 実装済み（再利用可能）

| 項目 | 場所 | 状態 |
|------|------|------|
| バックエンド2段階決済 | [wallet_topup_controller.rb](../../../app/controllers/api/v1/wallet_topup_controller.rb) (220行) | ✅ 完成 |
| ルーティング | [routes.rb:728](../../../config/routes.rb#L728) | ✅ 完成 |
| モーダルUI + 決済フロー | [ChatPanelApp.js:191-280](../../../client/app/startup/ChatPanelApp.js#L191) `WalletTopupModal` | ✅ 完成 |
| ロケールキー | [ja.yml:2302-2312](../../../config/locales/ja.yml#L2302) | ✅ 完成 |

バックエンドは Stripe PaymentIntent を2段階で処理する:
1. `POST /api/v1/wallet_topup` → PaymentIntent 作成
2. `POST /api/v1/wallet_topup/confirm` → 検証して `Wallet#topup!` でチャージ（冪等性チェック付き）

`configure_stripe_api!` は `PaymentSettings`（コミュニティ設定）→ `ENV["STRIPE_SECRET_KEY"]` の順にフォールバックする。

### 未接続・未設定（課題）

1. **ボタンがモーダルを開かない** — [ChatPanelApp.js:1022](../../../client/app/startup/ChatPanelApp.js#L1022) の `handleOpenTopup` がスタブで、`showTopupModal: true` ではなく「準備中」メッセージをチャットに追加しているだけ。モーダルは実装済みだが一度も開かれない。

2. **Stripe APIキーが未設定** — DB `payment_settings` にレコードなし、`.env` に `STRIPE_SECRET_KEY` なし。この状態で動かすとコントローラが `"No Stripe API key configured"` を raise する。

## 実装計画

### Step 1: ボタンをモーダルに接続（5分）

`handleOpenTopup` のスタブを削除し、モーダルを開くように変更する。

```javascript
// ChatPanelApp.js:1022
handleOpenTopup() {
  this.fetchWalletBalance();
  this.setState({ showTopupModal: true });
}
```

### Step 2: Stripeテストキーの設定（要ユーザー判断）

Stripe のテストキー（`sk_test_...` / `pk_test_...`）が必要。設定方法は2通り:

- **方法A（推奨・簡易）**: `.env` に `STRIPE_SECRET_KEY=sk_test_...` を追加
- **方法B（本番準拠）**: 管理画面 → 決済設定 → Stripe でコミュニティ単位の `payment_settings` を登録

> **ユーザーに確認が必要**: Stripe アカウントの有無とテストキーの提供。

### Step 3: E2E検証（15分）

Stripeテストモードのカード番号で実動作を確認:

| 項目 | 値 |
|------|-----|
| カード番号 | `4242 4242 4242 4242` |
| 有効期限 | 任意の未来日 |
| CVC | 任意の3桁 |

検証項目:
1. モーダルが開く
2. 金額選択 → 「追加する」で PaymentIntent 作成
3. confirm 後に `wallets.balance_cents` が増加
4. `credit_transactions` に `topup` 記録
5. `usage_records` に紐づく決済が発生しないこと（チャージのみ）
6. 同一 PaymentIntent の再 confirm で冪等性が効くこと

### Step 4: テスト追加（30分）

- `spec/requests/api/v1/wallet_topup_spec.rb` — create/confirm/balance のAPIテスト
- 金額バリデーション（100〜10,000円）
- 冪等性（同一PI二重チャージの拒否）
- 未認証の拒否

## スコープ外（今回の計画には含めない）

- 実カード（liveキー）での本番決済 — テストモード動作確認後に別途
- Webhook による決済結果同期 — 現状は confirm で同期しており、基本動作には不要
- 複数通貨対応 — 現状円（JPY）固定

## 推奨

Step 1 は即実装可能。Step 2 で Stripe テストキーの提供が必要。
キーがあれば E2E まで一気に通す。
