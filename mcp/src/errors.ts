// API 呼び出しの失敗を MCP のツールエラーに変換する。
//
// MCP では「ツールの実行は成功したが結果がエラー」を `isError: true` で
// 表す。例外を投げるとクライアントによってはプロトコルエラー扱いになり、
// モデルに理由が伝わらないため、ここで文言まで確定させておく。
//
// 注意: トークンは絶対にメッセージへ含めない。利用者のログや会話に残る。
//
// 文言は「次に何をすればよいか」まで書く。同じステータスでも参照系（read）と
// 実行系（run）では意味が違う（402 は実行系だけの残高不足、429 は実行系では
// 同じトークンの実行中、など）ため、作成時に要求 scope を受け取って分岐する。

import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";

/** 要求するスコープ。参照系は read、課金を伴う実行系は run（read を包含）。 */
export type ApiScope = "read" | "run";

/** 失敗の種類。文言は併せて `message` に確定させておく。 */
export type ApiErrorKind =
  | "auth" // 401
  | "forbidden" // 403
  | "not_found" // 404
  | "payment_required" // 402 残高不足（実行系）
  | "invalid_request" // 422
  | "busy" // 429 concurrent_run（同じトークンで実行中）
  | "rate_limited" // 429 レート制限
  | "network" // 接続失敗・タイムアウト
  | "server" // 5xx など
  | "response"; // 本文が想定外

export interface ApiErrorOptions {
  status?: number;
  cause?: unknown;
}

export class AgentBankApiError extends Error {
  readonly kind: ApiErrorKind;
  readonly status: number | undefined;

  constructor(kind: ApiErrorKind, message: string, options: ApiErrorOptions = {}) {
    super(message, { cause: options.cause });
    this.name = "AgentBankApiError";
    this.kind = kind;
    this.status = options.status;
  }
}

export interface ApiErrorContext {
  /** 失敗したリクエストが要求した scope。文言の分岐に使う。 */
  scope: ApiScope;
  /** 402 の `topup_url`（相対パス）を絶対 URL にするためのベース URL。 */
  baseUrl: string;
}

/**
 * HTTP エラー応答を、利用者が次の行動を選べる文言付きの例外にする。
 *
 * @param status HTTP ステータス
 * @param body 応答本文（解釈できなければ undefined）
 * @param context 文言の分岐に使う要求 scope とベース URL
 */
export function createApiError(
  status: number,
  body: unknown,
  context: ApiErrorContext,
): AgentBankApiError {
  const failure = readFailure(status, body, context);
  const message = context.scope === "run" ? runMessage(failure) : readMessage(failure);

  return new AgentBankApiError(kindOfStatus(status, failure.code), message, { status });
}

/** 応答本文から取り出した失敗の材料。欠けている項目は空文字。 */
interface Failure {
  status: number;
  /** 機械が読むコード（例: insufficient_balance, session_not_found）。 */
  code: string;
  /** API が返した人向けの説明（例: message は必須です）。 */
  detail: string;
  /** 402 のチャージ導線（相対パス）。 */
  topupUrl: string;
  /** 502 の失敗分類（例: provider_not_configured）。 */
  errorType: string;
  /** 429 daily_limit_exceeded の上限（円）と当日の使用額（円）。 */
  limitCents: number;
  usedCents: number;
  baseUrl: string;
}

function readFailure(status: number, body: unknown, context: ApiErrorContext): Failure {
  const record = isRecord(body) ? body : {};

  return {
    status,
    code: asString(record["error"]),
    detail: asString(record["message"]),
    topupUrl: asString(record["topup_url"]),
    errorType: asString(record["error_type"]),
    limitCents: asNumber(record["limit_cents"]),
    usedCents: asNumber(record["used_cents"]),
    baseUrl: context.baseUrl,
  };
}

/** 参照系（scope read）の文言。 */
function readMessage(failure: Failure): string {
  switch (failure.status) {
    case 401:
      return INVALID_TOKEN_MESSAGE;
    case 403:
      return forbiddenMessage("read");
    case 404:
      return "指定のペルソナは見つかりません";
    case 429:
      return "リクエストが多すぎます。少し待って再試行してください";
    default:
      return serverFailureMessage(failure);
  }
}

/** 実行系（scope run・課金あり）の文言。 */
function runMessage(failure: Failure): string {
  switch (failure.status) {
    case 401:
      return INVALID_TOKEN_MESSAGE;
    case 402:
      return insufficientBalanceMessage(failure);
    case 403:
      return forbiddenMessage("run");
    case 404:
      return failure.code === "session_not_found"
        ? "指定のセッションは見つかりません。session_id を省略して新しいセッションで実行するか、get_persona で対象のペルソナを確認してください"
        : "指定のペルソナは見つかりません。search_personas で id を探し直してください";
    case 422:
      // 値域の数値はツールの inputSchema（tools.ts）が正本。ここでは
      // 送り直すという次の行動だけを伝える。
      return [
        "入力が受け付けられませんでした",
        failure.detail === "" ? "" : `: ${failure.detail}`,
        "。message を空でない文字列にし、max_tokens を正の整数にして実行し直してください",
      ].join("");
    case 429:
      // 実行は課金を伴うため、どの 429 でも自動では再送しない。
      return busyMessage(failure);
    default:
      return failure.status >= 500 ? runFailedMessage(failure) : serverFailureMessage(failure);
  }
}

