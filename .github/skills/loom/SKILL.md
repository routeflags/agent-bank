---
name: loom
description: >-
  textloom の統合 CLI `loom` で、テキスト（HTML / Twig / Markdown）を安全に編集・検証・変換する。
  変更は「対象のバイト範囲だけを置換し、対象外の不変を sha256 の証跡で示す」方式で行い、
  既定はプレビュー、書き込みは --write を付けたときだけ。失敗はすべて安全に中止（ファイルは変わらない）。
  使用時: 表の編集、リンクの修正・生存確認、本文の置換、公開 HTML の生成、表・Markdown・パス・変更ログの検証。
  HTML の規格・アクセシビリティ検証の正は consumer リポジトリの設定（html-validate 等）で、
  loom の `check html` は非公開 API（`--help` に出ない。代替を意図しない。issue #27）。
loom-version: 0.11.0
user-invocable: true
argument-hint: '<サブコマンド（例: table update FILE --table products …）>'
---

# loom（textloom 統合 CLI）を使うスキル

## Overview

`loom` は「テキストを壊さずに編集・検証・変換する」機械的なツールである。DB・公開・同期・分析は**対象外**（ファイルだけを扱う）。

- 層は 6 つ: `md`（Markdown → HTML）/ `table`（HTML の表の編集と検査）/ `text`（文字列置換と `<a>` の編集）/ `check`（検証）/ `find`（検索・列挙）/ `skill`（このスキル自身の配布・同期）。
- 実行時の依存は無し（Go の単一バイナリ。Node も Python も要らない）。
- このスキルは CLI に埋め込まれている（`loom skill`）。**手でコピーしない**: `loom skill install --to <repo> --write` で配置し、`loom skill check --path <repo>/.github/skills/loom/SKILL.md` で古さを検知する（sha256 比較・CI 可）。
- frontmatter の `loom-version` は対応する CLI のバージョン。CLI と食い違うと `loom skill check` が警告する。

## このスキルの読み分け（重要）

以下 2 つは有効な場所が違う。消費者リポジトリに居るときに「開発手順」を探さない。

- **消費者リポジトリで有効な手順**: このドキュメントの「鉄則」以降のすべて（`loom` コマンド、`--json` の読み方、困ったとき、導入手順）。thch-vape.shop / seo-operations などで実行する。
- **textloom リポジトリ内での開発手順（このリポジトリの中だけ）**: 末尾の「textloom リポジトリ内での開発手順」節。`make env` / `make diff-test` / 設計書パスは**ここにしか無い**（消費者リポジトリには Makefile も設計書も無い）。
- **HTML の検証はどちらが正か（重要）**: HTML の規格・アクセシビリティ検証の正は **consumer リポジトリの設定（`npx html-validate` 等）**。loom の `check html` は **非公開 API**（`loom --help` / `loom check --help` の一覧に出ない。互換保証なし）で、明示的に指示されたとき以外は選ばない（判定差の実測は README。issue #27）。`check lint` も同じく非公開 API で、**テンプレートを修正する**道具（`--fix`）と、その修正対象 3 ルールの検出であり、検証の代替ではない。

## 鉄則（エージェント向け）

1. **まずプレビュー**。`--write` を付けるまでファイルは 1 バイトも変わらない。プレビュー出力（差分・証跡・検査結果）を確認してから `--write` を付ける。
2. **HTML・Twig を sed / 正規表現で書き換えない**。表は `table`、リンクは `text link`、文字列は `text replace`、void 要素の書式は `check lint --fix`（非公開 API）を使う。
3. **表セル内の文字列置換は既定で拒否される**（`TABLE_CELL_HIT` / exit 1）。表の中を直したいときは `table update` / `add-row` などを使う。どうしても必要な場合だけ `--allow-table-cells` を付け、事後の `table validate` まで行う。
4. **Twig（`{{ }}` / `{% %}` / `{# #}`）を含む範囲は書き換えない**（`UNSUPPORTED_*` / exit 1）。テンプレートを含む文書では、まず `table inspect` で対象が編集可能かを確かめる。
5. **機械可読出力を使う**。判断は `--json` の封筒で行う（`status` / `exit_code` / `summary` / `issues` / `evidence`）。人が読む前提のテキスト出力を解析しない。
6. **終了コードと `status` で分岐する**: `0` 成功（プレビュー含む）/ `1` 検証 NG・安全中止（ファイル不変）/ `2` 使い方の誤り（引数・対象不在・設定不備）。**1 や 2 のときに「書き込まれたかも」と推測しない**（書き込みは検証を通った 1 回だけ）。`status` は `ok` / `issues_found`（検査は完走して指摘あり）/ `aborted`（検証 NG・安全中止・**検査を完了できない**）/ `usage_error` の 4 値で、**「指摘あり」と「完了できない」は `status` だけで分けられる**（`summary` のキーはコマンドごとに違う）。
7. **コミットは loom にやらせない**。書き込み後の `git diff` と `git commit` は利用側が行う。
8. **スキルが古いと言われたら更新する**（`loom skill check` が exit 1）。`loom skill install --to . --write --force` を実行してから作業を続ける。worktree が多い親ディレクトリでは `loom skill install --scan <parent-dir> --write --force` で一括更新できる（既定はプレビュー。異なるコピーは `--force` が無ければ `REFUSED` で exit 1）。

