#!/usr/bin/env node
// agentbank-mcp のエントリポイント。stdio で MCP サーバーを起動する。
//
// stdout は MCP の JSON-RPC 専用。診断メッセージは必ず stderr へ出す。
// 環境変数が足りないときも stdout には何も書かずに終了する。

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { AgentBankClient } from "./client.js";
import { ConfigError, loadConfig } from "./config.js";
import { createServer, SERVER_NAME, SERVER_VERSION } from "./server.js";

async function main(): Promise<void> {
  const config = loadConfig();
  const client = new AgentBankClient(config);
  const server = createServer(client);

  await server.connect(new StdioServerTransport());
  // トークンは出さない。接続先とバージョンだけ。
  console.error(`${SERVER_NAME} ${SERVER_VERSION} started (API: ${config.baseUrl})`);
}

main().catch((error: unknown) => {
  if (error instanceof ConfigError) {
    console.error(`[agentbank-mcp] ${error.message}`);
  } else {
    console.error("[agentbank-mcp] 起動に失敗しました:", error);
  }

  process.exit(1);
});