const INVALID_TOKEN_MESSAGE =
  "トークンが無効か失効しています。マイページの『MCP 接続』で再発行してください";

/**
 * 403 の文言。要求 scope によって、発行し直すべきトークンが変わる。
 *
 * `read` は参照系、`run` は実行系（参照も含む）を指す。
 */
function forbiddenMessage(scope: ApiScope): string {
  if (scope === "run") {
    return "このトークンには run スコープがありません。マイページの『MCP 接続』で run を許可したトークンを発行し直してください";
  }

  return "このトークンには必要な権限がありません。マイページの『MCP 接続』で read スコープ付きのトークンを発行し直してください";
}

/** 402。`topup_url` は相対パスなので、ホストを付けて案内する。 */
function insufficientBalanceMessage(failure: Failure): string {
  const lines = ["残高が足りません。実行の前にウォレットへチャージしてください。"];
  const topupUrl = failure.topupUrl === "" ? "" : absoluteUrl(failure.baseUrl, failure.topupUrl);

  lines.push(
    topupUrl === "" ? "チャージはマイページの残高から行えます。" : `チャージ先: ${topupUrl}`,
  );
  return lines.join("\n");
}

/**
 * 429。実行系には 3 種類あり、待ち方がそれぞれ違う。
 *
 * - `concurrent_run`: 同じトークンの実行が進行中。終わるのを待つ。
 * - `daily_limit_exceeded`: 日次上限（既定 500 円／トークン）。待っても
 *   5 分では解消せず、**JST 0 時**にリセットされる。
 * - それ以外: レート制限（参照 60 / 実行 20 リクエスト・5 分）。
 */
function busyMessage(failure: Failure): string {
  if (failure.code === "concurrent_run") {
    return "同じトークンで別の実行が進行中です。その実行が終わってから、もう一度 run_persona を呼んでください（自動では再実行しません）";
  }

  if (failure.code === "daily_limit_exceeded") {
    const limit = yen(failure.limitCents);
    const used = yen(failure.usedCents);

    return [
      `本日の利用上限に達しました（上限 ${limit} / 使用 ${used}）。`,
      "上限は日本時間の 0 時にリセットされます。",
      "すぐに使いたい場合は、マイページの『MCP 接続』で新しいトークンを発行するか、管理者に上限の変更を相談してください（自動では再実行しません）。",
    ].join("");
  }

  return "リクエストが多すぎます。しばらく待ってから実行し直してください（自動では再実行しません）";
}

/** 円の表示。小数 2 桁まで、末尾の 0 は落とす。 */
function yen(cents: number): string {
  return `${Number.isInteger(cents) ? cents : cents.toFixed(2)} 円`;
}

/** 502 など。実行が成立しなかった理由と、次に確かめることを伝える。 */
function runFailedMessage(failure: Failure): string {
  // API の message は「…してください。」のように句点で終わることがある。
  // そのまま繋ぐと「。。」になるので、末尾の句読点は落としてから使う。
  const trimmedDetail = failure.detail.replace(/[。．.、]+$/u, "");
  const detail = trimmedDetail === "" ? "" : `: ${trimmedDetail}`;
  const errorType = failure.errorType === "" ? "" : `（error_type: ${failure.errorType}）`;

  return [
    `ペルソナの実行に失敗しました${detail}${errorType}。`,
    "AI プロバイダーの設定や上流の状態を確認し、必要なら実行し直してください",
    "（自動では再実行しません）。",
  ].join("");
}

/** それ以外のステータス。API が返したコードをそのまま添える。 */
function serverFailureMessage(failure: Failure): string {
  return failure.detail !== ""
    ? `Agent Bank API がエラーを返しました（HTTP ${failure.status}）: ${failure.detail}`
    : `Agent Bank API がエラーを返しました（HTTP ${failure.status}）`;
}

/** 相対パスにベース URL を繋いで絶対 URL にする。 */
function absoluteUrl(baseUrl: string, path: string): string {
  return `${baseUrl}${path.startsWith("/") ? path : `/${path}`}`;
}

function kindOfStatus(status: number, code: string): ApiErrorKind {
  if (status === 401) return "auth";
  if (status === 403) return "forbidden";
  if (status === 404) return "not_found";
  if (status === 402) return "payment_required";
  if (status === 422) return "invalid_request";
  if (status === 429) return code === "concurrent_run" ? "busy" : "rate_limited";
  return "server";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

/** 数値として読める値だけを返す（JSON の number を想定）。 */
function asNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

/**
 * 例外を MCP のツールエラー結果へ変換する。
 *
 * `AgentBankApiError` は組み立て済みの文言をそのまま使う。予期しない例外は
 * スタックトレースを出さず、型名だけを伝える（内部情報を会話へ漏らさない）。
 */
export function toToolErrorResult(error: unknown): CallToolResult {
  const text =
    error instanceof AgentBankApiError
      ? error.message
      : `予期しないエラーが発生しました（${errorName(error)}）。`;

  return { content: [{ type: "text", text }], isError: true };
}

/** 例外の型名。メッセージ本文は環境依存（パスなど）を含むため使わない。 */
function errorName(error: unknown): string {
  if (error instanceof Error) return error.name;
  return typeof error;
}
