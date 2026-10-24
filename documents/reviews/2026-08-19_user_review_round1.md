# Lamprey（Capafy AI）実装レビュー（ユーザー目線）— Round 1

- 作成日: 2026-08-19
- 対象ブランチ: `feat/agent-bank`
- 対象コミット: `b0dab93b20ca09329536f3b018a85eeddb187d9d`
- 参照ドキュメント: `README.md`（Sharetribe Go 既定）, `AGENTS.md`, `documents/use_cases/capafy_ai_use_cases.md`, `documents/guides/billing_flow_implementation_guide.md`

---

## 0. 前提と確認方法（今回の制約）

### UI（ブラウザ）確認について

Browser スキルの手順どおりに接続を試みましたが、この実行環境では `agent.browsers.list()` が空（利用可能ブラウザなし）となり、自動ブラウザ操作ができませんでした。

- 代替として、HTTP レベル（`curl`）の確認と、実装コードの静的レビューを中心に行っています。
- 画面の最終確認は、下記の「9. 手動ブラウザ確認チェックリスト」を推奨します。

### 開発環境メモ

- `docker compose -f docker-compose.dev.yml up -d` は、ホスト側の `redis-server` が `:6379` を占有している場合に Redis のポート競合で失敗します（`docker-compose.dev.yml` の `redis: ports: "6379:6379"` が原因）。
- 一方で、`http://localhost:3000/` は応答しており、別プロセス（ローカル Rails など）でアプリが起動している状態でした。

---

## 1. プロダクトの趣旨（README / 資料からの把握）

- `README.md` はベースである Sharetribe Go の一般説明（メンテ終了の注意を含む）で、Lamprey 固有の目的やユースケースは直接は書かれていません。
- Lamprey（Capafy AI）は **AI ペルソナ（AI エージェント）を「出品・購入・チャット利用」できるマーケットプレイス**として拡張されています（`AGENTS.md` / `documents/use_cases/capafy_ai_use_cases.md`）。

---

## 2. 想定主要ユーザーフロー（ユーザー目線）

購入者:
1) トップで検索/カテゴリからペルソナを探す（UC-03）
2) ペルソナ詳細で価値を理解し、購入（UC-05）
3) 購入後、チャット開始（UC-06）
4) 残高不足時にトップアップ/自動リチャージ（UC-07/08）

出品者:
1) 出品フォームでペルソナを作成/公開（UC-04）
2) 売上/コミッションの把握（UC-09）

管理者:
1) コミッション設定・決済運用（UC-10）

---

## 3. 良い点（ユーザー体験に効く実装）

### 3-1. チャット体験（低レイテンシ/ストリーミング）

- Action Cable による chunk 配信（`app/channels/persona_chat_channel.rb`, `app/jobs/persona_executor_job.rb`）で、ユーザーは「待たされている感」を減らせます。
- `stream_error` に `error_type`（例: `insufficient_balance`）を載せられる設計は、UI で適切な導線（トップアップ誘導）に分岐しやすく良いです（`app/jobs/persona_executor_job.rb`）。

### 3-2. 購入検証（未購入のチャット防止）

- `POST /api/v1/chat_sessions` で `UserPlanSubscription(active)` を確認しており、**未購入ユーザーがチャット開始できない**制御がサーバー側にあります（`app/controllers/api/v1/chat_sessions_controller.rb`）。
- 既存セッションを返す（冪等）仕様は、UI の再試行/二重クリックに強いです（同ファイル）。

### 3-3. ウォレットの整合性

- `Wallet#deduct_for_usage!` が `lock!` + `transaction` で競合を抑止しており、同時実行時の二重控除を避けやすいです（`app/models/wallet.rb`）。
- `PersonaExecutorJob` が usage 記録 + 課金をトランザクションでまとめ、整合性を重視している点は良いです（`app/jobs/persona_executor_job.rb`）。

### 3-4. XSS 対策（チャット表示）

- AI 出力を HTML として描画する前にエスケープする実装があり、最低限の XSS 耐性があります（`client/app/startup/ChatPanelApp.js` の `sanitizeHTML`）。

---

## 4. 重大指摘（P0: 体験が成立しない/信頼を損ねる）

### P0-1. 「購入完了」→「購買権限(Subscription)」→「初回トークン付与」が実運用フローに未接続

現状:
- `UserPlanSubscriptionService` は実装され、初回トークン付与まで含まれています（`app/services/user_plan_subscription_service.rb`）。
- しかし **Transaction 完了時にこの Service が呼ばれていません**（コード上の呼び出し元が spec のみ）。
- その結果、ユーザーは「購入したのにチャットできない/残高が増えない」状態になり得ます。

ユーザー影響:
- UC-05（購入）→UC-06（チャット）の導線が断絶し、プロダクトの中核価値が成立しません。

推奨対応（最短）:
- Transaction の `completed` 遷移（または Stripe の成功 webhook / 決済完了コールバック）で `UserPlanSubscriptionService.create_on_purchase(transaction)` を確実に呼ぶ。
- 冪等性（重複購入/二重 webhook）に備え、Service の duplicate guard を活かす。

### P0-2. ウォレットトップアップ UI が「成功しない」可能性が高い（PaymentIntent の扱い）

現状:
- サーバーは `Stripe::PaymentIntent` を作成し、`confirm` では `status == "succeeded"` の場合のみウォレットへ反映します（`app/controllers/api/v1/wallet_topup_controller.rb`）。
- フロント（`client/app/startup/ChatPanelApp.js`）は **Stripe.js による決済確定を行わず**、PaymentIntent 作成直後に `/confirm` を叩いています。

