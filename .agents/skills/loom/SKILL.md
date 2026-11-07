---
name: loom
description: textloom 統合 CLI `loom` で HTML / Twig / Markdown を安全に編集・検証・変換する。表の編集、リンクの修正、本文の置換、Markdown からの生成、規格・リンク切れの検証に使う。既定はプレビューで、`--write` を付けたときだけ書き込む。
---

# loom（textloom 統合 CLI）

**正本は `.github/skills/loom/SKILL.md`**（`loom skill install --to .` が配布。259 行）。
層は 6 つ: `md`（Markdown 変換）/ `table`（HTML・Twig の表編集）/ `text`（文字列置換・`<a>` 編集）/
`check`（検証）/ `find`（変更せず探す）/ `skill`（このスキル自体の配布）。

## 守ること

- **既定はプレビュー**。書き込むのは `--write` を付けたときだけ。既存ファイルの上書きは `--force` も要る
- 変更は「対象のバイト範囲だけを置換」し、**対象外が変わっていないことを sha256 で証跡**に出す。
  失敗時は安全に中止され、ファイルは変わらない
- 検証は consumer リポジトリの設定（`html-validate` 等）が正。`loom check html` は非公開 API で代替を意図しない
- 実行前に `loom --help`（層とフラグ）と正本スキルを読む

## よく使う形

```bash
loom find <layer> ...                 # 変更せずに列挙・検索
loom table update FILE --table NAME … # 表の編集（既定プレビュー）
loom text replace FILE --from '' --to '' # 文字列置換
loom md build FILE --out PATH         # Markdown → HTML 生成
loom check …                          # 検証の集約点
loom skill check --path .github/skills/loom/SKILL.md   # 配布済みスキルの鮮度確認
```

- 成果物の既定出力先は `artifacts/loom/…`（`--out` で変更可）。
- `--json` を付けると stdout が JSON 封筒 1 個になり、人向けログは stderr へ回る（自動処理向け）。
