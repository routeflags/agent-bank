# ペルソナのスキルは system ロールで渡す

> **決定事項（Issue #57）**: ペルソナのスキル（`listings.skill_markdown`）は
> **system ロール（システムプロンプト）**としてプロバイダーに渡す。
> user メッセージの先頭に置く方式は採用しない。

---

## 1. 理由

- 会話履歴と分離され、毎ターン先頭に固定される枠だから
- モデルが「指示」として最も優先する枠だから（user メッセージ内に置くと、利用者の入力で上書きされやすい）
- 履歴が伸びても埋もれないから

## 2. プロバイダー別の渡し方

| プロバイダー | 渡し方 | 実装 |
|---|---|---|
| OpenAI Chat Completions | `messages[0] = { role: "system" }` | `Ai::OpenAiAdapter#stream`（受け取った配列をそのまま送信） |
| Anthropic Messages | メッセージ配列ではなく**トップレベルの `system` パラメータ** | `Ai::AnthropicAdapter#extract_system_and_messages` が変換済み |

## 3. 責務の分界

- 道具（function calling）は `tools` パラメータという別枠で渡す
- スキル本文・人格・口調・禁止事項は**ハーネスが system に合成**する
- その合成役が `Ai::ChatCompletionsBuilder`（`build_system_prompt`）で、現在は「スキル markdown → 口調指示 → 長さ指示」の順に連結している
- `ChatSession#system_prompt` はスキル markdown そのものを返す。出品の説明文（`description`）は店頭の紹介文であって人格定義ではないため、AI には渡さない

## 4. 禁止事項

- user メッセージの先頭に指示を埋め込む実装を残さないこと
- `ChatCompletionsBuilder` は履歴の user / assistant メッセージ本文を改変しないこと
- エラー通知用に `role: "system"` で保存した `chat_messages` は AI への送信対象に含めないこと（`ChatCompletionsBuilder` は user / assistant のみを対象とする）

## 5. 関連ファイル

- `app/services/ai/chat_completions_builder.rb` — system 先頭固定と履歴の組み立て
- `app/services/ai/open_ai_adapter.rb` — OpenAI への送信
- `app/services/ai/anthropic_adapter.rb` — Anthropic 用の system 分離
- `app/models/chat_session.rb` — `#system_prompt`（スキル markdown の取得）
- `app/jobs/persona_executor_job.rb` — 上記をつないで実行するジョブ

## 6. テスト

- OpenAI: `messages[0].role == "system"` であること（`spec/services/ai/openai_adapter_spec.rb`）
- Anthropic: トップレベル `system` に出て、メッセージ配列から消えること（`spec/services/ai/anthropic_adapter_spec.rb`）
- `ChatCompletionsBuilder#build` の戻り値の先頭が system メッセージであること（`spec/services/ai/chat_completions_builder_spec.rb`）
