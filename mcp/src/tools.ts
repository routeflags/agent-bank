// MCP のツール定義。
//
// 入力スキーマは zod で書き、SDK が JSON Schema（tools/list）へ変換する。
// 上限・必須の宣言を schema 側に置くことで、モデルにもクライアントにも
// 同じ制約が見える。
//
// 登録するツール:
//   search_personas / get_persona  参照系（既定で有効）
//   run_persona                    実行系。**課金を伴う**（既定で有効）
//   get_persona_skill              スキル本文の受け渡し。**既定で無効**
//
// get_persona_skill は、受け渡し用の API がまだ無いため、
// `AGENTBANK_ENABLE_SKILL_DOWNLOAD=true` のときだけ一覧に出す。有効に
// しても本文は返さず、対象外・準備中という理由だけを返す（推測で本文を
// 作らない）。API ができたら取得処理をここに足す。

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

import { AgentBankClient, MAX_LIMIT } from "./client.js";
import { toToolErrorResult } from "./errors.js";
import { formatPersonaDetail, formatPersonaList, formatPersonaRun } from "./format.js";

export const SEARCH_PERSONAS_TOOL = "search_personas";
export const GET_PERSONA_TOOL = "get_persona";
export const RUN_PERSONA_TOOL = "run_persona";
export const GET_PERSONA_SKILL_TOOL = "get_persona_skill";

/** 1 回の実行で送れる発話の長さ。 */
export const MAX_MESSAGE_LENGTH = 4000;
/** 1 回の実行で指定できる出力トークンの上限。 */
export const MAX_OUTPUT_TOKENS = 4096;

/** 参照系なので読み取り専用であることをクライアントに伝える。 */
const READ_ONLY_ANNOTATIONS = { readOnlyHint: true, openWorldHint: true } as const;

/**
 * 実行系の注釈。課金されるため読み取り専用ではなく、同じ入力でも結果が
 * 変わりうる（べき等でない）。取り消し（destructive）ではない。
 */
const BILLABLE_ANNOTATIONS = {
  readOnlyHint: false,
  destructiveHint: false,
  idempotentHint: false,
  openWorldHint: true,
} as const;

/** スキル本文を配布していないペルソナ。 */
const SKILL_NOT_AVAILABLE_TEXT = [
  "このペルソナはスキル本文の配布に対応していません。",
  "本文の代わりに、get_persona のスキル抜粋（先頭 200 文字）で内容を確かめるか、",
  "run_persona で実行して応答を受け取ってください（実行は課金されます）。",
].join("");

/**
 * 配布対象だが、本文を返す API がまだ無い。
 * 本文を作ったり推測したりしてはいけない（出品者のノウハウそのもの）。
 */
const SKILL_PENDING_TEXT = [
  "スキル本文の配布は準備中です。",
  "このペルソナはダウンロード実行に対応していますが、本文を取得する API がまだ用意されていないため、",
  "本文は返せません。get_persona のスキル抜粋か、run_persona の実行結果を使ってください。",
].join("");

export interface ToolOptions {
  /** スキル本文ダウンロードのツールを一覧に出すか（既定 false）。 */
  enableSkillDownload?: boolean;
}

export function registerTools(
  server: McpServer,
  client: AgentBankClient,
  options: ToolOptions = {},
): void {
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

  server.registerTool(
    RUN_PERSONA_TOOL,
    {
      title: "ペルソナを実行する（課金あり）",
      description: [
        "Agent Bank のペルソナを 1 回実行し、応答本文を返します。",
        "**実行のたびに課金されます**（scope run を持つトークンが必要。read は包含されます）。",
        "返り値の末尾に 消費（今回の実行への請求額・円）/ 残高（実行後の残高・円）/ セッション id が付きます。",
        "同じ内容を送り直すと再度課金されるため、利用者の確認なしに繰り返さないでください。",
        "応答が 402 のときは残高不足です。案内された URL でチャージしてから実行し直してください。",
        "429（実行中）を含め、失敗したときに自動で再送しないでください。",
      ].join(""),
      inputSchema: {
        persona_id: z
          .number()
          .int()
          .positive()
          .describe("実行するペルソナの id（search_personas の結果に含まれる）"),
        message: z
          .string()
          .min(1)
          .max(MAX_MESSAGE_LENGTH)
          .describe(`ペルソナに送る発話（1〜${MAX_MESSAGE_LENGTH} 文字）`),
        max_tokens: z
          .number()
          .int()
          .min(1)
          .max(MAX_OUTPUT_TOKENS)
          .optional()
          .describe(
            `応答の長さの上限（出力トークン数）。1〜${MAX_OUTPUT_TOKENS}。省略時はモデル上限と残高から決まる`,
          ),
        session_id: z
          .number()
          .int()
          .positive()
          .optional()
          .describe("前回の実行のセッション id。同じ会話を続けるときだけ指定する（省略時は新規）"),
      },
      annotations: BILLABLE_ANNOTATIONS,
    },
    async ({ persona_id, message, max_tokens, session_id }) => {
      try {
        const result = await client.runPersona({
          personaId: persona_id,
          message,
          ...(max_tokens === undefined ? {} : { maxTokens: max_tokens }),
          ...(session_id === undefined ? {} : { sessionId: session_id }),
        });
        return { content: [{ type: "text" as const, text: formatPersonaRun(result) }] };
      } catch (error) {
        return toToolErrorResult(error);
      }
    },
  );

  // 既定では一覧に出さない。有効にしても本文は返さない（API 未実装）。
  if (options.enableSkillDownload === true) {
    server.registerTool(
      GET_PERSONA_SKILL_TOOL,
      {
        title: "ペルソナのスキル本文を取得する（準備中）",
        description: [
          "ペルソナのスキル（指示文）本文を取得します。",
          "このツールは既定では無効で、AGENTBANK_ENABLE_SKILL_DOWNLOAD=true のときだけ一覧に表示されます。",
          "本文を渡せるのはダウンロード実行に対応したペルソナだけです。",
          "本文を取得する API はまだ用意していないため、現在は本文を返さず、対象外・準備中という理由だけを返します。",
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
          // 配布対象かは詳細 API の skill_available_for_download で判定する。
          const persona = await client.getPersona(id);
          return {
            content: [
              {
                type: "text" as const,
                text: persona.skill_available_for_download
                  ? SKILL_PENDING_TEXT
                  : SKILL_NOT_AVAILABLE_TEXT,
              },
            ],
            // どちらの経路でも本文は渡せていない。取得できたと誤解させないよう
            // isError で返す（理由は本文で説明済み）。
            isError: true,
          };
        } catch (error) {
          return toToolErrorResult(error);
        }
      },
    );
  }
}
