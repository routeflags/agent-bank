// ツール応答の整形。モデルが読みやすい日本語のテキストにする。
//
// price_cents（一覧・詳細の価格）は通貨を含まない最小単位の数値なので、
// 勝手に「円」と付けない（API が通貨を返さないため）。一方で実行 API の
// usage.cost_cents（請求額）と balance_cents（残高）は API の契約が「円」
// （app/controllers/api/v1/persona_runs_controller.rb）なので「円」を付ける。

import type { PersonaDetail, PersonaRunResult, PersonaSummary } from "./client.js";

export function formatPersonaList(personas: PersonaSummary[]): string {
  if (personas.length === 0) {
    return "該当するペルソナはありませんでした。query や category、sort の条件を変えて試してください。";
  }

  const blocks = personas.map(
    (persona, index) =>
      `${index + 1}. ${persona.title}\n${indent(summaryLines(persona).join("\n"))}`,
  );

  return [`${personas.length} 件のペルソナが見つかりました。`, "", ...blocks].join("\n");
}

export function formatPersonaDetail(persona: PersonaDetail): string {
  const lines = [
    persona.title,
    ...summaryLines(persona),
    "",
    "スキル抜粋（先頭 200 文字。全文はこのツールでは取得できません）:",
    persona.skill_excerpt || "（未設定）",
    "",
    `ダウンロードでスキルを渡せる設定: ${persona.skill_available_for_download ? "あり" : "なし"}`,
  ];

  return lines.join("\n");
}

/**
 * 実行結果。本文の後に、この 1 回の請求額と実行後の残高、継続用の
 * セッション id を添える（次の実行で `session_id` に渡せる）。
 */
export function formatPersonaRun(result: PersonaRunResult): string {
  return [
    result.content || "（応答の本文は空でした）",
    "",
    "---",
    [
      `消費: ${formatYen(result.usage.cost_cents)} 円`,
      `残高: ${formatYen(result.balance_cents)} 円`,
      `セッション: ${result.session_id}`,
    ].join(" / "),
    `（消費は今回の実行への請求額、残高は実行後の額。使用トークン: ${withThousands(result.usage.total_tokens)}）`,
  ].join("\n");
}

/** 一覧と詳細で共通の項目。 */
function summaryLines(persona: PersonaSummary): string[] {
  return [
    `id: ${persona.id}`,
    `カテゴリ: ${formatCategory(persona)}`,
    [
      `価格: ${withThousands(persona.price_cents)}（price_cents）`,
      formatRating(persona),
      `実行モード: ${formatRunModes(persona)}`,
    ].join(" / "),
    `説明: ${persona.description || "（未設定）"}`,
  ];
}

/** 絞り込みに使える `url` を添える。 */
function formatCategory(persona: PersonaSummary): string {
  const category = persona.category;
  if (!category) return "未分類";

  const label = category.name || category.url || String(category.id);
  return category.url ? `${label}（${category.url}）` : label;
}

function formatRating(persona: PersonaSummary): string {
  if (persona.reviews_count <= 0) return "評価: まだレビューがありません";

  return `評価: ${persona.avg_rating.toFixed(1)}（${withThousands(persona.reviews_count)} 件のレビュー）`;
}

function formatRunModes(persona: PersonaSummary): string {
  return persona.run_modes.length > 0 ? persona.run_modes.join(", ") : "未設定";
}

/** 3 桁区切り。Intl のロケールデータに依存させない。 */
function withThousands(value: number): string {
  return Math.trunc(value)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

/**
 * 円建ての金額。API は小数を含むことがある（請求額 0.59 円など）ため、
 * 整数なら 3 桁区切り、小数なら 2 桁までを出す。
 */
function formatYen(value: number): string {
  return Number.isInteger(value) ? withThousands(value) : value.toFixed(2);
}

function indent(text: string): string {
  return text
    .split("\n")
    .map((line) => `   ${line}`)
    .join("\n");
}
