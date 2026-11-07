// MCP サーバーを実際のプロトコル経路（tools/list, tools/call）で検証する。
//
// HTTP は差し替えた fetch でモックし、本物の API は呼ばない。
// トランスポートは SDK の InMemoryTransport なので、stdio や子プロセスも使わない。

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { Ajv } from "ajv";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { AgentBankClient, type FetchLike } from "../src/client.js";
import { createServer } from "../src/server.js";

/** テスト用トークン。応答に漏れていないことを確かめるためにも使う。 */
const TEST_TOKEN = "test-token-0123456789";
const BASE_URL = "https://example.test";

const BUSINESS_PERSONA = {
  id: 12,
  title: "ビジネス戦略アドバイザー",
  description: "事業計画の壁打ちができます。",
  price_cents: 3000,
  category: { id: 3, url: "business", name: "ビジネス" },
  avg_rating: 4.5,
  reviews_count: 12,
  run_modes: ["chat", "download"],
};

/** カテゴリ未設定・未評価・モード未設定のフォールバック確認用。 */
const BARE_PERSONA = {
  id: 13,
  title: "雑談相手",
  description: "",
  price_cents: 0,
  category: null,
  avg_rating: 0,
  reviews_count: 0,
  run_modes: [],
};

interface Harness {
  mcp: Client;
  requests: Array<{ url: URL; init: RequestInit | undefined }>;
  close: () => Promise<void>;
}

interface StartOptions {
  fetchImpl: FetchLike;
  token?: string;
  timeoutMs?: number;
  /** get_persona_skill を一覧に出すか（既定は出さない）。 */
  enableSkillDownload?: boolean;
}

async function startServer(options: StartOptions): Promise<Harness> {
  const requests: Harness["requests"] = [];
  const recordingFetch: FetchLike = (input, init) => {
    requests.push({ url: new URL(String(input)), init });
    return options.fetchImpl(input, init);
  };

  const agentBank = new AgentBankClient({
    token: options.token ?? TEST_TOKEN,
    baseUrl: BASE_URL,
    fetchImpl: recordingFetch,
    ...(options.timeoutMs === undefined ? {} : { timeoutMs: options.timeoutMs }),
  });

  const server = createServer(agentBank, {
    enableSkillDownload: options.enableSkillDownload === true,
  });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);

  const mcp = new Client({ name: "agentbank-mcp-test", version: "0.0.0" });
  await mcp.connect(clientTransport);

  return {
    mcp,
    requests,
    close: async () => {
      await mcp.close();
      await server.close();
    },
  };
}

/** 指定ステータスの JSON 応答を返すだけの fetch。 */
function respondWith(body: unknown, status = 200): FetchLike {
  return async () =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
}

async function callTool(
  mcp: Client,
  name: string,
  args: Record<string, unknown>,
): Promise<CallToolResult> {
  return (await mcp.callTool({ name, arguments: args })) as CallToolResult;
}

/** テキストブロックを 1 本にまとめる。 */
function textOf(result: CallToolResult): string {
  return result.content
    .filter((item): item is { type: "text"; text: string } => item.type === "text")
    .map((item) => item.text)
    .join("\n");
}

function toolByName(tools: Tool[], name: string): Tool {
  const tool = tools.find((candidate) => candidate.name === name);
  assert.ok(tool, `${name} が見つかりません`);
  return tool;
}

/** 全ツールの inputSchema を Ajv でコンパイルできるか確かめる。 */
function assertValidSchemas(tools: Tool[]): void {
  const ajv = new Ajv({ strict: false, allErrors: true });

  for (const tool of tools) {
    assert.equal(tool.inputSchema.type, "object");
    assert.doesNotThrow(
      () => ajv.compile(tool.inputSchema),
      `${tool.name} の inputSchema が不正な JSON Schema です`,
    );
  }
}

