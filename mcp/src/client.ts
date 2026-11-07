// Agent Bank の API への HTTP クライアント。
//
// 認証は Bearer トークン（参照系は scope read、実行系は scope run）。
// トークンはリクエストヘッダにだけ載せ、ログにも例外の文言にも含めない。
//
// fetch は差し替え可能にしてある。テストは HTTP をモックするだけで、
// 本物のサーバーを必要としない。
//
// 課金を伴う実行（runPersona）は **自動リトライしない**。再送すると
// 二重に課金されるため、失敗はすべて呼び出し元（モデル）に見せて判断させる。

import { AgentBankApiError, createApiError, type ApiScope } from "./errors.js";

export interface PersonaCategory {
  id: number;
  /** 絞り込みの `category` にそのまま渡せる。 */
  url: string;
  name: string;
}

/** `GET /api/v1/personas` の 1 件分。 */
export interface PersonaSummary {
  id: number;
  title: string;
  description: string;
  price_cents: number;
  category: PersonaCategory | null;
  avg_rating: number;
  reviews_count: number;
  run_modes: string[];
}

/** `GET /api/v1/personas/:id` の 1 件分。スキルは抜粋のみ。 */
export interface PersonaDetail extends PersonaSummary {
  skill_excerpt: string;
  skill_available_for_download: boolean;
}

export interface SearchPersonasParams {
  query?: string | undefined;
  category?: string | undefined;
  limit?: number | undefined;
}

/** `POST /api/v1/personas/:id/run` の引数。 */
export interface RunPersonaParams {
  /** 実行するペルソナの id。 */
  personaId: number;
  /** 送る発話。 */
  message: string;
  /** 出力トークンの上限（省略時はモデル上限と残高から決まる）。 */
  maxTokens?: number | undefined;
  /** 継続するセッション。省略時は新規作成。 */
  sessionId?: number | undefined;
}

/** 1 回の実行の使用量。 */
export interface PersonaRunUsage {
  total_tokens: number;
  /** この実行への **利用者への請求額（円）**。AI の原価ではない。 */
  cost_cents: number;
}

/** `POST /api/v1/personas/:id/run` の 200 応答。 */
export interface PersonaRunResult {
  content: string;
  usage: PersonaRunUsage;
  /** 実行後の残高（円）。 */
  balance_cents: number;
  session_id: number;
}

export type FetchLike = typeof globalThis.fetch;

/** `request` のオプション。省略時は参照系（GET / read）。 */
interface RequestOptions {
  method?: "GET" | "POST";
  search?: URLSearchParams;
  /** JSON にして本文に載せる値。undefined ならば本文なし。 */
  body?: unknown;
  /** 要求する scope。実行系は "run"。 */
  scope?: ApiScope;
}

export interface AgentBankClientOptions {
  token: string;
  baseUrl: string;
  /** テスト用の差し替え口。省略時は組み込みの fetch。 */
  fetchImpl?: FetchLike;
  timeoutMs?: number;
}

/** ページ上限。API 側のクランプ（上限 50）と揃える。 */
export const MAX_LIMIT = 50;

/** 1 リクエストの待ち時間の上限（ミリ秒）。 */
export const REQUEST_TIMEOUT_MS = 20_000;

export class AgentBankClient {
  private readonly token: string;
  private readonly baseUrl: string;
  private readonly fetchImpl: FetchLike;
  private readonly timeoutMs: number;

  constructor(options: AgentBankClientOptions) {
    this.token = options.token;
    this.baseUrl = options.baseUrl;
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch;
    this.timeoutMs = options.timeoutMs ?? REQUEST_TIMEOUT_MS;
  }

  /** `GET /api/v1/personas`。 */
  async searchPersonas(params: SearchPersonasParams = {}): Promise<PersonaSummary[]> {
    const search = new URLSearchParams();
    if (params.query) search.set("query", params.query);
    if (params.category) search.set("category", params.category);
    if (params.limit !== undefined) search.set("limit", String(params.limit));

    const body = await this.request("/api/v1/personas", { search });
    const personas = readArray(body, "personas");
    return personas.map((persona) => toPersonaSummary(persona));
  }

  /** `GET /api/v1/personas/:id`。存在しない・非公開は 404。 */
  async getPersona(id: number): Promise<PersonaDetail> {
    const body = await this.request(`/api/v1/personas/${id}`);
    const persona = readObject(body, "persona");
    return {
      ...toPersonaSummary(persona),
      skill_excerpt: asString(persona["skill_excerpt"]),
      skill_available_for_download:
        persona["skill_available_for_download"] === true,
    };
  }

  /**
   * `POST /api/v1/personas/:id/run`。課金を伴う 1 回の実行。
   *
   * 実行は同期で、応答は生成完了後に返る（1 リクエストに 1 応答）。
   *
   * @throws {AgentBankApiError} 402 残高不足 / 404 / 422 / 429 実行中 /
   *   5xx 実行失敗 / ネットワーク
   */
  async runPersona(params: RunPersonaParams): Promise<PersonaRunResult> {
    const payload: Record<string, string | number> = { message: params.message };
    if (params.maxTokens !== undefined) payload["max_tokens"] = params.maxTokens;
    if (params.sessionId !== undefined) payload["session_id"] = params.sessionId;

    const body = await this.request(`/api/v1/personas/${params.personaId}/run`, {
      method: "POST",
      body: payload,
      scope: "run",
    });

    return toRunResult(body);
  }

