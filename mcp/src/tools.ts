// MCP のツール定義（第 1 段は参照系 2 つ）。
//
// 入力スキーマは zod で書き、SDK が JSON Schema（tools/list）へ変換する。
// 上限・必須の宣言を schema 側に置くことで、モデルにもクライアントにも
// 同じ制約が見える。

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { AgentBankClient, MAX_LIMIT } from "./client.js";
import { toToolErrorResult } from "./errors.js";
import { formatPersonaDetail, formatPersonaList } from "./format.js";

export const SEARCH_PERSONAS_TOOL = "search_personas";
export const GET_PERSONA_TOOL = "get_persona";

/** 参照系なので読み取り専用であることをクライアントに伝える。 */
const READ_ONLY_ANNOTATIONS = { readOnlyHint: true, openWorldHint: true } as const;

export function registerTools(server: McpServer, client: AgentBankClient): void {
  server.registerTool(
    SEARCH_PERSONAS_TOOL,
    {
      title: "ペルソナを検索する",
      description: [
        "Agent Bank で公開されている AI ペルソナを検索し、一覧を返します。",
        "各件には id / title / description / price_cents / category / avg_rating /",
        "reviews_count / run_modes が含まれます。",
        "結果の id は get_persona に渡せます。",
        "スキル（指示文）の全文は含まれません。",
      ].join(""),
      inputSchema: {
        query: z
          .string()
          .min(1)
          .max(200)
          .optional()
          .describe("キーワード。タイトルや説明文への部分一致。省略時は全件"),
        category: z
          .string()
          .min(1)
          .max(100)
          .optional()
          .describe("カテゴリの url または id（例: business）"),
        limit: z
          .number()
          .int()
          .min(1)
          .max(MAX_LIMIT)
          .optional()
          .describe(`取得件数。1〜${MAX_LIMIT}。省略時はサーバー既定値`),
      },
      annotations: READ_ONLY_ANNOTATIONS,
    },
    async ({ query, category, limit }) => {
      try {
        const personas = await client.searchPersonas({ query, category, limit });
        return { content: [{ type: "text" as const, text: formatPersonaList(personas) }] };
      } catch (error) {
        return toToolErrorResult(error);
      }
    },
  );

  server.registerTool(
    GET_PERSONA_TOOL,
    {
      title: "ペルソナの詳細を取得する",
      description: [
        "Agent Bank のペルソナ 1 件の詳細を返します。",
        "一覧の項目に加えて、スキル（指示文）の先頭 200 文字の抜粋と、",
        "ダウンロードでスキル本文を渡せるかどうかが含まれます。",
        "スキル全文はこのツールでは取得できません。",
      ].join(""),
      inputSchema: {
        id: z
          .number()
          .int()
          .positive()
          .describe("ペルソナの id（search_personas の結果に含まれる）"),
      },
      annotations: READ_ONLY_ANNOTATIONS,
    },
    async ({ id }) => {
      try {
        const persona = await client.getPersona(id);
        return { content: [{ type: "text" as const, text: formatPersonaDetail(persona) }] };
      } catch (error) {
        return toToolErrorResult(error);
      }
    },
  );
}
