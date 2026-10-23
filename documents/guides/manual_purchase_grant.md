# 手動付与による有料ペルソナの運用（管理者付与）

> **目的**: 決済手段を持たないコミュニティでも有料ペルソナを販売・検証できるよう
> にする、オーナー承認ベースの購入権利付与の運用手順
> **対象**: routeflags/agent-bank（Issue #24）
> **作成日**: 2026-10-23
> **関連**: [dev_persona_purchase_flow.md](./dev_persona_purchase_flow.md)（開発用の
> 購入再現。本ドキュメントとは別経路）、[free_grant_audit.md](./free_grant_audit.md)
> （逆ガードの監査）

---

## 1. 方針（決定事項）

> **決済手段が無い間（`payment_process: none` の marketplace）、有料ペルソナは
> 「オーナー（管理者）による明示的な手動付与」で運用する。**

Issue #24 で選択肢を検討し、以下の方針を決定した。

| 選択肢 | 判断 | 理由 |
|--------|------|------|
| 1. 決済手段が無い間は有料出品を禁止 | 不採用 | Freemius 有効化まで販売・検証ができない |
| **2. 管理者による手動付与（Rake）を正式な運用とする** | **採用** | 決済手段が無くても検証・販売が可能。Freemius 有効化後の例外対応（返金・オフライン決済）にも流用できる |
| 3. オフライン決済を記録して付与 | 段階的に統合 | 手順 2 と同じ付与機構を使う。オフライン決済が発生したら operator に決済手段と日付を含めた識別子を渡して実行する |
| 4. 当面は無料ペルソナのみ | 不採用 | 有料ペルソナの検証ができない |

背景: #18 で「`free` 遷移では購入権利を付与しない」ように修正した結果、
決済手段が無いコミュニティでは有料ペルソナの購入経路が存在せず、コンタクトはできるが
チャット開始が `403 purchase_required` で拒否されるようになった。開発コミュニティは
この構成。既存の付与経路は (a) `confirmed` 遷移（実決済）、(b) 開発/テスト専用の
`DevPersonaPurchase`（production では常に無効）のみだった。

### 付与経路の全体像

| 経路 | 対象環境 | payment_reference | 備考 |
|------|---------|-------------------|------|
| `confirmed` 遷移（実決済） | 本番 | `initial_purchase_<transaction_id>` | Freemius 有効化後の正規経路 |
| **本タスク（管理者手動付与）** | **全環境（production 可）** | `manual_grant:<operator>:<ISO8601>` | **本ドキュメントの対象** |
| `lamprey:dev:grant_persona`（`DevPersonaPurchase`） | development / test のみ | `dev_purchase_<random>` | 購入の再現用。production では常に無効 |

> ⚠️ 手動付与は「実決済なしに購入権利と初回トークンを付与する」操作であり、
> 本番でも実行できる。だからこそ **operator の記録と承認フローが必須**である。

---

## 2. 承認フロー

1. 付与の必要性（誰に・どのペルソナを・なぜ）をオーナーが判断する
2. オーナー自身（または委任された実行者）がコマンドを実行する
3. `operator` には**付与を判断した人の識別子**（username / メール等）を渡す。
   実行者と判断者が異なる場合は判断者の名前を使う
4. 実行後、§4 の手順で付与結果を確認する
5. トークン残高や二重付与を疑われる場合は §6 の監査手順で照合する

オフライン決済（返金・銀行振込など）が理由の場合は、operator に脈絡が残るように
識別子を工夫する（例: `smapira-invoice-202611`）。

---

## 3. 実行手順

```bash
# 引数: [listing_id, person, operator]
# person   : Person ID / username / メールアドレスのいずれか
# operator : 必須。付与を判断した人の識別子（未指定なら中断）
bin/rails 'lamprey:purchases:grant[<listing_id>,<person>,<operator>]'

# 例: listing 42 を alice@example.com に、smapira の判断で付与
bin/rails 'lamprey:purchases:grant[42,alice@example.com,smapira]'
```

実行時は付与前に警告と対象明細が出力される（誤用防止）:

```text
[lamprey:purchases:grant] ⚠️  管理者による手動付与を実行します（実決済なし）
  この操作は購入権利と初回トークンを付与します。production でも実行できます。
  operator      : smapira
  person        : alice (person_id=xxxxxxxx)
  listing       : 42 「〇〇ペルソナ」 price_cents=500 JPY
  付与トークン数 : 100000 tokens (initial_amount_cents=200000)
  payment_ref   : manual_grant:smapira:2026-10-23T21:00:00+09:00
[lamprey:purchases:grant] 購入権利を付与しました: subscription_id=123
  payment_reference=manual_grant:smapira:2026-10-23T21:00:00+09:00
  person=alice (person_id=xxxxxxxx)
  listing=42 「〇〇ペルソナ」
  wallet_balance_cents=200000
```