## コマンド早見表

```bash
# 表（HTML / Twig 専用。Markdown の表は `check md-tables`）
loom table list FILE                       # 表の一覧（索引・id・行数・列数）
loom table inspect FILE --table products   # 構造検査（V1〜V9 のうち検出可能な条件）
loom table validate FILE [--strict]        # 文書全体の表検査（読取のみ）
loom table update FILE --table products --key 商品B --column 価格 --value 2500            # セル更新
loom table update-batch FILE --table products --set '商品B:価格=2500' --set '商品C:価格=3000'
loom table add-row FILE --index 1 --values '["商品C","3000"]' [--position 3 | --after 商品B]
loom table delete-row FILE --table products --key 商品C
loom table move-row FILE --table products --key 商品C --to 0
loom table diff FILE --table products --key 商品B --column 価格 --value 2500   # 差分だけ見る
loom table apply FILE --instructions ops.json                                  # JSON 指示（表操作のみ）

# リンク（L1 列挙 / L2 生存確認 / L3 編集 / L4 一括置換）
loom find link FILE [--base-url https://example.com/]
loom check link FILE --base-url https://example.com/ --limit 20 [--delay 1]
loom text link set FILE --index 0 --set-href /guide/ --add-rel nofollow
loom text link replace FILE --from page.html --to /guide/
loom text link apply FILE --instructions links.json

# 文字列の置換・検索（表セル内は既定拒否）
loom find text FILE --query '台湾情勢' --with-location
loom text replace FILE --old '台湾の状況' --new '台湾情勢' [--allow-table-cells]

# 原稿 → 公開 HTML / 検証
loom md build sites/thch-vape/content/2026-10-08_guide-cbd.md --site thch-vape --out artifacts/loom/cbd.html
loom check md-tables sites/thch-vape/content/2026-10-08_guide-cbd.md [--html artifacts/loom/cbd.html]
loom check md-tables A.md B.md C.md --json                                   # 位置引数を複数（issue #35。1 プロセス・封筒 1 個・同じパスは 1 回だけ。不存在/ディレクトリ/glob は exit 2）
loom check md-tables --paths 'sites/**/*.md' --json                          # 複数ファイルを 1 つの封筒に（summary.files / issues[].path）
loom check lint --paths 'app/template/**/*.twig' --rules void,boolean-style,attr-quotes [--fix --write]   # テンプレートの修正と、その 3 ルールの検出（検証の代替ではない）
loom check paths [ROOT] [--csv FILE] [--missing-only] [--self-test]      # 文書中のパス参照の実在検査
loom check changelog FILE [--fix --write] [--self-test]                  # 変更ログの版番号の並び（C15）
loom check changelog A.md B.md --json                                    # 位置引数を複数（issue #38。1 プロセス・封筒 1 個・同じパスは 1 回だけ。不存在/ディレクトリ/glob は exit 2。--fix は 1 ファイル指定のときだけ）
loom check changelog --paths 'sites/**/*.md' --json                      # 複数ファイルを 1 つの封筒に（位置引数と併用可）
loom check changelog --paths-git '*.md' --json                           # git 管理下だけを対象に（1 プロセス）
loom check boundary [ROOT] --model FILE [--from-context-map FILE] [--self-test]   # コンテキスト境界の候補（B1・B3）＋文書との突き合わせ

# このスキル自身の配布・同期
loom skill install --to . [--write [--force]]                                  # 既定はプレビュー
loom skill install --scan <parent-dir> [--write [--force]]                     # 親ディレクトリ配下のコピーを一括（Delta worktree を含む。--to とは排他）
loom skill check --path .github/skills/loom/SKILL.md [--json]                  # 古ければ exit 1
```

