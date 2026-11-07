// API 呼び出しの失敗を MCP のツールエラーに変換する。
//
// MCP では「ツールの実行は成功したが結果がエラー」を `isError: true` で
// 表す。例外を投げるとクライアントによってはプロトコルエラー扱いになり、
// モデルに理由が伝わらないため、ここで文言まで確定させておく。
//
// 注意: トークンは絶対にメッセージへ含めない。利用者のログや会話に残る。

import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";

/** 失敗の種類。文言は伴に `message` に確定させておく。 */
export type ApiErrorKind =
  | "auth" // 401
  | "forbidden" // 403
  | "not_found" // 404
  | "rate_limited" // 429
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