ユーザー影響:
- ほとんどのケースで PaymentIntent は `requires_action` 等になり得て、ユーザーは「決済に失敗しました」を繰り返す（信頼毀損）。

推奨対応:
- 本番想定なら Stripe Elements/Stripe.js で `client_secret` を使って `confirmCardPayment`（または適切な確認フロー）を実装。
- MVP で UI を先出ししたいだけなら、「デモ/未実装」表示にして CTA を無効化するなど、誤解させない導線にする。

### P0-3. ロケールが `/ja` から `/fi` に飛ぶ（日本市場向けとして致命的）

確認:
- `/ja/listings/new` が `307` で `/fi/listings/new` にリダイレクトされました（ログイン済み Cookie あり）。
- 新規出品ページがフィンランド語で表示され、カテゴリは英語混在でした。

ユーザー影響:
- 日本向けリリースとして UI 体験が破綻します（離脱率が極端に上がる）。

推奨対応:
- コミュニティのデフォルトロケール/許可ロケール設定の見直し（Sharetribe の Community 設定）。
- ログイン後リダイレクトで locale を保持する（`/ja/sessions` → `/ja/...`）方針を明確化。

### P0-4. 検索が「使用できません」表示（コア機能の停止）

確認:
- トップに「現在検索が使用できません…」が出ます（`config/locales/ja.yml` の `search_engine_not_responding`）。

ユーザー影響:
- UC-03（閲覧・検索）が成立しません。マーケットプレイスで検索停止は致命傷です。

推奨対応:
- 本番: ThinkingSphinx / 検索基盤を必須として監視・自動復旧（ジョブ/ヘルスチェック）を整備。
- 開発: Sphinx なしでも「最低限の DB 検索（LIKE）」などのフォールバックを用意し、UX を壊さない。

---

## 5. 重要指摘（P1: 体験が悪い/将来の不具合を呼ぶ）

### P1-1. 未購入時の UI 導線が弱い（購入 CTA への誘導不足）

- サーバーは `error_type: "purchase_required"` を返しますが（`app/controllers/api/v1/chat_sessions_controller.rb`）、クライアント側でこの種別を明示的に扱っていません（例: `client/app/startup/ChatPanelApp.js` の `createSession`）。
- 推奨: purchase_required を受けたら「購入する」ボタン/決済導線へ案内し、エラーテキストだけで終わらせない。

### P1-2. 表示言語の混在

- 例: `ChatSession#system_prompt` が `"Available external APIs: ..."` と英語文言を生成します（`app/models/chat_session.rb`）。
- 例: エラーのフォールバックが `'An error occurred.'`（`client/app/startup/ChatPanelApp.js`）。
- 推奨: 生成/表示するユーザー向け文言は日本語に統一し、i18n へ寄せる。

### P1-3. SSE ストリーム API がクライアント未使用

- `GET /api/v1/chat_sessions/:id/stream`（`app/controllers/api/v1/chat_stream_controller.rb`）は存在しますが、クライアント側に `EventSource` 等の利用が見当たりません。
- 推奨: 使わないなら削除/凍結して保守面積を減らす。使うならクライアント統合し、Action Cable との役割分担（履歴同期 vs ストリーム）を明確にする。

---

## 6. 改善提案（UX を伸ばす具体案）

- チャット開始前に「購入済み」「残高」「1メッセージあたり概算消費」の見える化（不安を減らす）。
- 残高不足時はモーダルだけでなく、チャット入力欄の直上に常時バナーで再表示（復帰しやすい）。
- ストリーミング中の中断/再送/エラー復帰（再接続）導線を用意（とくにモバイル）。
- 出品フォーム: ペルソナの「最初の挨拶」「想定利用シーン」「禁止事項」など、購入判断に効く情報設計を強化。

---

## 7. セキュリティ/信頼性観点メモ（ユーザー体験に直結）

- Action Cable の購読/送信で `chat_session.person_id == current_user.id` を検証しており、最低限の越権は防げています（`app/channels/persona_chat_channel.rb`）。
- ただし、API コントローラが大量の `skip_before_action` を持つため、将来的に「想定外にスキップされてはいけない処理」まで外れていないかは要注意です（`app/controllers/api/v1/chat_sessions_controller.rb`, `app/controllers/api/v1/chat_stream_controller.rb`, `app/controllers/api/v1/wallet_topup_controller.rb`）。

---

## 8. 次のアクション（優先度順）

P0:
1) Transaction 完了→ `UserPlanSubscriptionService` 呼び出し（購買権限 + 初回トークン付与の自動化）
2) トップアップ: Stripe.js での確定フロー実装、または UI を「未実装」にして誤解防止
3) ロケール/リダイレクトの是正（日本向けで `/fi` へ飛ばない）
4) 検索: 本番必須化 + 開発フォールバック

P1:
1) purchase_required の UI 分岐（購入 CTA を出す）
2) 文言の日本語統一 + i18n 化
3) SSE API の整理（統合 or 削除）

---

## 9. 手動ブラウザ確認チェックリスト（推奨）

購入者:
- `/ja/` トップ: 検索の状態（有効/無効）と、空状態の訴求が自然か
- ペルソナ詳細（`/ja/listings/{id}-{slug}`）: 価格・説明・購入 CTA が明確か
- 購入完了→購入済み表示→チャット開始（未購入でチャットできないことも含む）
- チャット: 返信ストリーム、エラー表示、残高不足時のトップアップ誘導

出品者:
- 出品（`/ja/listings/new`）: 日本語 UI で迷わず入力できるか（ロケール崩れがないか）

管理者:
- コミッション/決済設定（管理画面）: 日本語化・設定値の説明が十分か

