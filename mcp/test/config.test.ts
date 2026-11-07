// 環境変数の解釈の検証。起動時に落ちるべきものが、リクエスト時に初めて
// 落ちないことを保証する。

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ConfigError, DEFAULT_BASE_URL, loadConfig, normalizeBaseUrl } from "../src/config.js";

describe("loadConfig", () => {
  it("AGENTBANK_TOKEN が無ければ ConfigError", () => {
    assert.throws(() => loadConfig({}), ConfigError);
    assert.throws(() => loadConfig({ AGENTBANK_TOKEN: "   " }), ConfigError);
  });

  it("エラー文言は発行手順と設定場所を示す", () => {
    assert.throws(
      () => loadConfig({}),
      (error: unknown) =>
        error instanceof ConfigError &&
        error.message.includes("AGENTBANK_TOKEN") &&
        error.message.includes("MCP 接続") &&
        error.message.includes("env"),
    );
  });

  it("トークンの前後の空白を落とす（コピーの改行対策）", () => {
    const config = loadConfig({ AGENTBANK_TOKEN: "  abc123\n" });

    assert.equal(config.token, "abc123");
    assert.equal(config.baseUrl, DEFAULT_BASE_URL);
  });

  it("AGENTBANK_BASE_URL で接続先を変えられる", () => {
    const config = loadConfig({
      AGENTBANK_TOKEN: "abc123",
      AGENTBANK_BASE_URL: "http://localhost:3000/",
    });

    assert.equal(config.baseUrl, "http://localhost:3000");
  });
});

describe("normalizeBaseUrl", () => {
  it("未指定なら既定の URL", () => {
    assert.equal(normalizeBaseUrl(undefined), DEFAULT_BASE_URL);
    assert.equal(normalizeBaseUrl(""), DEFAULT_BASE_URL);
  });

  it("末尾のスラッシュをすべて落とす", () => {
    assert.equal(normalizeBaseUrl("https://example.test///"), "https://example.test");
  });

  it("http / https 以外は受け付けない", () => {
    assert.throws(() => normalizeBaseUrl("ftp://example.test"), ConfigError);
    assert.throws(() => normalizeBaseUrl("example.test"), ConfigError);
  });
});
