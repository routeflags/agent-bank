# 購入権利・初回トークンの読み取り専用監査手順（Issue #25）

> **目的**: 旧実装（`free` 遷移の逆ガード）により、実際の購入なしに
> `UserPlanSubscription`（購入権利）と初回トークンが付与された取引を、
> 本番・ステージングの実データから**読み取り専用**で洗い出し、
> オーナーが「巻き戻しが必要か」を判断できる材料を揃える
> **対象**: routeflags/agent-bank（Issue #25 / 修正は Issue #18）
> **関連**: [dev_persona_purchase_flow.md](./dev_persona_purchase_flow.md)（開発用付与）

---

## 1. 背景

Issue #18 の修正前の実装は、`TransactionProcessStateMachine` の `free` 遷移
（決済なしで成立した取引＝コンタクト等）で、

```ruby
if transaction.listing&.price&.positive?
  UserPlanSubscriptionService.create_on_purchase(transaction)
end
```

のように「listing の価格が正なら付与」という逆ガードをかけていた。
これにより**有料ペルソナにコンタクトしただけで**次の 2 点が付与されていた。

| 付与物 | 保存先 | 監査時の手がかり |
|--------|--------|------------------|
| 購入権利 | `user_plan_subscriptions`（person × listing） | 行の有無・作成時刻 |
| 初回トークン | `wallets` / `credit_transactions` の topup | `metadata.stripe_payment_id` = `initial_purchase_<transaction id>` |

`payment_reference`（= `CreditTransaction.metadata.stripe_payment_id`）は

- `initial_purchase_<取引ID>` … 取引を伴う購入付与（`create_on_purchase`）
- `dev_purchase_<乱数>` … 開発専用の購入再現（`DevPersonaPurchase`。production では無効）

の 2 系統しかないため、**topup の reference がその取引 ID に一致すれば、
「その取引の free 遷移で付与された」直接証拠になる**。

修正後のコードは `free` 遷移で付与しない（テストで固定済み）。本監査は
**過去に付与された実データの有無**を調べるためのものである。

---

## 2. 監査タスクの読み取り専用保証

`lib/tasks/lamprey_audit.rake` の `lamprey:audit:free_grants` は:

1. **SELECT 文しか発行しない**（作成・更新・削除のメソッドを一切呼ばない）
2. 実行中は MySQL セッションを `SET SESSION TRANSACTION READ ONLY` に設定し、
   誤って書き込みが発生しても DB 側で拒否される（終了時に `READ WRITE` に復帰）
3. spec（`spec/tasks/lamprey_audit_free_grants_spec.rb`）で
   実行前後の `UserPlanSubscription` / `CreditTransaction` / `Wallet` /
   `Transaction` の件数が不変であることを検証済み

つまりデータを書き換えることはない。**巻き戻し（無効化・補正）は実装していない**
（Issue #25 の範囲外。手順の概要は §6）。

---

## 3. 実行方法

### 3.1 基本（全件）

```bash
bin/rails 'lamprey:audit:free_grants'
```

### 3.2 絞り込み（任意。未指定なら全件）

```bash
# 対象期間（free 遷移時刻 last_transition_at、なければ created_at で判定）
bin/rails 'lamprey:audit:free_grants[2026-01-01,2026-12-31]'

# 期間 + community_id
bin/rails 'lamprey:audit:free_grants[2026-01-01,2026-12-31,3]'

# community のみ
bin/rails 'lamprey:audit:free_grants[, ,3]'
```

- 引数は `[since, until, community_id]`（いずれも任意）
- 不正な日付・community_id、`since > until` はエラー終了（abort）する
- タスク名の由来: `lamprey:` 名前空間の既存タスク（`lamprey:dev:grant_persona` 等）
  との一貫性

### 3.3 対象の定義（旧実装のガードと同値）

| 条件 | 意味 |
|------|------|
| `transactions.current_state = 'free'` | `free` 遷移で完了（決済なし） |
| `listings.price_cents > 0` | 旧実装が付与対象としていた「価格が正」 |

`price_cents` が NULL（= 旧実装の `price&.positive?` が偽）の listing は
対象外になり、旧実装の分岐と一致する。削除済み（`deleted`）の取引も
漏らさないために対象に含め、出力で `deleted=` を区別できる。

