// MCP サーバーの組み立て。stdio への接続は index.ts が行う。
//
// この分割はテストのため。HTTP クライアントを差し替えて、本物の stdio を
// 使わずにプロトコル（tools/list, tools/call）を検証できる。

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

import type { AgentBankClient } from "./client.js";
import { registerTools, type ToolOptions } from "./tools.js";

export const SERVER_NAME = "agentbank-mcp";
/** package.json の version と合わせる。 */
export const SERVER_VERSION = "0.1.0";

/** クライアント（モデル）に最初に伝える使い方。 */
export const SERVER_INSTRUCTIONS = [
  "Agent Bank（AI ペルソナのマーケットプレイス）のツールです。",
  "search_personas で候補を探し、get_persona で 1 件の詳細を確認してください。",
  "run_persona はペルソナを実行します。**実行のたびに課金される**ため、",
  "利用者が求めたときだけ呼び、失敗しても自動で再送しないでください。",
  "残高不足（402）のときは、案内された URL でチャージが必要です。",
  "スキル（ペルソナの指示文）の全文は取得できません。抜粋のみです。",
].join("");

export function createServer(
  client: AgentBankClient,
  options: ToolOptions = {},
): McpServer {
  const server = new McpServer(
    { name: SERVER_NAME, version: SERVER_VERSION },
    { instructions: SERVER_INSTRUCTIONS },
  );

  registerTools(server, client, options);
  return server;
}