describe("tools/list", () => {
  it("既定では参照系 2 つと実行系 1 つの計 3 ツールを返す", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [] }) });
    t.after(harness.close);

    const { tools } = await harness.mcp.listTools();

    assert.deepEqual(
      tools.map((tool) => tool.name).sort(),
      ["get_persona", "run_persona", "search_personas"],
    );
    for (const tool of tools) {
      assert.equal(typeof tool.description, "string");
      assert.ok((tool.description ?? "").length > 0, `${tool.name} の説明が空です`);
    }
  });

  it("スキル本文の取得は既定で一覧に出さない（AGENTBANK_ENABLE_SKILL_DOWNLOAD 未設定）", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [] }) });
    t.after(harness.close);

    const names = (await harness.mcp.listTools()).tools.map((tool) => tool.name);

    assert.ok(!names.includes("get_persona_skill"), "既定で get_persona_skill が出ています");
  });

  it("AGENTBANK_ENABLE_SKILL_DOWNLOAD=true のときだけ 4 ツールになる", async (t) => {
    const harness = await startServer({
      fetchImpl: respondWith({ personas: [] }),
      enableSkillDownload: true,
    });
    t.after(harness.close);

    const { tools } = await harness.mcp.listTools();

    assert.deepEqual(tools.map((tool) => tool.name).sort(), [
      "get_persona",
      "get_persona_skill",
      "run_persona",
      "search_personas",
    ]);
  });

  it("inputSchema が JSON Schema として妥当で、説明文を持つ", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [] }) });
    t.after(harness.close);

    const { tools } = await harness.mcp.listTools();
    assertValidSchemas(tools);
  });

  it("スキル取得を有効にしてもすべての inputSchema が妥当", async (t) => {
    const harness = await startServer({
      fetchImpl: respondWith({ personas: [] }),
      enableSkillDownload: true,
    });
    t.after(harness.close);

    const { tools } = await harness.mcp.listTools();
    assertValidSchemas(tools);
  });

  it("search_personas の入力は query / category / limit で、すべて任意", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [] }) });
    t.after(harness.close);

    const tool = toolByName((await harness.mcp.listTools()).tools, "search_personas");
    const schema = tool.inputSchema as {
      properties: Record<string, Record<string, unknown>>;
      required?: string[];
    };

    assert.deepEqual(Object.keys(schema.properties).sort(), [
      "category",
      "limit",
      "query",
    ]);
    assert.deepEqual(schema.required ?? [], []);
  });

  it("limit は 1〜50 の整数として宣言される", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [] }) });
    t.after(harness.close);

    const tool = toolByName((await harness.mcp.listTools()).tools, "search_personas");
    const limit = (tool.inputSchema as { properties: Record<string, Record<string, unknown>> })
      .properties["limit"];

    assert.equal(limit?.["type"], "integer");
    assert.equal(limit?.["minimum"], 1);
    assert.equal(limit?.["maximum"], 50);

    const validate = new Ajv({ strict: false }).compile(tool.inputSchema);
    assert.equal(validate({ limit: 1 }), true);
    assert.equal(validate({ limit: 50 }), true);
    assert.equal(validate({ limit: 0 }), false);
    assert.equal(validate({ limit: 51 }), false);
    assert.equal(validate({ limit: 1.5 }), false);
  });

  it("get_persona の入力は必須の id", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ persona: BUSINESS_PERSONA }) });
    t.after(harness.close);

    const tool = toolByName((await harness.mcp.listTools()).tools, "get_persona");
    const validate = new Ajv({ strict: false }).compile(tool.inputSchema);

    assert.deepEqual(tool.inputSchema.required, ["id"]);
    assert.equal(validate({ id: 12 }), true);
    assert.equal(validate({}), false);
    assert.equal(validate({ id: 0 }), false);
    assert.equal(validate({ id: "12" }), false);
  });

  it("run_persona の入力は persona_id と message が必須で、上限を持つ", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [] }) });
    t.after(harness.close);

    const tool = toolByName((await harness.mcp.listTools()).tools, "run_persona");
    const schema = tool.inputSchema as {
      properties: Record<string, Record<string, unknown>>;
      required?: string[];
    };

    assert.deepEqual(Object.keys(schema.properties).sort(), [
      "max_tokens",
      "message",
      "persona_id",
      "session_id",
    ]);
    assert.deepEqual(schema.required, ["persona_id", "message"]);
    assert.equal(schema.properties["message"]?.["type"], "string");
    assert.equal(schema.properties["message"]?.["minLength"], 1);
    assert.equal(schema.properties["message"]?.["maxLength"], 4000);
    assert.equal(schema.properties["max_tokens"]?.["minimum"], 1);
    assert.equal(schema.properties["max_tokens"]?.["maximum"], 4096);

    const validate = new Ajv({ strict: false }).compile(tool.inputSchema);
    assert.equal(validate({ persona_id: 12, message: "こんにちは" }), true);
    assert.equal(
      validate({ persona_id: 12, message: "こんにちは", max_tokens: 4096, session_id: 34 }),
      true,
    );
    assert.equal(validate({ message: "こんにちは" }), false);
    assert.equal(validate({ persona_id: 12 }), false);
    assert.equal(validate({ persona_id: 0, message: "こんにちは" }), false);
    assert.equal(validate({ persona_id: 12, message: "" }), false);
    assert.equal(validate({ persona_id: 12, message: "あ".repeat(4001) }), false);
    assert.equal(validate({ persona_id: 12, message: "x", max_tokens: 0 }), false);
    assert.equal(validate({ persona_id: 12, message: "x", max_tokens: 4097 }), false);
    assert.equal(validate({ persona_id: 12, message: "x", max_tokens: 1.5 }), false);
    assert.equal(validate({ persona_id: 12, message: "x", session_id: 0 }), false);
  });

  it("run_persona は課金されることを annotations で伝える", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [] }) });
    t.after(harness.close);

    const tool = toolByName((await harness.mcp.listTools()).tools, "run_persona");

    assert.equal(tool.annotations?.["readOnlyHint"], false);
    assert.equal(tool.annotations?.["destructiveHint"], false);
    assert.equal(tool.annotations?.["idempotentHint"], false);
  });
});

