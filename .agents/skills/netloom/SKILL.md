---
name: netloom
description: 外部 API（Google Trends / Apify / X / GA4 / GSC / PSI / Lighthouse / Playwright / devtools など）を netloom 経由で呼び出す。SNS・分析・検索順位・スクリーンショット・性能測定を「証跡（VCR カセット）付き」で取りたいときに使う。
---

# netloom（外部 API の薄いプロキシ）

**正本は `.github/skills/netloom/SKILL.md`**（`netloom skill install --to .` が配布する埋め込みスキル。
`netloom skill check --path .github/skills/netloom/SKILL.md` で一致を確認できる）。
作業前に正本を読むこと（送信元の一覧と版は `netloom version --sources` が唯一の正）。

## 守ること

- **1 コマンド = 1 往復**。答えは `--out PATH` に書かれる（stdout をパースしない）
- `.env` は netloom 自身が読む。flow スクリプトへ環境変数を渡すときだけ `--env-allow NAME,...`
  （`--env-allow` に無い名前は渡らない。未設定の名前を書くと exit 2）
- 往復は VCR カセット（JSONL）に残る。`--replay` でオフライン再現できる
- **副作用のある操作は明示フラグ必須**（本番書き込み `--allow-prod-write`、実メール送信など）。
  フラグを付けずに叩かない
- 認証情報・Cookie・トークンはログに出さない

## よく使う形

```bash
# スクリーンショット / DOM / 評価式 / 操作フロー（Playwright）
netloom playwright shot  --url URL --out PATH --viewport 1512x950 --wait-until networkidle
netloom playwright html  --url URL --out PATH
netloom playwright flow  --script FLOW.js --out RESULT.json --env-allow A,B

# 性能（Lighthouse / PageSpeed / CrUX）
netloom lighthouse run --url URL --out DIR
netloom psi --url URL --out PATH

# 分析・検索
netloom ga4 run-report --metrics screenPageViews --start-date 2026-11-01 --end-date 2026-11-07 --out PATH
netloom gsc query --site https://example.com --body @body.json --out PATH
netloom google-trends interest-over-time --keyword TEXT --out PATH
```

- Playwright のブラウザは `npx playwright install chromium` が前提（このマシンは導入済み）。
- `playwright flow` のスクリプトは「`async function` の本体（`page`, `context` を受ける）」。戻り値が `--out` の JSON になる。

## つまずきやすい点

- `--help` は全体ヘルプのみ（サブコマンド個別のヘルプは無い）。引数の正は正本スキルと `netloom --help` の該当行。
- `--to` / `--scan` / `--out` のどれが必須かはコマンドごとに違う。書かずに流すと exit 2。
