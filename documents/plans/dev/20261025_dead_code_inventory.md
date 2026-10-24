# Sharetribe 由来の未使用機能の棚卸し表（Issue #60 Phase C・調査のみ）

> **作業日**: 2026-10-25
> **方針**: 今回はコードを消さない。撤去は判定後に別 Issue へ分割する。
> 撤去案は末尾の「分割案」まで（実装は別 Issue）。
>
> **実測方法**（いずれも `app/` `lib/` `config/` `client/app/` が対象。`node_modules`・`vendor` 除く）:
>
> ```bash
> grep -rli "paypal" app/ lib/ config/ client/app/     # 内容一致のファイル数
> grep -rli "braintree" app/ lib/ config/ client/app/
> grep -rli "stripe" app/ lib/ config/ client/app/
> grep -rli "transaction\|booking\|shipping" app/ lib/ config/ client/app/
> ```
>
> locale ファイル（`config/locales`）が大半を占めるため、表の「参照数」は
> 内容一致の総ファイル数、「代表ファイル」は機能の中核（services・controllers・
> models・routes・jobs・views）に絞って記載する。機能判定は中核の利用実態で行う。

---

## 棚卸し表

| 機能 | 代表ファイル | 参照数 | 依存（管理画面・spec・ルーティング） | 撤去難易度 | 判定 |
|------|--------------|--------|--------------------------------------|------------|------|
| PayPal 決済 | `app/services/paypal_service/`（60件）<br>`app/controllers/paypal_accounts_controller.rb`<br>`app/controllers/paypal_ipn_controller.rb`<br>`app/views/`（34件） | 内容一致 **324件**<br>（内訳: locales 149、services 60、views 34、controllers 16、assets 16、models 14） | spec **27件** が言及<br>routes: `paypal_ipn` webhook、`paypal_service/checkout_orders`、`paypal_accounts`、`admin paypal` リソース | 高（services・controllers・views・IPN・admin 設定画面まで配線が残る） | **保留** |
| Stripe 決済 | `app/services/stripe_service/`（29件）<br>`app/controllers/preauthorize_transactions_controller.rb`（`StripeAPIWrapper.confirm_payment_intent`）<br>`app/services/inbox_service.rb`（`StripeService::API::API.payments`） | 内容一致 **297件**<br>（内訳: locales 147、views 49、services 29、assets 20、controllers 15） | spec **25件** が言及<br>routes: `payment_settings#redirect_to_stripe` / `#stripe_callback`、`stripe_account` リソース、`stripe_confirm_intent` / `stripe_failed_intent` | 高 | **残す** |
| Braintree | `app/models/transaction.rb:92`（`payment_gateway` inclusion の列挙のみ）<br>`app/services/transaction_service/transaction.rb:13`（`DEPRECATED_GATEWAYS = [:braintree, :checkout]`）<br>`app/services/transaction_service/store/payment_settings.rb`（gateway 列挙×2） | 内容一致 **70件**<br>（内訳: locales 67、その他 3。services・controllers・views・jobs の実体なし） | spec **0件**<br>routes: なし<br>管理画面: なし | 低（列挙からの除去＋locale 掃除のみ） | **撤去する**（別 Issue に分割） |
| transaction / booking / shipping | `app/models/transaction.rb`（`has_one :booking`、`payment_gateway` ほか）<br>`app/models/booking.rb`<br>`app/services/transaction_service/`（77件）<br>`app/jobs/`（23件）<br>`app/state_machines/transaction_process_state_machine.rb` | 内容一致 **465件**<br>（内訳: locales 143、views 105、services 77、controllers 29、models 26、jobs 23） | spec: 取引系 spec が広範に依存（free/confirmed 遷移・購入記録）<br>routes: 取引・受取確認系が多数 | 極高（購入記録・監査 #25 の基盤。`Transaction` は persona 購入の記録として現役） | **残す**（transaction）/ **保留**（booking・shipping の利用実態は別途確認） |

---

## 判定の根拠

- **PayPal → 保留**: 決済は Freemius 一本（#43 系）のため新規利用は無いが、
  `paypal_accounts_controller`・IPN webhook・`checkout_orders`・admin 設定画面まで
  配線が残り、spec 27件も言及する。一括撤去は危険なため、利用実態の切り分け
  （設定画面の表示条件・IPN の到達有無）を別 Issue で行ってから判定する。
- **Stripe → 残す**: wallet チャージ経路（`confirm_payment_intent`・`stripe_callback` 等）で
  現役利用がある。未使用なのは出品者受取（Connect）側だけの可能性があるため、
  残す。Connect 側の切り分けは PayPal と同じ別 Issue で扱う。
- **Braintree → 撤去する（別 Issue）**: 実体は gateway 列挙の3行のみで、
  サービス・コントローラ・ルーティング・spec が存在しない。locale 67件の掃除が
  作業の大半になる見込み。小さく分割できる。
- **transaction → 残す**: `Transaction`（free/confirmed）は persona 購入の記録であり、
  監査 #25・購入付与の基盤として現役。撤去対象にしない。
- **booking・shipping → 保留**: `has_one :booking`・`require_shipping_address` 等の配線は
  残るが、ペルソナ販売（無形商品）で利用実態があるか未確認。別 Issue で利用実態を
  調べてから判定する。

---

## 分割案（撤去は別 Issue。実装しない）

1. **Braintree 列挙の除去**（小）: `payment_gateway` inclusion・`DEPRECATED_GATEWAYS`・
   `payment_settings` ストアの列挙から `:braintree` を除去し、locale の braintree
   キーを掃除する。spec 0件のため影響は小さい。
2. **PayPal 利用実態の切り分け調査**（調査のみ）: 設定画面の表示条件・IPN 到達有無・
   `checkout_orders` の到達可能性を確認し、撤去範囲を確定する。
3. **Stripe Connect 側の切り分け調査**（調査のみ）: チャージ経路と出品者受取経路を
   分離し、Connect 側だけの撤去可否を判断する。
4. **booking・shipping の利用実態調査**（調査のみ）: ペルソナ販売で booking・
   shipping の配線に到達する導線があるか確認し、撤去可否を判断する。

---

## 実測ログ（2026-10-25）

```
# 内容一致ファイル数（app/ lib/ config/ client/app/）
PayPal:                         324件（locales 149 / services 60 / views 34 / controllers 16 / assets 16 / models 14 / その他 35）
Braintree:                       70件（locales 67 / その他 3）
Stripe:                         297件（locales 147 / views 49 / services 29 / assets 20 / controllers 15 / その他 37）
transaction/booking/shipping:   465件（locales 143 / views 105 / services 77 / controllers 29 / models 26 / jobs 23 / その他 62）
# spec 言及ファイル数
PayPal: 27件 / Braintree: 0件 / Stripe: 25件
```