describe("search_personas", () => {
  it("API の応答を一覧テキストに整形する", async (t) => {
    const harness = await startServer({
      fetchImpl: respondWith({ personas: [BUSINESS_PERSONA, BARE_PERSONA] }),
    });
    t.after(harness.close);

    const result = await callTool(harness.mcp, "search_personas", {
      query: "ビジネス",
      category: "business",
      limit: 2,
    });
    const text = textOf(result);

    assert.notEqual(result.isError, true);
    assert.match(text, /2 件のペルソナが見つかりました。/);
    // 1 件目: カテゴリ・評価・実行モードが入る
    assert.match(text, /1\. ビジネス戦略アドバイザー/);
    assert.match(text, /id: 12/);
    assert.match(text, /カテゴリ: ビジネス（business）/);
    assert.match(text, /価格: 3,000（price_cents）/);
    assert.match(text, /評価: 4\.5（12 件のレビュー）/);
    assert.match(text, /実行モード: chat, download/);
    assert.match(text, /説明: 事業計画の壁打ちができます。/);
    // 2 件目: 未設定項目のフォールバック
    assert.match(text, /2\. 雑談相手/);
    assert.match(text, /カテゴリ: 未分類/);
    assert.match(text, /評価: まだレビューがありません/);
    assert.match(text, /実行モード: 未設定/);
    assert.match(text, /説明: （未設定）/);
  });

  it("検索条件をクエリ文字列で API に渡し、トークンを Bearer で送る", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [BUSINESS_PERSONA] }) });
    t.after(harness.close);

    await callTool(harness.mcp, "search_personas", {
      query: "ビジネス",
      category: "business",
      limit: 3,
    });

    assert.equal(harness.requests.length, 1);
    const request = harness.requests[0];
    assert.ok(request);
    assert.equal(request.url.origin + request.url.pathname, `${BASE_URL}/api/v1/personas`);
    assert.equal(request.url.searchParams.get("query"), "ビジネス");
    assert.equal(request.url.searchParams.get("category"), "business");
    assert.equal(request.url.searchParams.get("limit"), "3");

    const headers = request.init?.headers as Record<string, string>;
    assert.equal(headers["authorization"], `Bearer ${TEST_TOKEN}`);
  });

  it("条件を省略したらクエリ文字列を付けない", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [] }) });
    t.after(harness.close);

    await callTool(harness.mcp, "search_personas", {});

    const request = harness.requests[0];
    assert.ok(request);
    assert.equal(request.url.search, "");
  });

  it("0 件ならその旨を返す（エラーにはしない）", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ personas: [] }) });
    t.after(harness.close);

    const result = await callTool(harness.mcp, "search_personas", { query: "存在しない" });

    assert.notEqual(result.isError, true);
    assert.match(textOf(result), /該当するペルソナはありませんでした/);
  });
});

