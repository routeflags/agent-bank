# @agentbank/mcp

Agent Bank（Lamprey）の AI ペルソナを、MCP クライアント（Claude Desktop など）
から検索・参照・実行するための **stdio サーバー**です。

- 同じマシンで子プロセスとして起動する（HTTP サーバーではありません）
- 認証は `Authorization: Bearer <トークン>`。スコープは参照系 `read`、実行系 `run`
- `run_persona` は **実行のたびに課金** されます（残高が要ります）
- Node 18 以上（20.x で動作確認）

| ツール | 説明 | 既定 |
|---|---|---|
| `search_personas` | ペルソナを検索 | 有効 |
| `get_persona` | ペルソナ 1 件の詳細（抜粋付き） | 有効 |
| `run_persona` | ペルソナを 1 回実行（**課金あり**） | 有効 |
| `get_persona_skill` | スキル本文（**準備中**） | 無効（`AGENTBANK_ENABLE_SKILL_DOWNLOAD=true` で表示） |

スキル（ペルソナの指示文）の**全文は取得できません**。先頭 200 文字の抜粋だけが
返ります。本文の受け渡し（`get_persona_skill`）は、API ができ次第の対応です。

---

## 1. セットアップ

```bash
cd mcp
npm ci || npm install
npm run build      # dist/ に出力
npm test           # ユニットテスト（HTTP はモック）
```

バイナリは `dist/index.js`です。`package.json` の `bin` は `agentbank-mcp`。

---

## 2. `AGENTBANK_TOKEN` の取得

1. Agent Bank にログインする
2. マイページ →「MCP 接続」を開く（画面は準備中。完了までは下記の API で発行）
3. トークン名（例: `Claude Desktop`）を付けて発行し、
   **表示された平文をその場でコピーする**

平文が表示されるのは発行時 1 回だけです。サーバーはハッシュ（digest）しか
保持しないため、後から再表示はできません（失くしたら再発行）。

画面ができるまでの発行方法（ログイン済みブラウザの Cookie を使う）:

```bash
# scope は read（参照）と run（実行）をカンマ区切りで
curl -X POST http://localhost:3000/api/v1/tokens \
  -H 'Content-Type: application/json' \
  -b cookies.txt \
  -d '{"name":"Claude Desktop","scopes":["read","run"]}'
# => {"raw_token":"...","api_token":{...}}
```

- `run_persona` を使うには **`run`** を許可します（`run` は `read` を包含するので
  `["run"]` だけでも参照系は使えます）
- トークンは**パスワードと同じ**に扱う。リポジトリ・チャット・スクリーンショットに
  貼らない
- 不要になったら「MCP 接続」画面（または `DELETE /api/v1/tokens/:id`）で失効する
- レート制限は **トークンあたり 60 リクエスト / 5 分**。超えると 429

---

## 3. 環境変数

| 変数 | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `AGENTBANK_TOKEN` | ✓ | — | 発行した Bearer トークン |
| `AGENTBANK_BASE_URL` | | `https://rakuichi-rakumon.jp` | API のベース URL。ローカル開発では `http://localhost:3000` |
| `AGENTBANK_ENABLE_SKILL_DOWNLOAD` | | （未設定） | `true` のときだけ `get_persona_skill` を一覧に出す。**既定で無効** |

`AGENTBANK_ENABLE_SKILL_DOWNLOAD` は `true`（大文字小文字は問わない）だけが有効です。
`1` や `yes` では有効になりません。有効にしても、スキル本文を返す API がまだ無い
ため、ツールは理由（対象外 / 準備中）だけを返します。

`AGENTBANK_TOKEN` が無い・`AGENTBANK_BASE_URL` が URL でない場合は、
**stdout に何も書かずに** stderr へ理由を出して終了コード 1 で終わります。
（stdout は MCP のプロトコル専用のため）

---

## 4. クライアント設定例

### Claude Desktop