---

## 4. 出力の読み方

### 4.1 明細（1 取引 = 1 ブロック）

```text
#1 transaction_id=101 current_state=free deleted=false
  buyer      : alice (person_id=12)
  listing    : listing_id=77 「有料ペルソナ」 price_cents=1000 USD（監査時点の値）
  free完了   : 2026-01-05 10:00:00 (last_transition_at)
  wallet     : wallet_id=3 balance_cents=3000 USD
  購入権利   : subscription_id=5 status=active billing_model=token_based created_at=...
  初回トークン: credit_transaction_id=9 amount_cents=3000 reference=initial_purchase_101 ←この取引由来
  実購入     : なし（同一 buyer×listing の confirmed 取引なし）
  判定       : 巻き戻し候補（この取引の free 遷移で付与された直接証拠あり）
```

| 項目 | 読み方 |
|------|--------|
| `listing price_cents` | **監査時点**の価格。付与時点の価格は復元できない（§5 注意） |
| `購入権利` | 同一 person × listing の `user_plan_subscriptions` 行。複数行があれば全件表示 |
| `初回トークン … ←この取引由来` | reference がこの取引 ID に一致 = **直接証拠** |
| `参考 他取引由来` | 同一 buyer の他取引（`initial_purchase_<別ID>`）由来の topup |
| `参考 開発用付与` | `dev_purchase_*` の topup（開発環境での購入再現） |
| `実購入` | 同一 buyer × listing の `confirmed` 取引（正当な付与経路）と、その reference の一致状況 |

### 4.2 判定区分

| 判定 | 条件 | 巻き戻し判断 |
|------|------|--------------|
| **巻き戻し候補** | この取引由来トークンあり、実購入なし | 逆ガードの直接証拠あり。**検討対象** |
| **要判断** | この取引由来トークンあり、実購入（confirmed）もあり | 後から実購入した可能性。**個別判断** |
| **要確認** | 購入権利はあるが付与経路の証拠なし | 経路不明。**個別調査**（§5 参考） |
| **実購入の裏付けあり** | 同一 buyer×listing に confirmed 取引あり | 正当な付与の可能性 → **不要な可能性が高い** |
| **付与なし** | 購入権利もこの取引由来トークンもなし | 何も付与されていない → **不要** |

### 4.3 サマリ

```text
---
[lamprey:audit:free_grants] サマリ
  対象（free×有料 listing） : 3 件
  巻き戻し候補（この取引の free 遷移で付与された直接証拠あり） : 1 件
  ...
  オーナー判断が必要（巻き戻し候補＋要判断＋要確認） : 2 件
  実行条件: 期間=全期間 community_id=全件
  書き込み: なし（SELECT のみ。実行中セッションを READ ONLY に設定）
```

- **`オーナー判断が必要` の件数が今回の調査結果**である。
- `0 件` なら旧逆ガードによる付与データは存在しない（巻き戻し不要の根拠）。

---

## 5. 精度上の注意（誤検知・漏れ）

| 観点 | 内容 |
|------|------|
| 価格は監査時点 | listing の価格は後から変更できる。付与時は正だが監査時に 0 なら**漏れ**、付与時は 0 だが監査時に正なら**誤検知**の方向になる。`initial_purchase_<id>` の reference 判定までは価格に依存しないため、判定行で最終確認する |
| subscription 単体では経路不明 | `user_plan_subscriptions` は `confirmed`・`DevPersonaPurchase`・旧逆ガードの 3 経路で作られる。**確定できるのは topup の reference だけ**（`initial_purchase_<取引ID>` 一致 = 直接証拠） |
| 参考表示のみの reference | `dev_purchase_*` は取引に紐づかないため、どの pair 由来かは判定できない（参考表示） |
| `confirmed` のみを実購入とみなす | 付与は `confirmed` 遷移で発生するため。`paid` 未完了の取引は実購入とみなさない |
| N+1 クエリ | 明細ごとに少数クエリを発行する。件数が数十〜数百件でも監査用途なら問題にならない |

---

## 6. 巻き戻しが必要かの判断と手順（実装は別 Issue）

### 6.1 判断材料