describe("get_persona", () => {
  it("スキル抜粋とダウンロード可否を含む詳細を返す", async (t) => {
    const harness = await startServer({
      fetchImpl: respondWith({
        persona: {
          ...BUSINESS_PERSONA,
          skill_excerpt: "あなたは経営顧問です。",
          skill_available_for_download: true,
        },
      }),
    });
    t.after(harness.close);

    const result = await callTool(harness.mcp, "get_persona", { id: 12 });
    const text = textOf(result);

    assert.notEqual(result.isError, true);
    assert.equal(harness.requests[0]?.url.pathname, "/api/v1/personas/12");
    assert.match(text, /^ビジネス戦略アドバイザー/);
    assert.match(text, /スキル抜粋（先頭 200 文字。全文はこのツールでは取得できません）:/);
    assert.match(text, /あなたは経営顧問です。/);
    assert.match(text, /ダウンロードでスキルを渡せる設定: あり/);
  });
});

describe("実行の変換（run_persona）", () => {
  /** 実 API の 200 応答（#144）と同じ形。cost_cents は請求額（円）。 */
  const RUN_OK = {
    content: "事業計画の骨子を作りました。",
    usage: { total_tokens: 588, cost_cents: 0.59 },
    balance_cents: 498.78,
    session_id: 34,
  };

  it("本文と「消費 / 残高 / セッション」を整形して返す", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith(RUN_OK) });
    t.after(harness.close);

    const result = await callTool(harness.mcp, "run_persona", {
      persona_id: 12,
      message: "事業計画を一緒に考えて",
    });
    const text = textOf(result);

    assert.notEqual(result.isError, true);
    assert.match(text, /^事業計画の骨子を作りました。/);
    assert.match(text, /消費: 0\.59 円 \/ 残高: 498\.78 円 \/ セッション: 34/);
    assert.match(text, /使用トークン: 588/);
    assert.ok(!text.includes(TEST_TOKEN), "トークンが応答に含まれています");
  });

  it("POST で message / max_tokens / session_id を送る", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith(RUN_OK) });
    t.after(harness.close);

    await callTool(harness.mcp, "run_persona", {
      persona_id: 12,
      message: "続きをお願いします",
      max_tokens: 256,
      session_id: 34,
    });

    assert.equal(harness.requests.length, 1, "実行は 1 リクエストだけ（自動リトライしない）");
    const request = harness.requests[0];
    assert.ok(request);
    assert.equal(request.url.origin + request.url.pathname, `${BASE_URL}/api/v1/personas/12/run`);
    assert.equal(request.init?.method, "POST");

    const headers = request.init?.headers as Record<string, string>;
    assert.equal(headers["authorization"], `Bearer ${TEST_TOKEN}`);
    assert.equal(headers["content-type"], "application/json");
    assert.deepEqual(JSON.parse(String(request.init?.body)), {
      message: "続きをお願いします",
      max_tokens: 256,
      session_id: 34,
    });
  });

  it("max_tokens と session_id を省略したら本文に載せない", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith(RUN_OK) });
    t.after(harness.close);

    await callTool(harness.mcp, "run_persona", { persona_id: 12, message: "こんにちは" });

    const request = harness.requests[0];
    assert.ok(request);
    assert.deepEqual(JSON.parse(String(request.init?.body)), { message: "こんにちは" });
  });

  /** 実行系のエラー。どのケースも 1 回だけ叩き、トークンを漏らさない。 */
  const runErrorCases: Array<{
    name: string;
    status: number;
    body: unknown;
    expected: RegExp;
  }> = [
    {
      name: "402 は残高不足を伝え、チャージ URL にホストを付ける",
      status: 402,
      body: { error: "insufficient_balance", topup_url: "/ja/e2etester" },
      expected: new RegExp(`残高が足りません。[\\s\\S]*チャージ先: ${BASE_URL}/ja/e2etester`),
    },
    {
      name: "429 concurrent_run は実行中として待つよう伝える",
      status: 429,
      body: { error: "concurrent_run" },
      expected: /同じトークンで別の実行が進行中です。[\s\S]*自動では再実行しません/,
    },
    {
      name: "429 rate_limited はレート制限として伝える",
      status: 429,
      body: { error: "rate_limited" },
      expected: /リクエストが多すぎます。[\s\S]*自動では再実行しません/,
    },
    {
      name: "502 は実行失敗の理由と error_type を伝える",
      status: 502,
      body: {
        error: "run_failed",
        message: "AI プロバイダーが設定されていません",
        error_type: "provider_not_configured",
      },
      expected: /ペルソナの実行に失敗しました: AI プロバイダーが設定されていません（error_type: provider_not_configured）/,
    },
    {
      name: "404 persona_not_found はペルソナの探し直しを促す",
      status: 404,
      body: { error: "persona_not_found" },
      expected: /指定のペルソナは見つかりません。search_personas で id を探し直してください/,
    },
    {
      name: "404 session_not_found は session_id の外し方を伝える",
      status: 404,
      body: { error: "session_not_found" },
      expected: /指定のセッションは見つかりません。session_id を省略して/,
    },
    {
      name: "422 は受け付ける形を伝える",
      status: 422,
      body: { error: "invalid_request", message: "message は必須です" },
      expected: /入力が受け付けられませんでした: message は必須です。message を空でない文字列にし/,
    },
    {
      name: "403 は run スコープの発行を促す（read の文言とは分ける）",
      status: 403,
      body: { error: "insufficient_scope" },
      expected: /run スコープがありません。マイページの『MCP 接続』で run を許可したトークンを発行し直してください/,
    },
  ];

  for (const testCase of runErrorCases) {
    it(testCase.name, async (t) => {
      const harness = await startServer({
        fetchImpl: respondWith(testCase.body, testCase.status),
      });
      t.after(harness.close);

      const result = await callTool(harness.mcp, "run_persona", {
        persona_id: 12,
        message: "実行して",
      });
      const text = textOf(result);

      assert.equal(result.isError, true);
      assert.match(text, testCase.expected);
      assert.equal(harness.requests.length, 1, "失敗しても再送しない");
      assert.ok(!text.includes(TEST_TOKEN), "トークンがエラーメッセージに含まれています");
    });
  }

  it("403 の文言は参照系と実行系で分かれる", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ error: "insufficient_scope" }, 403) });
    t.after(harness.close);

    const readText = textOf(await callTool(harness.mcp, "get_persona", { id: 12 }));
    const runText = textOf(await callTool(harness.mcp, "run_persona", { persona_id: 12, message: "x" }));

    assert.match(readText, /read スコープ付きのトークンを発行し直してください/);
    assert.ok(!readText.includes("run を許可した"), "参照系に実行の案内が混ざっています");
    assert.match(runText, /run を許可したトークンを発行し直してください/);
  });
});

