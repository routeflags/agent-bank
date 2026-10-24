# 決済デバッグ手順（Freemius）

「Freemius では決済されているのに残高が増えない」等を切り分けるための手順。全て読み取りのみで、課金は発生しない。

## 1. まず 1 コマンドで状態を見る

```bash
bin/rails 'lamprey:debug:payment[<Freemius の payment_id>]'
```

出力の見方:

| 項目 | 意味 |
|---|---|
| `FreemiusClient.configured?` | product ID と Bearer が読めているか |
| `FreemiusPricing.configured?` | `FREEMIUS_JPY_USD_RATE` が有効か |
| `FreemiusTopupPlans.configured?` | 額面 MAP が有効か。無効なら理由も出る |
| `MAP の付与額` | その plan が何円分か。`nil` なら webhook は加算しない |
| `user_email` → `person` → `wallet` | 購入者をローカルで特定できたか |
| `この決済を参照する加算記録` | 加算済みか（0 件なら未処理） |

## 2. 症状別の切り分け

| 症状 | 見る場所 | よくある原因 |
|---|---|---|
| webhook が来ない | Listener 登録、トンネル/ドメイン、HTTPS | URL 間違い、ローカルの場合 `RAILS_DEVELOPMENT_HOSTS` 未設定で 403 |
| webhook が 401 | レスポンスの status | `PRODUCT_SECRET_KEY` の不一致（転送プロキシでボディ改変も同様） |
| 200 だが加算なし | リクエストログの `duration` / `db` | **イベント種別が取れていない**（`type` の位置違い）。`db: 0.0` なら DB にすら行っていない |
| 200 で DB は動くが加算なし | `lamprey:debug:payment` | plan が MAP 未登録、またはメール一致でユーザー特定できない |
| 加算額が想定と違う | `MAP の付与額` と `gross` | MAP の値が古い、plan 価格と付与額の逆ザヤ |
| 二重に加算される | `加算記録: N 件` | `freemius:<payment_id>` の冪等が効いていない（本来起こらない） |

## 3. ログの探し方

```bash
# webhook のリクエストだけ見る
grep -a '/webhooks/freemius' log/development.log | tail -5

# 実際の配信はトップレベル type で来る
#   {"type":"payment.created","objects":{"payment":{...},"user":{...}}}
```

レスポンスの `"status":200` に加えて `"db":0.0` が並んでいたら、ハンドラに到達していない（イベント判定で落ちている）。

## 4. 署名付きで手元から再送する

実際の決済を再処理させたい場合（幂等なので二重加算されない）:

```ruby
require "openssl"; require "net/http"
payload = { type: "payment.created", objects: { payment: { id: "<payment_id>", plan_id: "<plan_id>", gross: 5, currency: "usd" }, user: { email: "<buyer>" } } }.to_json
sig = OpenSSL::HMAC.hexdigest("SHA256", ENV["PRODUCT_SECRET_KEY"], payload)
Net::HTTP.post(URI("https://<domain>/webhooks/freemius"), payload, { "Content-Type" => "application/json", "x-signature" => sig })
```

## 5. 設定の点検

```bash
bin/rails runner 'puts FreemiusTopupPlans.validation_errors.inspect'
bin/rails runner 'puts FreemiusTopupPlans.plans.inspect'
```

額面 MAP は「plan_id → 付与円」で、`persona 用 plan との重複`・`範囲外`・`重複キー`があると**未設定扱い**になる（起動ログに `[FreemiusTopupPlans] Misconfigured:` が出る）。

## 6. やってはいけないこと

- 本番 DB への書き込みを伴う検証（このタスクは SELECT のみ）
- 実際のカード決済を自動化すること
- 秘密値（Bearer / Secret Key）をログや Issue に貼ること