- 既に active な購入権利がある場合は `既に active な購入権利があります。二重付与は
  しません` と表示され、正常終了する（冪等。初回トークンも再付与されない）
- 実行ログ（`Rails.logger`）にも operator・対象・payment_reference が残る

---

## 4. 確認方法

### 4.1 コンソールでの確認

```bash
bin/rails runner '
person = Person.find_by!(username: "alice")
listing = Listing.find(42)
sub = UserPlanSubscription.find_by(person: person, listing: listing)
puts "subscription: id=#{sub.id} status=#{sub.status}"
wallet = Wallet.find_by(person_id: person.id, community_id: listing.community_id)
puts "wallet: id=#{wallet.id} balance_cents=#{wallet.balance_cents}"
'
```

### 4.2 SQL での確認

```sql
-- 購入権利（手動付与分）
SELECT id, person_id, listing_id, status, billing_model, created_at
FROM user_plan_subscriptions
WHERE person_id = '<person_id>' AND listing_id = 42;

-- 付与された初回トークン（payment_reference から手動付与と特定できる）
SELECT ct.id, ct.amount_cents, ct.metadata, ct.created_at
FROM credit_transactions ct
JOIN wallets w ON w.id = ct.wallet_id
WHERE w.person_id = '<person_id>'
  AND ct.transaction_type = 'topup'
  AND ct.metadata LIKE '%"stripe_payment_id":"manual_grant:%'
ORDER BY ct.id DESC;
```

### 4.3 チャット開始の確認

付与後は対象ペルソナのチャットセッションを作成できる（`403 purchase_required`
が出なくなったら購入権利が効いている）。

---

## 5. ロールバック（付与の無効化）

誤付与や返金対応で付与を取り消す場合は、(1) 購入権利の無効化と (2) 初回トークンの
返却を `bin/rails console` で行う。

```ruby
# 1. 購入権利を無効化（チャット判定と冪等性ガードは status 列を見るため、
#    両方を更新する）
sub = UserPlanSubscription.find(123)
sub.transition_to!(:canceled)   # 遷移履歴に記録
sub.update!(status: "canceled") # 判定用のカラム

# 2. 付与した初回トークンを戻す（payment_reference 指定・冪等）
wallet = Wallet.find_by!(person_id: sub.person_id, community_id: sub.listing.community_id)
wallet.refund!(stripe_payment_id: "manual_grant:smapira:2026-10-23T21:00:00+09:00")
```

- `refund!` は同じ reference への再実行を拒否する（二重返却しない）
- 無効化後、同じ person×listing に再度付与できる（`canceled` は active ではないため
  冪等性ガードに掛からない。 billing_model は 2 回目以降 `subscription_with_overage` になる）

---

## 6. 監査（`lamprey:audit:free_grants` との関係）

`bin/rails 'lamprey:audit:free_grants'` は「`free` 状態で完了し有料 listing の取引」を
対象に、購入権利と初回トークンの付与経路を読み取り専用で突合する（Issue #25）。

- 手動付与は取引を伴わないため、**手動付与だけなら監査の対象取引にならない**
- ただし同一 buyer×listing に free 遷移のコンタクトがあると、手動付与の購入権利が
  「要確認（付与経路の証拠なし）」判定になりうる。この場合、topup の metadata の
  `stripe_payment_id` を確認し、`manual_grant:` で始まっていれば §2 の承認フローを
  経た正当な手動付与として扱う（付与時と operator を特定できる）
- 返却（`refund!`）後は refund の CreditTransaction が残るため、付与・返却のペアが
  監査記録で追える

---

## 7. 運用上の注意

- 本タスクは `DevPersonaPurchase` とは別物。production のガードを迂回するのでは
  なく、管理者の正規経路として production でも動作する
- `operator` 空でも実行できてしまうミスを防ぐため、未指定なら abort する。
  CI や cron から自動実行しない（人手の判断記録が前提のタスク）
- 付与トークン数は `config/billing.yml`（未設定時は既定値 100,000 tokens）に従う
- UI 上に「購入導線が無い」注意表示を出すかは別 Issue（フォローアップ候補）