設定ファイル:

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "agentbank": {
      "command": "node",
      "args": ["/absolute/path/to/agent-bank/mcp/dist/index.js"],
      "env": {
        "AGENTBANK_TOKEN": "発行したトークン",
        "AGENTBANK_BASE_URL": "https://rakuichi-rakumon.jp"
      }
    }
  }
}
```

- `args` は**絶対パス**にする（クライアントの作業ディレクトリは不定）
- `node` が見つからない場合は `which node` の結果（例: `/usr/local/bin/node`）を
  `command` に書く
- 設定変更後は Claude Desktop を**完全に終了して再起動**する

### Claude Code（CLI）

```bash
claude mcp add agentbank \
  --env AGENTBANK_TOKEN=発行したトークン \
  --env AGENTBANK_BASE_URL=https://rakuichi-rakumon.jp \
  -- node /absolute/path/to/agent-bank/mcp/dist/index.js
```

### ローカル開発（:3000 の Rails に繋ぐ）

```bash
AGENTBANK_TOKEN=<トークン> AGENTBANK_BASE_URL=http://localhost:3000 \
  node mcp/dist/index.js
```

---

## 5. ツール

### `search_personas`

公開されているペルソナを検索し、一覧を返します。

| 引数 | 型 | 必須 | 説明 |
|---|---|---|---|
| `query` | string (1〜200) | | キーワード。タイトル・説明文への部分一致 |
| `category` | string | | カテゴリの `url` か `id`（例: `business`） |
| `limit` | integer (1〜50) | | 取得件数。未指定はサーバー既定値（20） |

返り値（テキスト）の 1 件分:

```
1. ビジネス戦略アドバイザー
   id: 12
   カテゴリ: ビジネス（business）
   価格: 3,000（price_cents） / 評価: 4.5（12 件のレビュー） / 実行モード: chat, download
   説明: 事業計画の壁打ちができます。
```

`price_cents` は通貨を含まない最小単位の数値です（API が通貨を返さないため、
「円」などの単位は付けていません）。

### `get_persona`

1 件の詳細を返します。

| 引数 | 型 | 必須 | 説明 |
|---|---|---|---|
| `id` | integer (> 0) | ✓ | ペルソナの id（`search_personas` の結果に含まれる） |

一覧の項目に加えて次を含みます。

- `skill_excerpt`: スキル（指示文）の先頭 200 文字
- `ダウンロードでスキルを渡せる設定`: `skill_available_for_download` の表示

**スキル全文は API から返りません**（収益モデル上の制約）。全文の受け渡しは
`get_persona_skill`（準備中）の担当です。

### `run_persona`（課金あり）

ペルソナを 1 回実行し、応答本文を返します。

> [!IMPORTANT]
> **実行のたびに課金されます。** 同じ発話を送り直すと、もう一度課金されます。
> 実行にはウォレットの残高が必要です（不足すると 402）。

| 引数 | 型 | 必須 | 説明 |
|---|---|---|---|
| `persona_id` | integer (> 0) | ✓ | 実行するペルソナの id |
| `message` | string (1〜4000) | ✓ | ペルソナに送る発話 |
| `max_tokens` | integer (1〜4096) | | 応答の上限（出力トークン数）。省略時はモデル上限と残高から決まる |
| `session_id` | integer (> 0) | | 前回の実行のセッション id。同じ会話を続けるときだけ指定 |

返り値（テキスト）の例:

```
事業計画の骨子を作りました。（本文）

