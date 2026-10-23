# 購入→チャット利用の再現手順（開発環境）

> **目的**: AI ペルソナの「購入 → チャット利用」を、実課金なしで開発環境で再現する
> **対象**: routeflags/agent-bank（Issue #18）
> **作成日**: 2026-10-23
> **関連 Issue**: #18「[致命的] 購入フローが動作せず、ペルソナを利用できない」

---

## 1. 前提となる仕組み

| 項目 | 内容 |
|------|------|
| チャット開始条件 | `UserPlanSubscription`（`status: active`）または無料ペルソナ（`Listing#free_to_use?`） |
| 購入権利の付与（本番） | 取引ステートマシンの `confirmed` 遷移（実決済の完了） |
| 購入権利の付与（開発/テスト） | `DevPersonaPurchase`（API / Rake。**production では常に無効**） |
| 決済プロバイダ | Freemius（Merchant of Record）。開発環境ではキー未設定のため実決済不可 |

> `free` 遷移（コンタクト等、決済なしで成立した取引）では購入権利を付与しない。
> 付与すると「コンタクトだけで購入権利＋初回トークンが得られる」購入偽装になるため。

---

## 2. 必要な環境

| ツール | バージョン | 備考 |
|--------|-----------|------|
| Ruby | 3.4.10 | `rbenv` 等 |
| MySQL | 8.x | `sharetribe_development` / `sharetribe_test` |
| Node.js | 18.16 | アセットビルド時のみ |

リポジトリのセットアップ（[local_development_setup.md](./local_development_setup.md) 参照）に加えて:

- `config/database.yml`（git 管理外）
- `.env`（git 管理外。§5 参照）

---

## 3. 手順 A: ブラウザ UI で通す（推奨）

### 3.1 開発購入を有効化する

開発購入は **二重ガード** で保護されている。両方を満たすときだけ有効になる。

1. `Rails.env` が `development` または `test`（`production` はフラグ値によらず無効）
2. 環境変数 `LAMPREY_ENABLE_DEV_PURCHASE` が truthy（既定は無効）

```bash
# .env（git 管理外）に追記
echo 'LAMPREY_ENABLE_DEV_PURCHASE=true' >> .env

# 起動中の場合は再起動して環境変数を読み込み直す
bin/rails server -b 0.0.0.0 -p 3000
```

> 既存プロセスを止めたくない場合は、プロセス限定で渡してもよい:
> `LAMPREY_ENABLE_DEV_PURCHASE=true bin/rails server -p 3001`

### 3.2 購入 → チャット

1. `http://localhost:3000/login` でログイン（開発用の購入者アカウント）
2. 有料の `run_online` ペルソナの詳細ページ（`/ja/listings/:id`）を開く
3. 「このスキルを利用する」を押す → チャットパネルが開く
4. 未購入のため「このペルソナを利用するには購入が必要です。」と「購入する」ボタンが表示される
5. 「購入する」を押す
   - 開発購入が有効: 購入権利（`UserPlanSubscription`）と初回トークンが付与され、続けてチャットセッションが作成され
る
   - 開発購入が無効: 「このペルソナの購入ページは現在準備中です。」（本番と同じ振る舞い）
6. 「購入が完了しました。チャットを開始できます。」が出たあと、メッセージを送信してストリーミング応答を確認

> 実 AI 応答まで確認するには AI プロバイダの API キー（例: `OPENAI_API_KEY`）と
> ウォレット残高（最低 10 cents）が必要。購入直後は初回トークンで残高が付与される。

---

## 4. 手順 B: Rake タスクで付与する（サーバー不要）

サーバーを起動せず、コマンドだけで購入状態を作れる。環境フラグは不要（オペレーターの明示操作とみなす）
が、`production` では実行できない。

```bash
# 引数: [listing_id, person]
# person は Person ID / username / メールアドレスのいずれか
bin/rails 'lamprey:dev:grant_persona[123,buyer@example.com]'
```

実行例:

```text
[lamprey:dev:grant_persona] 購入権利を付与しました: subscription_id=123
  person=devbuyer (xxxxxxxxxxxxxxxxxxxxxx)
  listing=123 サンプルペルソナ
  wallet_balance_cents=200000
```

2 回目以降は `既に購入済みです: subscription_id=...` と表示され、二重付与されない。

---

## 5. 手順 C: API を直接叩く（検証・自動化用）

```http
POST /api/v1/dev/persona_purchases
Content-Type: application/json

{ "listing_id": 123 }
```

| 状況 | ステータス | ボディ |
|------|-----------|--------|
| 開発購入が有効・未購入 | 201 | `{ "persona_purchase": { "subscription_id": 1, "status": "active", "billing_model": "token_based", "duplicate": false } }` |
| 既に購入済み | 200 | 同上（`"duplicate": true`） |
| 開発購入が無効（本番含む） | 404 | `{ "error": "見つかりません" }`（存在を隠す） |
| ペルソナが存在しない | 404 | `{ "error": "ペルソナが見つかりません" }` |
| 未ログイン | 401 | `{ "error": "ログインが必要です" }` |

