// 環境変数の読み取り。MCP サーバーはクライアント（Claude Desktop など）が
// 起動するため、設定はすべて環境変数で渡す。

/** 既定の接続先。公開マーケットプレイス。 */
export const DEFAULT_BASE_URL = "https://rakuichi-rakumon.jp";

export interface AgentBankConfig {
  /** Bearer トークン。ログ・エラーメッセージには出さない。 */
  token: string;
  /** 末尾スラッシュを除いた API のベース URL。 */
  baseUrl: string;
}

/** 環境変数が不正なときの失敗。main が stderr に出して終了する。 */
export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

/**
 * 環境変数から設定を組み立てる。
 *
 * `AGENTBANK_TOKEN` は必須。`AGENTBANK_BASE_URL` は省略時に既定値。
 * 検証は起動時に行い、リクエスト時に初めて失敗する状態にしない。
 *
 * @throws {ConfigError} トークンが無い、またはベース URL が http(s) でない
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): AgentBankConfig {
  const token = (env.AGENTBANK_TOKEN ?? "").trim();
  if (token === "") {
    throw new ConfigError(
      [
        "環境変数 AGENTBANK_TOKEN が設定されていません。",
        "  1. マーケットプレイスのマイページ →「MCP 接続」でトークンを発行してください。",
        '  2. MCP クライアントの設定（claude_desktop_config.json など）の "env" に',
        "     AGENTBANK_TOKEN を設定して、クライアントを再起動してください。",
        "  詳しい手順: mcp/README.md",
      ].join("\n"),
    );
  }

  return { token, baseUrl: normalizeBaseUrl(env.AGENTBANK_BASE_URL) };
}

/**
 * ベース URL を検証し、末尾スラッシュを落とす。
 *
 * @throws {ConfigError} 絶対 URL でない、または http(s) 以外のスキーム
 */
export function normalizeBaseUrl(raw: string | undefined): string {
  const trimmed = (raw ?? "").trim();
  if (trimmed === "") return DEFAULT_BASE_URL;

  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    throw new ConfigError(
      `環境変数 AGENTBANK_BASE_URL が URL として解釈できません: ${trimmed}`,
    );
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new ConfigError(
      `環境変数 AGENTBANK_BASE_URL は http:// か https:// で指定してください: ${trimmed}`,
    );
  }

  return trimmed.replace(/\/+$/, "");
}