**`check html` は非公開 API**（`--help` の一覧に出ない・互換保証なし。HTML の規格検証は consumer の設定＝`npx html-validate` 等が正。明示指示があるときだけ使う。issue #27）:

```bash
loom check html artifacts/loom/cbd.html [--compare-published /tmp/published.html]
loom check html a.html b.html --config .htmlvalidate.json --json           # 位置引数を複数（issue #38。--paths と同じ封筒。--compare-published は 1 ファイル指定のときだけ）
loom check html --paths 'app/template/**/*.twig' --paths 'app/Plugin/*/Resource/template/**/*.twig' --config .htmlvalidate.json --json
```

- `table` 層は **HTML（Twig 含む）専用**。`.md` / `.markdown` を渡すと exit 2（`usage_error`）で `check md-tables` へ誘導する（表の不存在と誤認しない）。
- `check md-tables` は Markdown の表（`md/T1`・`md/T2`・`md/T5`・`md/T6`。`--html` 併用時は `md/H1`・`md/H2`）を検査する。複数ファイルは**位置引数を 1..N 個**（issue #35。**存在するリテラルなファイル**。不存在・ディレクトリ・glob は exit 2（1 ファイル指定と同じ判定。glob は `--paths` を使う）。`--paths` と併用できる。同じパスは 1 回だけ検査）か `--paths` で指定し、封筒は 1 個（`summary.files` / `summary.checked` / `issues[].path`）。位置引数 1 個のときは従来の 1 ファイル出力。`--html` は 1 ファイル指定のときだけで、複数ファイル・`--paths` とは併用できない。
- **`check html` は非公開 API**（`--help` の一覧に出ない・互換保証なし。HTML の規格・アクセシビリティ検証の正は consumer の設定＝`npx html-validate` 等。loom は置き換えを意図しない。issue #27）: `check html` は Go 実装のリンター（`github.com/toba/go-html-validate`。**npx / Node を使わない**）で `.htmlvalidate.json` を読む。複数ファイルは**位置引数を 1..N 個**（issue #38。`check md-tables` と同じ確定ルール: 存在するリテラルなファイル。不存在・ディレクトリ・glob は exit 2。`--paths` と併用可・同じパスは 1 回だけ検査）でも `--paths` でも指定でき、封筒は 1 個。`summary.by_rule` にルール別件数、`issues[]` にファイル（`path`）・ルール（`html/<rule>`）・行・列を出す。**検出の位置はルール名・メッセージ
の値・要素の属性と関係（証拠）から解決**し（要素はタグ名の開始、属性自体は属
性名の開始、属性値の検出は値の開始。桁は UTF-16 コード単位）、同じ証拠の候補
が複数あるときだけ文書順で補う（**候補集合 = 発火集合**を保証できるときに
限り、発火し得ない要素へは付けない。issue #31。`detail.location_basis` が `rule+message+elem
ents+order` になる）。証拠が無い検出は `line` / `column` を出さず `detail.loc
ation: "unresolved"` になる（推測値を出さない。issue #26・#31）。html-validate との差（ルール集合・severity の対応表・実測）は README の「html-validate との差」を見る（`details.severity_map` / `details.ignored_rules` でも分かる）。ERROR が 1 件でもあれば exit 1（WARN だけなら 0）。`--compare-published` は位置引数 1 個・`--paths` 無しのときだけで、複数ファイル・`--paths` 併用は exit 2。
- `check lint` は**一括実行を止めない**。解析不能なファイルは `html/parse-failed`（severity ERROR）の issue として返り、他のファイルは検査を続ける。`--rules` は設定のルール名の別名（`void`・`attribute-boolean-style`・`html/attr-quotes` 等）を受ける。
- `--paths` は**ファイル木**（未追跡を含む）を展開する。git の管理下だけを対象にしたいときは `--paths-git GLOB`（`check lint` / `check html` / `check md-tables` / `check changelog`）を使う（issue #18）。選択は **git の pathspec 規則**なので `*` が `/` を跨ぐ（`app/template/*.twig` は下位も含む）。`--paths` とは併用できない。git が無い・失敗したときはファイル木へフォールバックし、`details.paths_git.used = false` と理由が出る。
- `check paths` は文書に書かれたパス参照（`sites/…` などの相対・`/Users/…` などの絶対）が実在するかを検査する（**読み取り専用**。書くのは監査結果の CSV だけ）。データ形式（`.json`・`.jsonl`・`.csv` 等）と記録・ビルド出力（`cassettes/`・`artifacts/`・`node_modules` 等の除外ディレクトリ）は走査しない。`--csv FILE` を省くと `artifacts/loom/path_audit.csv` を書く。MISSING が 1 件でもあれば exit 1（違反ではなく要確認。歴史記録の旧パスが多い）。`--missing-only` は一覧だけを絞る（CSV は全件）。`--self-test` は検出器の自己テスト（12 ケース。一時ディレクトリのみに書き、CSV を書かない）。
- `check changelog` は変更ログの版番号を**数値として**降順で比較する（`1.12 > 1.9`。文字列比較にしない）。`.md` は `## ～ #### 変更ログ` の節の最初の表、`.html` は最後の `<h2|h3 id="changelog">` の直後の表が対象。`--fix` は `--write` が要り、行の集合と内容を変えず順序だけ降順に並べ直す（行数が変わったら中止）。**並べ直したときは exit 0**（検出ありのときは exit 1）。どちらだったかは `summary.fixed` / `summary.fixed_rows` で分かる。自動で直せないもの（Version の重複など）は exit 1 のまま残る。複数ファイルは**位置引数を 1..N 個**（issue #38。`check md-tables` と同じ確定ルール: 存在するリテラルなファイル。不存在・ディレクトリ・glob は exit 2。`--paths` と併用可・同じパスは 1 回だけ検査）でも `--paths` でも指定でき、1 つの封筒（読み取り専用・`issues[].path`）。**`--fix` は 1 ファイル指定のときだけ**（`--paths`・複数の位置引数と併用すると exit 2）。書き込みは 1 ファイルずつ証跡を閉じる設計で、まとめると途中で失敗したときに部分適用が残るため。issue #17）。
- `check boundary` は consumer のモデル（`--model FILE` の JSON: `contexts` の `vocabulary`・`owned`、`excluded`、`skip_filenames`）で、所有パス外の語彙の使用（B1）と所有パス外の `.md` の置き場（B3）を候補として出す（**読み取り専用**。ファイルも CSV も書かない）。走査は Git 管理下の `.md`（`git ls-files '*.md'`。git が無ければファイル木）。候補は `issues[]`（`boundary/b1`・`boundary/b3`・severity `WARN`）に載り、1 件でもあれば exit 1（**違反ではない**。人間が引用か再定義かを判定する）。モデルの正本は consumer 側の文書で、loom に既定値は無い（`owned` / `excluded` は **`root` 相対**なので、リポジトリのルートを渡す）。`--from-context-map FILE` を足すと、正本の文書（「コンテキスト」と「所有パス」の表。所有パスはバッククォートで書く）とモデルを突き合わせ、差を `issues[]`（`boundary/model-drift`・severity `WARN`）に出す（例: `[C2] 所有パス Makefile がモデルに無い`）。`--from-context-map` は `--model` と一緒に使う（文書からの導出モデルでの走査はしない）。**照合は正規化して行う**（issue #19）: 末尾の `/`・`/*`・`/**` を落とし、`<site-id>` のような `<…>` は `*` にし、**末尾セグメントの末尾 `*` は名前の前方一致**として吸収する（`substance-dictionary*/**` と `substance-dictionary`・`substance-dictionary-html` は同じ家族）。部分木の粒度差（`X` と `X/y`）は差として出す（実在の差を隠さない）。

共通フラグ: `--json`（封筒 1 個）/ `--write`（書込み許可）/ `--dry-run`（`--write` の否定）/ `--out PATH` / `--force`（既存出力の上書き）/ `--show-evidence`。

## 典型的なワークフロー

**1. 表のセルを 1 つ更新する**

```bash
loom table inspect FILE --table products --json      # 行キーと列名を確認（編集可否もここで分かる）
loom table update FILE --table products --key 商品B --column 価格 --value 2500 --json
loom table update FILE --table products --key 商品B --column 価格 --value 2500 --write --json
loom table validate FILE --json                      # 事後の表検査（0 であること）
```

**2. リンクを貼り替える（サイト移転など）**

```bash
loom find link FILE --base-url https://example.com/ --json     # 対象を特定（index / href / in_table）
loom text link replace FILE --from page.html --to /guide/ --json
loom text link replace FILE --from page.html --to /guide/ --write --json
loom check link FILE --base-url https://example.com/ --limit 50 --json   # 生存確認（外部へ出るので --limit 必須）
```

**3. 本文の文言を置換する**

```bash
loom find text FILE --query '台湾の状況' --with-location --json   # ヒット位置（表の行・列も返す）
loom text replace FILE --old '台湾の状況' --new '台湾情勢' --json # 表セル内があれば TABLE_CELL_HIT で止まる
loom text replace FILE --old '台湾の状況' --new '台湾情勢' --write --json
```

**4. 原稿から公開 HTML を作って検証する**

```bash
loom md build sites/<site>/content/<manuscript>.md --site <site> --out artifacts/loom/out.html --json
loom md build sites/<site>/content/<manuscript>.md --site <site> --out artifacts/loom/out.html --verify --json   # 2 回生成してバイト一致を確認（不一致は書かずに exit 1・status: aborted・issues[] = md/reproducible・details.verify）
loom check md-tables sites/<site>/content/<manuscript>.md --html artifacts/loom/out.html --json
loom check html artifacts/loom/out.html --compare-published /tmp/published.html --json
```

原稿の本文に `---`（水平線）があっても `md build` は正常に変換する（可視要素には残さない）。

H1 直後の `>` ブロック（可視メタ）は `<blockquote class="article-quote article-quote--info">`、利益相反と本文中の引用は `<blockquote class="article-quote">` で出る（issue #30。可視メタを `<div>` で囲まない）。**#36 以降は可視メタを描くのは `法規制確認` と `ページ Version` の 2 項目だけ**。著者・所属・ORCID・ライセンスは「引用方法」節の推奨引用形式から読む（原稿の冒頭行は任意のフォールバック。両方無い項目だけ `欠落:` で失敗）、日付は原稿の変更ログ表（先頭行 = dateModified / 最終行 = datePublished）から取る（変更ログが無ければ冒頭の `最終更新` とファイル名の日付、それも無ければ JSON-LD から落とす。捏造しない）。

**5. 公開前の衛生チェック（void 要素の書式を直す）**

```bash
loom check lint --paths 'app/template/**/*.twig' --rules void,boolean-style,attr-quotes --json
loom check lint --paths 'app/template/**/*.twig' --rules void --fix --write --json   # 対象外バイトは不変
```

一括実行は解析不能ファイルがあっても続行する。`--json` の `status` が `issues_found`（完走して指摘あり）か `aborted`（解析不能・読込不能で検査を完了できない）かを示し、`summary.checked` / `failed` / `skipped` と `details.files[].status`、`issues[].path` で「どこまで見たか」が分かる。

**6. スキルを最新に保つ（消費者リポジトリ）**

```bash
loom skill check --path .github/skills/loom/SKILL.md --json   # exit 1 なら古い
loom skill install --to . --write --force --json              # 埋め込みスキルで更新
```

## `--json` の読み方

```json
{
  "tool": "loom", "version": "0.11.0", "layer": "table", "command": "update",
  "status": "ok",            // ok / issues_found / aborted / usage_error
  "exit_code": 0,
  "source": { "kind": "file", "path": "…", "sha256_before": "…" },
  "changed": true,
  "summary": { … },           // 層ごとの集計
  "issues": [ { "check": "table/V5", "severity": "ERROR", "message": "…", "line": 42 } ],
  "evidence": { "unchanged_prefix_bytes": 120, "prefix_sha256": "…", "suffix_sha256_before": "…", "suffix_sha256_after": "…", "before_sha256": "…", "after_sha256": "…" },
  "details": { "paths": { "out_dir": "…" } }
}
```

- `issues[].check` は層接頭辞つき（`table/V1`・`md/T1`・`html/void-style`・`html/parse-failed`・`boundary/model-drift`）。severity は `ERROR` / `WARN` / `INFO`。複数ファイルを 1 つにまとめるコマンド（`check html` / `check md-tables` / `check changelog` の位置引数 2 本以上と `--paths`）は、`issues[].path` にファイルを入れる。
- `check html` の `summary` は 1 ファイルでは `errors` / `warnings`、複数ファイル（位置引数 2 本以上 / `--paths`）では `files` / `checked` / `skipped` / `issues` / `errors` / `warnings` / `by_rule`（ルール別件数）を返す。`details.severity_map`（severity の対応表）と `details.ignored_rules`（設定にあるが loom では検査されないルール。`extends` の解決込み。`off` で切ったものは出さない）が差の説明になる。
- `check html` は `.htmlvalidate.json` の `extends`（`html-validate:recommended` など）を**loom 側で解決**する。プリセットで `off` のルールは検査せず、severity はプリセットの値を使う（issue #21）。**設定にも `extends` にも無いルールは loom の既定で有効**（上流は有効にしない）なので、上流に寄せたいときは `"class-pattern": "off"` のように設定で切る。
- `details.effective_config` が「どのルールが差か」を機械可読に示す（issue #24）: `defined_rules`（解決後の定義）/ `disabled_rules`（`off` で検査しない）/ `effective_rules`（実際に検査する）/ `extra_rules`（定義に無いのに有効 = 寄せられない差）/ `missing_rules`（定義にあるが実装が無い = `ignored_rules` と同じ）/ `presets` / `unresolved_extends`。
- `check md-tables`（複数ファイル: 位置引数 2 本以上 / `--paths`。issue #35）の `summary` は `files` / `checked` / `skipped` / `issues`、`check changelog`（複数ファイル: 位置引数 2 本以上 / `--paths`。issue #38）の `summary` は `files` / `checked` / `skipped` / `targeted` / `rows` / `findings` を返す。
- `check lint` の `summary` は `files` / `checked` / `failed` / `skipped` / `findings` を返し、`details.files[]` に `{path, status, findings, issues}`、`issues[]` に `path`（対象ファイル）が並ぶ。
- `check paths` の `summary` は `paths` / `exists` / `missing` / `skipped` / `missing_only` を返し、`details.rows[]` に `{source_file, source_line, matched_path, exists, resolved_path, alternatives}`、検出は `issues[]`（`path/missing`・severity `WARN`）、CSV は `artifacts[]` に載る。
- `check changelog` の `summary` は `files` / `rows` / `findings` / `fixed` / `fixed_rows` を返し、`details.rows[]` に `{version, line}`、検出は `issues[]`（`md/C15`・`html/C15`・severity `WARN`）、並べ直したときは `evidence`（before/after の sha256 と不変範囲）が載る。
- `check boundary` の `summary` は `files`（除外後の走査対象数）/ `b1` / `b3` / `drift`（`--from-context-map` の差の件数）を返し、`details.b1[]` に `{file, line, context, word, excerpt}`、`details.b3[]` に `{key, files}`、`details.drift[]` に `{kind, context, path, side, excluded_covered}`、検出は `issues[]`（`boundary/b1`・`boundary/b3`・`boundary/model-drift`・severity `WARN`）に載る（`changed` は常に false。`artifacts` は無い）。
- `evidence` は「対象外のバイトが変わっていない」ことの証跡。検算は `shasum -a 256` で行える（`prefix_sha256` は変更範囲より前のバイト列のハッシュ）。
- 書き込みを伴うコマンドは `changed: true` と `before_sha256` / `after_sha256` を返す。

## やってはいけないこと

- **DB・公開・同期・分析を loom に期待する**（対象外。EC-CUBE 側の運用で行う）。
- **原稿・正本を loom の出力先にする**（`md build` は原稿を読むだけで、出力は `--out` / `$LOOM_OUT_DIR` に書く）。
- **`--write` 無しで書き込む**ことはできない（できないのは仕様。プレビュー出力を確認してから付ける）。
- **表を sed / 正規表現で直す**（バイト安全の検証が無いので壊れる。`table` を使う）。
- **Markdown の表を `table` 層で見る**（対象外。`check md-tables` を使う）。
- **HTML の規格・アクセシビリティ検証を loom に置き換える**（検証の正は consumer の設定＝`npx html-validate` 等。`check html` は experimental。issue #27）。
- **`check link` を CI で回す**（外部サイトへ実際に HTTP を出す。ローカルは `--only-internal` か `--exclude` で絞る）。
- **`check paths` の MISSING を即「壊れている」と判断する**（`issues/*/` などの履歴記録に残る旧パスが大半。人間が引用か修正かを判定する）。
- **`check boundary` の B1・B3 を違反と判断する**（所有パス外の語彙の使用は候補。引用か再定義かを人間が判定する。モデルの正本は consumer 側の文書）。
- **スキルを手でコピーする**（`loom skill install` を使い、`loom skill check` で古さを検知する）。

## 困ったとき

```bash
loom --help                 # 層の一覧
loom table --help           # 層ごとのコマンド
loom table update --help    # 個別のフラグ
```

- 「`VERIFICATION_FAILED`」（exit 1）は「位置を確定できないので安全のため中止した」の合図。まず `--json` の `issues` を見て、該当ファイルを `--paths` で絞り、対象を 1 つずつ確認する。
- 「`html/parse-failed`」は**そのファイルの検査が完了していない**合図（他のファイルは検査済み。`summary.checked` / `failed` を見る）。属性の引用符（`<a href="x"class="y">` など）を整えて再実行する。
- `check html` の `detail.location: "unresolved"` は「そのルールの要素を
メッセージの値・属性から特定できず、位置を出さなかった」合図（推測値は出さな
い。issue #26）。`--json` の `issues[].message` と対象ファイルを見て手で探す。
`location_basis` が `rule+message+elements+order` のときは、同じ証拠の候補が
複数あり文書順で対応付けた合図（同じクラス名が複数の要素にある、など）。
- `check boundary --from-context-map` の `boundary/model-drift` は「文書（context-map）とモデル JSON が食い違っている」合図。文書かモデルのどちらかを直して揃える（`excluded_covered: true` は、モデルの `excluded` 配下に書かれた所有パスなので意図的な差でありうる）。
- `table` 層で「HTML 専用」と言われたら（exit 2 / `usage_error`）、入力が `.md` / `.markdown`。Markdown の表は `loom check md-tables` を使う。
- 「対象を一意に特定できない」と言われたら、`list` / `inspect` / `find link` で候補を確認し `--index` か `--table` で絞る。
- 「TABLE_CELL_HIT」は表のセルに当たった合図。`table update` に切り替える。
- 「UNSUPPORTED_*」は Twig 等のテンプレート構文。その範囲は手で編集するか、テンプレート側の設計を見直す。
- 「`loom skill check` が exit 1」はスキルが古い合図。`loom skill install --to . --write --force` で更新する。

## 導入手順（消費者リポジトリ）

```bash
# private リポジトリなので GOPRIVATE と認証を先に設定する（社内手順に従う）
export GOPRIVATE=github.com/routeflags/*
go install github.com/routeflags/textloom/cmd/loom@v0.11.0   # バージョンは固定する
loom skill install --to . --write                          # スキルを配置（既定はプレビュー）
loom skill check --path .github/skills/loom/SKILL.md       # CI に入れる（古ければ exit 1）
```

## textloom リポジトリ内での開発手順（このリポジトリの中だけ有効）

**消費者リポジトリでは実行できない**（Makefile・設計書・golden は textloom 側にしか無い）。

```bash
make env          # 実行環境とパス（golden 件数・fixture）を表示する
make build        # bin/loom を作る（手元確認は ./bin/loom を使う）
make diff-test    # 差分テスト（tests/diff/golden との比較。既存ケースの期待値は変更しない）
make test         # go test ./...
gofmt -l . && go vet ./...   # CI と同じ静的検査
```

- 設計書: `documents/20261017_textloom_design.md`（唯一の計画の正本）。移行の記録は `documents/20261017_textloom_go_migration.md`。
- このスキルの正本は `internal/usecase/skill/loom/SKILL.md`（`go:embed` で配布する）。`.github/skills/loom/SKILL.md` は同じ内容で、**バイト一致を Go テストで固定**している（乖離すると CI が落ちる）。
- スキルを変えたら両方を同じ内容にし、`go test ./internal/usecase/skill/` を通す。