その後、チャットセッションを作成できる:

```http
POST /api/v1/chat_sessions
Content-Type: application/json

{ "listing_id": 123 }
```

---

## 6. Freemius 未設定時の振る舞い（本番）

| 項目 | 未設定時の挙動 |
|------|----------------|
| `FreemiusClient.configured?` | `FREEMIUS_API_KEY` が無いため `false` |
| ウォレットチャージ | Stripe 直接連携にフォールバック（Stripe も未設定ならエラー、開発は擬似決済） |
| ペルソナ購入 | API 未実装のため購入導線は「準備中」。開発購入 API は 404（本番では無効） |

### 投入が必要な環境変数（値は書かない）

| 変数名 | 用途 | 必須 |
|--------|------|:----:|
| `FREEMIUS_API_KEY` | Freemius REST API の Bearer トークン | 必須 |
| `FREEMIUS_WEBHOOK_SECRET` | Webhook 署名検証（`x-signature`） | 必須 |
| `FREEMIUS_API_BASE_URL` | API のベース URL。既定は `https://api.freemius.com/v1` | 任意 |
| `LAMPREY_ENABLE_DEV_PURCHASE` | 開発購入の有効化。**production では効果なし** | 開発のみ |

投入手順（⚠️ 値はチャット・ログ・コミットに出さない）:

1. Freemius の Developer Dashboard で API トークンと Webhook シークレットを発行
2. 開発環境: `.env`（git 管理外）に追記する
3. 本番環境: デプロイ先のシークレット管理（環境変数）に登録する。ファイルに直書きしない
4. Webhook URL（`/webhooks/freemius`）を Freemius 側に登録する

> キー投入と実課金の実行は**オーナー承認が必要**。

---

## 7. 無料ペルソナ（価格 0 / 無料実行モード）の扱い

- 価格が未設定または 0、あるいは `default_run_mode == 'free'` のペルソナは **購入不要**（`Listing#free_to_use?`）。
  403 `purchase_required` を返さず、`UserPlanSubscription` が無くてもチャットセッションを作成できる。
- 購入権利が無い場合の `billing_model` は `token_based`（従量課金）。
- ⚠️ 既知の制約: 無料ペルソナでもトークン原価はウォレットから従量課金される（完全無料化は課金設計の変更であり別 Issue）。
- `run_online` 以外（`download` / `free`）のペルソナはチャットパネルがマウントされず、通常の注文フローになる。

---

## 8. 動作確認済みの検証（実測）

```bash
# 購入 → チャットの通しシナリオを含む
bundle exec rspec spec/requests/api/v1/dev_persona_purchases_spec.rb
bundle exec rspec spec/requests/api/v1/chat_sessions_spec.rb
bundle exec rspec spec/services/dev_persona_purchase_spec.rb
bundle exec rspec spec/services/persona_purchase_entitlement_spec.rb
bundle exec rspec spec/tasks/lamprey_dev_spec.rb

# 既存テスト（全体）
bundle exec rspec
```

上記は 2026-10-23 時点で全件成功（1409 examples, 0 failures）。ただし次に注意:

- 検証には **ビルド済みアセットが必要**（`app/assets/webpack/*`, `app/assets/javascripts/i18n/*.js`,
  `client/app/i18n/all.js`）。未ビルドのコピーではビューを描画する一部スペックが 500 になる。

```bash
# 初回のみ（Docker 環境で作業している場合は不要）
bundle install
bundle exec rake i18n:js:export        # app/assets/javascripts/i18n/*.js と client/app/i18n/all.js
cd client && npm install && npm run build:client && cd ..
```

> `bundle exec rake assets:precompile` を使うと、上記（`js:routes` / `i18n:js:export` / webpack）を
> 一括で実行できる。

---

## 9. トラブルシューティング

| 症状 | 原因と対処 |
|------|------------|
| 購入ボタンを押しても「準備中」と出る | `LAMPREY_ENABLE_DEV_PURCHASE` が未設定。`.env` に追記してサーバーを再起動 |
| API が 404 を返す | 開発購入が無効（`Rails.env` が development/test でない、またはフラグ未設定） |
| 購入後も 403 `purchase_required` | ペルソナが有料で、購入が別ユーザー/別 listing に付いている。`bin/rails runner` で `UserPlanSubscription.count` を確認 |
| 購入後に「残高が不足しています」 | ウォレット残高が 10 cents 未満。クレジットを追加するか再購入 |
| チャット応答が来ない | AI プロバイダの API キー未設定、または Delayed::Job ワーカー未起動（Docker で起動） |

---

## 10. セキュリティ留意事項

- 開発購入は `Rails.env.production?` で**常に**無効。`development` / `test` でも環境フラグが真のときのみ有効。
- `spec/services/dev_persona_purchase_spec.rb` / `spec/requests/api/v1/dev_persona_purchases_spec.rb` で
  「production では無効」「フラグ無効時は 404 で DB 不変」を固定している。
- 本番の購入導線（Freemius Checkout → サブスクリプション作成）は未実装。
  キー投入だけでは有効化されないため、別タスクでの設計・実装が必要。
