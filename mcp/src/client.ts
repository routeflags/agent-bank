// Agent Bank の参照系 API（/api/v1/personas）への HTTP クライアント。
//
// 認証は Bearer トークン（scope read）。トークンはリクエストヘッダにだけ載せ、
// ログにも例外の文言にも含めない。
//
// fetch は差し替え可能にしてある。テストは HTTP をモックするだけで、
// 本物のサーバーを必要としない。

import { AgentBankApiError, type ApiErrorKind } from "./errors.js";

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

export type FetchLike = typeof globalThis.fetch;

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

    const body = await this.request("/api/v1/personas", search);
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
   * GET を 1 回送る。失敗はすべて AgentBankApiError に正規化する。
   *
   * @param path `/api/v1/...` で始まるパス
   * @throws {AgentBankApiError} 401/403/404/429/5xx/ネットワーク/応答不正
   */
  private async request(path: string, search?: URLSearchParams): Promise<unknown> {
    const query = search && search.size > 0 ? `?${search.toString()}` : "";
    const url = `${this.baseUrl}${path}${query}`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        method: "GET",
        headers: {
          accept: "application/json",
          authorization: `Bearer ${this.token}`,
        },
        signal: controller.signal,
      });
    } catch (error) {
      throw this.networkError(error);
    } finally {
      clearTimeout(timer);
    }

    const body = await parseJson(response);
    if (!response.ok) throw this.httpError(response.status, body);
    return body;
  }

  /** HTTP ステータスを利用者が読める文言に変換する。 */
  private httpError(status: number, body: unknown): AgentBankApiError {
    const serverMessage = typeof body === "object" && body !== null
      ? asString((body as Record<string, unknown>)["error"])
      : "";

    const message = (() => {
      switch (status) {
        case 401:
          return "トークンが無効か失効しています。マイページの『MCP 接続』で再発行してください";
        case 403:
          return "このトークンには必要な権限がありません。『MCP 接続』で read スコープ付きのトークンを発行し直してください";
        case 404:
          return "指定のペルソナは見つかりません";
        case 429:
          return "リクエストが多すぎます。少し待って再試行してください";
        default:
          return serverMessage !== ""
            ? `Agent Bank API がエラーを返しました（HTTP ${status}）: ${serverMessage}`
            : `Agent Bank API がエラーを返しました（HTTP ${status}）`;
      }
    })();

    return new AgentBankApiError(kindOfStatus(status), message, { status });
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

function kindOfStatus(status: number): ApiErrorKind {
  if (status === 401) return "auth";
  if (status === 403) return "forbidden";
  if (status === 404) return "not_found";
  if (status === 429) return "rate_limited";
  return "server";
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
    throw new AgentBankApiError(
      "response",
      "Agent Bank API の応答を解釈できませんでした。API の仕様が変わった可能性があります",
    );
  }

  return value.filter(isRecord);
}

function readObject(body: unknown, key: string): Record<string, unknown> {
  const value = isRecord(body) ? body[key] : undefined;
  if (!isRecord(value)) {
    throw new AgentBankApiError(
      "response",
      "Agent Bank API の応答を解釈できませんでした。API の仕様が変わった可能性があります",
    );
  }

  return value;
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