1. **巻き戻し候補 = 0 件なら作業不要**（この監査結果を Issue #25 に記録して完了）
2. **巻き戻し候補がある場合**、取引ごとに確認する:
   - 購入権利（subscription）を無効化しても、当該 buyer が後から実購入
     （confirmed）していないか → §4.2 の「実購入」行を見る
   - 付与されたトークンを既に消費しているか（`usage_deduction` の有無・残高）→
     残高調整時に消費分を考慮する必要がある
3. **要判断 / 要確認** は reference と実購入行を突き合わせて個別に判断する

### 6.2 巻き戻し手順の概要（オーナー承認後・別 Issue で実装）

> [!WARNING]
> 以下は手順の概要にすぎない。実装・実行は Issue #25 の範囲外であり、
> **必ずオーナー承認を得て、事前にバックアップを取ってから**行うこと。

1. 対象の `user_plan_subscriptions` 行を確認し、`status` を `active` → `cancelled` に更新
   （行自体は監査証跡として残す。削除しない）
2. 付与された初回トークンの調整:
   - 残高が付与分ちょうどなら、`credit_transactions` に減算（refund 相当）を記録し
     `wallets.balance_cents` を減らす
   - すでに消費されている場合は、消費超過分の扱いをオーナーが決めてから反映する
3. 実行前後に対象レコードのダンプ（`SELECT ... INTO OUTFILE` または mysqldump の
   フィルタ抽出）を保存し、Issue に添付する

---

## 7. 本番・ステージング実行時の承認手順

本番 DB の**参照・更新はいずれもオーナー承認が必要**（AGENTS.md「エージェント
開発・運用ポリシー」§3）。本タスクは読み取り専用だが、本番 DB への接続自体が
承認対象である。

1. **承認依頼を Issue #25 に記録する** — 実行したいコマンド
   （例: `bin/rails 'lamprey:audit:free_grants[2026-01-01,,]'`）と目的を明記
2. **オーナーの承認を待つ** — 承認済みと推定してはならない
3. 承認されたら、AGENTS.md「データベース接続」節の接続情報で接続
   （SSH トンネル起動含む）。**本タスクは SELECT のみ・READ ONLY セッション**
4. 出力を丸ごと Issue #25 に貼付し、件数と判定内訳を報告する
5. 巻き戻しの要否を §6.1 の基準で提案し、**オーナーの判断を仰ぐ**
   （実行自体は別 Issue・別承認）

---

## 8. 開発環境での実行結果（2026-10-23 実測）

```bash
bin/rails 'lamprey:audit:free_grants'
```

```text
[lamprey:audit:free_grants] 読み取り専用監査（Issue #25）
  対象    : free 状態で完了し listing 価格が正の取引（旧逆ガードの対象）
  実行条件: 期間=全期間 community_id=全件
---
[lamprey:audit:free_grants] サマリ
  対象（free×有料 listing） : 0 件
  巻き戻し候補（この取引の free 遷移で付与された直接証拠あり） : 0 件
  要判断（この取引由来トークン＋実購入の裏付けあり） : 0 件
  要確認（購入権利はあるが付与経路の証拠なし） : 0 件
  実購入の裏付けあり（巻き戻し不要の可能性） : 0 件
  付与なし : 0 件
  オーナー判断が必要（巻き戻し候補＋要判断＋要確認） : 0 件
  実行条件: 期間=全期間 community_id=全件
  書き込み: なし（SELECT のみ。実行中セッションを READ ONLY に設定）
```

- 開発 DB（`sharetribe_development`）には `free` 状態の取引が存在しないため
  **0 件**。
- 期間・community 指定の引数パースも実CLIで確認済み
  （例: `bin/rails 'lamprey:audit:free_grants[2026-01-01,2026-12-31,1]'` →
  `実行条件: 期間=2026-01-01 〜 2026-12-31 community_id=1`）。

**検出漏れを避けるための検証**: `spec/tasks/lamprey_audit_free_grants_spec.rb` で、
旧実装と同等の付与（`create_on_purchase` を free 取引に実行）を擬似的に再現し、
- 直接証拠（`reference=initial_purchase_<id>`）と「巻き戻し候補」判定が出ること
- 無料 listing / confirmed 取引が対象外であること
- 期間・community の絞り込みが効くこと
- 実行前後で件数が変わらないこと（書き込みなし）

を確認済み（`spec/tasks` 19 examples 全パス）。