  /**
   * リクエストを 1 回送る。失敗はすべて AgentBankApiError に正規化する。
   * リトライはしない（実行系は再送が二重課金になるため）。
   *
   * @param path `/api/v1/...` で始まるパス
   * @param options メソッド・クエリ・本文・要求 scope（既定は GET / read）
   * @throws {AgentBankApiError} 401/402/403/404/422/429/5xx/ネットワーク/応答不正
   */
  private async request(path: string, options: RequestOptions = {}): Promise<unknown> {
    const search = options.search;
    const query = search && search.size > 0 ? `?${search.toString()}` : "";
    const url = `${this.baseUrl}${path}${query}`;
    const scope: ApiScope = options.scope ?? "read";

    const headers: Record<string, string> = {
      accept: "application/json",
      authorization: `Bearer ${this.token}`,
    };
    if (options.body !== undefined) headers["content-type"] = "application/json";

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        method: options.method ?? "GET",
        headers,
        ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
        signal: controller.signal,
      });
    } catch (error) {
      throw this.networkError(error);
    } finally {
      clearTimeout(timer);
    }

    const body = await parseJson(response);
    if (!response.ok) {
      throw createApiError(response.status, body, { scope, baseUrl: this.baseUrl });
    }
    return body;
  }

  /** 接続失敗・タイムアウト。原因は含めるが、トークンは含めない。 */
  private networkError(error: unknown): AgentBankApiError {
    if (isAbortError(error)) {
      return new AgentBankApiError(
        "network",
        `Agent Bank API への接続がタイムアウトしました（${Math.round(this.timeoutMs / 1000)} 秒）。ネットワークと AGENTBANK_BASE_URL を確認してください`,
        { cause: error },
      );
    }

    return new AgentBankApiError(
      "network",
      `Agent Bank API（${this.baseUrl}）に接続できませんでした: ${describeFailure(error)}。ネットワークと AGENTBANK_BASE_URL を確認してください`,
      { cause: error },
    );
  }
}

function isAbortError(error: unknown): boolean {
  return error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError");
}

/** fetch の失敗理由。undici は `fetch failed` だけなので cause を足す。 */
function describeFailure(error: unknown): string {
  if (!(error instanceof Error)) return String(error);
  const cause = error.cause;
  return cause instanceof Error && cause.message !== ""
    ? `${error.message}: ${cause.message}`
    : error.message;
}

/** JSON 本文。空・壊れた本文は undefined（呼び出し側で応答不正として扱う）。 */
async function parseJson(response: Response): Promise<unknown> {
  const text = await response.text();
  if (text.trim() === "") return undefined;

  try {
    return JSON.parse(text) as unknown;
  } catch {
    return undefined;
  }
}

function readArray(body: unknown, key: string): Record<string, unknown>[] {
  const value = isRecord(body) ? body[key] : undefined;
  if (!Array.isArray(value)) {
    throw unreadableResponse();
  }

  return value.filter(isRecord);
}

function readObject(body: unknown, key: string): Record<string, unknown> {
  return requireRecord(isRecord(body) ? body[key] : undefined);
}

/** 応答そのものがオブジェクトか（成功時のトップレベル）。 */
function requireRecord(value: unknown): Record<string, unknown> {
  if (!isRecord(value)) throw unreadableResponse();
  return value;
}

function unreadableResponse(): AgentBankApiError {
  return new AgentBankApiError(
    "response",
    "Agent Bank API の応答を解釈できませんでした。API の仕様が変わった可能性があります",
  );
}

/**
 * 実行 API の 200 応答。`usage.cost_cents` は請求額（円）、
 * `balance_cents` は実行後の残高（円）。
 */
function toRunResult(body: unknown): PersonaRunResult {
  const record = requireRecord(body);
  const usage = requireRecord(record["usage"]);

  return {
    content: asString(record["content"]),
    usage: {
      total_tokens: asNumber(usage["total_tokens"]),
      cost_cents: asNumber(usage["cost_cents"]),
    },
    balance_cents: asNumber(record["balance_cents"]),
    session_id: asNumber(record["session_id"]),
  };
}

function toPersonaSummary(source: Record<string, unknown>): PersonaSummary {
  return {
    id: asNumber(source["id"]),
    title: asString(source["title"]),
    description: asString(source["description"]),
    price_cents: asNumber(source["price_cents"]),
    category: toCategory(source["category"]),
    avg_rating: asNumber(source["avg_rating"]),
    reviews_count: asNumber(source["reviews_count"]),
    run_modes: Array.isArray(source["run_modes"])
      ? source["run_modes"].filter((mode): mode is string => typeof mode === "string")
      : [],
  };
}

function toCategory(value: unknown): PersonaCategory | null {
  if (!isRecord(value)) return null;

  return {
    id: asNumber(value["id"]),
    url: asString(value["url"]),
    name: asString(value["name"]),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function asNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