describe("スキル本文の取得（get_persona_skill・既定で無効）", () => {
  it("配布対象でないペルソナは isError と理由を返す", async (t) => {
    const harness = await startServer({
      fetchImpl: respondWith({
        persona: { ...BUSINESS_PERSONA, skill_excerpt: "あなたは経営顧問です。", skill_available_for_download: false },
      }),
      enableSkillDownload: true,
    });
    t.after(harness.close);

    const result = await callTool(harness.mcp, "get_persona_skill", { id: 12 });
    const text = textOf(result);

    assert.equal(result.isError, true);
    assert.equal(harness.requests[0]?.url.pathname, "/api/v1/personas/12");
    assert.match(text, /このペルソナはスキル本文の配布に対応していません/);
    assert.ok(!text.includes(TEST_TOKEN), "トークンが応答に含まれています");
  });

  it("配布対象でも本文は返さず、準備中と伝える（推測で本文を作らない）", async (t) => {
    const harness = await startServer({
      fetchImpl: respondWith({
        persona: {
          ...BUSINESS_PERSONA,
          skill_excerpt: "あなたは経営顧問です。",
          skill_available_for_download: true,
        },
      }),
      enableSkillDownload: true,
    });
    t.after(harness.close);

    const result = await callTool(harness.mcp, "get_persona_skill", { id: 12 });
    const text = textOf(result);

    assert.equal(result.isError, true);
    assert.match(text, /スキル本文の配布は準備中です/);
    // 抜粋以上の本文を出していないこと。
    assert.ok(!text.includes("あなたは経営顧問です。"), "スキル本文らしき内容を返しています");
  });
});