---
消費: 0.59 円 / 残高: 498.78 円 / セッション: 34
（消費は今回の実行への請求額、残高は実行後の額。使用トークン: 588）
```

- `消費` は **今回の実行への請求額（円）**です。AI の原価ではありません
- `残高` は実行後のウォレット残高（円）です
- `セッション` は継続用の id です。同じ会話を続けるとき `session_id` に渡します

課金を伴うため、このサーバーは**自動リトライしません**（429 の実行中も含む）。
失敗したら、状況を確かめてから利用者の判断で実行し直してください。

#### 残高不足（402）のとき

「残高が足りません」と、チャージ先の URL（`AGENTBANK_BASE_URL` + API が返す
`topup_url`）を返します。マイページでチャージしてから、実行し直してください。

### `get_persona_skill`（既定で無効・準備中）

スキル（指示文）本文の取得です。**既定では一覧に出ません。**

有効にするには環境変数を追加します。

```json
"env": {
  "AGENTBANK_TOKEN": "発行したトークン",
  "AGENTBANK_ENABLE_SKILL_DOWNLOAD": "true"
}
```

| 引数 | 型 | 必須 | 説明 |
|---|---|---|---|
| `id` | integer (> 0) | ✓ | ペルソナの id |

有効にしても、本文を取得する API がまだ無いため、本文は返しません。

- ダウンロード実行に対応していないペルソナ → 「このペルソナはスキル本文の配布に
  対応していません」
- 対応しているペルソナ → 「スキル本文の配布は準備中です」

どちらも `isError: true` で返します（本文を渡せていないため）。推測で本文を
組み立てることはしません。

---

## 6. エラーの見え方

API 呼び出しの失敗は、MCP のツールエラー（`isError: true`）として会話に返ります。
例外を投げないので、モデルは理由を読んで次の手を選べます。

参照系（`search_personas` / `get_persona` / `get_persona_skill`）:

| 状況 | メッセージ（要旨） |
|---|---|
| 401 | トークンが無効か失効しています。マイページの『MCP 接続』で再発行してください |
| 403 | このトークンには必要な権限がありません。マイページの『MCP 接続』で **read** スコープ付きのトークンを発行し直してください |
| 404 | 指定のペルソナは見つかりません |
| 429 | リクエストが多すぎます。少し待って再試行してください |
| ネットワーク失敗 | `Agent Bank API（<URL>）に接続できませんでした: <原因>` |
| タイムアウト | 20 秒で打ち切り、接続先の確認を促す |
| 5xx | `Agent Bank API がエラーを返しました（HTTP <code>）` |

実行系（`run_persona`）:

| 状況 | メッセージ（要旨） |
|---|---|
| 401 | 参照系と同じ（トークンの再発行） |
| 402 | 残高が足りません。実行の前にチャージしてください（チャージ先 URL 付き） |
| 403 | このトークンには **run** スコープがありません。マイページの『MCP 接続』で run を許可したトークンを発行し直してください |
| 404 `persona_not_found` | 指定のペルソナは見つかりません。`search_personas` で探し直してください |
| 404 `session_not_found` | `session_id` を省略して新しいセッションで実行するか、対象を確認してください |
| 422 | 入力が受け付けられませんでした: <API の説明>。`message` を空でない文字列に、`max_tokens` を正の整数にして実行し直してください |
| 429 `concurrent_run` | 同じトークンで別の実行が進行中です。終わってから実行し直してください |
| 429 `rate_limited` | リクエストが多すぎます。しばらく待ってから実行し直してください |
| 5xx `run_failed` | ペルソナの実行に失敗しました（理由と `error_type`）。AI プロバイダーの設定を確認 |

どちらの 429 も **自動では再送しません**（再送すると課金が重なるため）。
トークンそのものはエラーメッセージにもログにも出しません。

---

## 7. 開発

```bash
npm test    # tsc（test 用）→ node --test。HTTP は fetch をスタブ
npm run build
```

構成:

| ファイル | 役割 |
|---|---|
| `src/index.ts` | エントリ。設定を読み、stdio で接続 |
| `src/config.ts` | 環境変数の解釈・検証 |
| `src/client.ts` | API の HTTP クライアント（GET / POST）と応答の解釈 |
| `src/errors.ts` | HTTP エラー → ツールエラー（文言は `read` / `run` で分岐） |
| `src/format.ts` | ツール応答のテキスト整形 |
| `src/tools.ts` | ツール定義（inputSchema）とハンドラ |
| `src/server.ts` | `McpServer` の組み立て（テスト用に分離） |

テストは SDK の `InMemoryTransport` を使い、実際の MCP プロトコル
（`tools/list` / `tools/call`）を通して検証します。stdio も子プロセスも使いません。

---

## 8. 関連

- Issue #143（MCP サーバー）— 第 1 段（参照系 2 つ）、第 2 段（実行とスキル取得）
- `documents/guides/mcp_setup.md` — 会員向けの最小手順
- 参照 API: `app/controllers/api/v1/personas_controller.rb`（#145）
- 実行 API: `app/controllers/api/v1/persona_runs_controller.rb`（#144 / #148）
