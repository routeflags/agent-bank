# @agentbank/mcp

Agent Bank（Lamprey）の AI ペルソナを、MCP クライアント（Claude Desktop など）
から検索・参照するための **stdio サーバー**です。

- 同じマシンで子プロセスとして起動する（HTTP サーバーではありません）
- 認証は `Authorization: Bearer <トークン>`。読み取り専用（scope `read`）
- Node 18 以上（20.x で動作確認）

> 第 1 段の実装です。ツールは参照系の 2 つ（`search_personas` / `get_persona`）
> だけです。ペルソナの実行（`run_persona`）とスキル全文の取得
> （`get_persona_skill`）は第 2 段以降です。

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
  -d '{"name":"Claude Desktop","scopes":["read"]}'
# => {"raw_token":"...","api_token":{...}}
```

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
実行系（第 2 段）で行います。

---

## 6. エラーの見え方

API 呼び出しの失敗は、MCP のツールエラー（`isError: true`）として会話に返ります。
例外を投げないので、モデルは理由を読んで次の手を選べます。

| 状況 | メッセージ（要旨） |
|---|---|
| 401 | トークンが無効か失効しています。マイページの『MCP 接続』で再発行してください |
| 403 | このトークンには必要な権限がありません（scope 不足） |
| 404 | 指定のペルソナは見つかりません |
| 429 | リクエストが多すぎます。少し待って再試行してください |
| ネットワーク失敗 | `Agent Bank API（<URL>）に接続できませんでした: <原因>` |
| タイムアウト | 20 秒で打ち切り、接続先の確認を促す |
| 5xx | `Agent Bank API がエラーを返しました（HTTP <code>）` |

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
| `src/client.ts` | `/api/v1/personas` の HTTP クライアントとエラー変換 |
| `src/format.ts` | ツール応答のテキスト整形 |
| `src/tools.ts` | ツール定義（inputSchema）とハンドラ |
| `src/server.ts` | `McpServer` の組み立て（テスト用に分離） |

テストは SDK の `InMemoryTransport` を使い、実際の MCP プロトコル
（`tools/list` / `tools/call`）を通して検証します。stdio も子プロセスも使いません。

---

## 8. 関連

- Issue #143（MCP サーバー）第 1 段
- `documents/guides/mcp_setup.md` — 会員向けの最小手順
- 参照 API: `app/controllers/api/v1/personas_controller.rb`（#145）