describe("エラーの変換（isError: true）", () => {
  const cases: Array<{
    name: string;
    status: number;
    body: unknown;
    expected: RegExp;
  }> = [
    {
      name: "401 はトークンの再発行を促す",
      status: 401,
      body: { error: "invalid_token" },
      expected: /トークンが無効か失効しています。マイページの『MCP 接続』で再発行してください/,
    },
    {
      name: "404 はペルソナが無いことを伝える",
      status: 404,
      body: { error: "ペルソナが見つかりません" },
      expected: /指定のペルソナは見つかりません/,
    },
    {
      name: "429 は待つよう伝える",
      status: 429,
      body: { error: "rate_limited" },
      expected: /リクエストが多すぎます。少し待って再試行してください/,
    },
    {
      name: "403 は権限不足を伝える",
      status: 403,
      body: { error: "insufficient_scope" },
      expected: /必要な権限がありません/,
    },
    {
      name: "5xx は API の失敗として伝える",
      status: 503,
      body: { error: "ペルソナの検索に失敗しました" },
      expected: /Agent Bank API がエラーを返しました（HTTP 503）/,
    },
  ];

  for (const testCase of cases) {
    it(testCase.name, async (t) => {
      const harness = await startServer({ fetchImpl: respondWith(testCase.body, testCase.status) });
      t.after(harness.close);

      const result = await callTool(harness.mcp, "get_persona", { id: 999 });
      const text = textOf(result);

      assert.equal(result.isError, true);
      assert.match(text, testCase.expected);
      assert.ok(!text.includes(TEST_TOKEN), "トークンがエラーメッセージに含まれています");
    });
  }

  it("ネットワーク失敗は原因を含める", async (t) => {
    const harness = await startServer({
      fetchImpl: async () => {
        throw new TypeError("fetch failed", {
          cause: new Error("connect ECONNREFUSED 127.0.0.1:3000"),
        });
      },
    });
    t.after(harness.close);

    const result = await callTool(harness.mcp, "search_personas", {});
    const text = textOf(result);

    assert.equal(result.isError, true);
    assert.match(text, /Agent Bank API（https:\/\/example\.test）に接続できませんでした/);
    assert.match(text, /connect ECONNREFUSED/);
    assert.match(text, /AGENTBANK_BASE_URL/);
    assert.ok(!text.includes(TEST_TOKEN), "トークンがエラーメッセージに含まれています");
  });

  it("タイムアウトは専用の文言にする", async (t) => {
    const harness = await startServer({
      timeoutMs: 10,
      fetchImpl: (_input, init) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => {
            const error = new Error("aborted");
            error.name = "AbortError";
            reject(error);
          });
        }),
    });
    t.after(harness.close);

    const result = await callTool(harness.mcp, "search_personas", {});

    assert.equal(result.isError, true);
    assert.match(textOf(result), /タイムアウトしました/);
  });

  it("応答の形が想定外なら解釈できないと伝える", async (t) => {
    const harness = await startServer({ fetchImpl: respondWith({ unexpected: true }) });
    t.after(harness.close);

    const result = await callTool(harness.mcp, "search_personas", {});

    assert.equal(result.isError, true);
    assert.match(textOf(result), /応答を解釈できませんでした/);
  });
});
