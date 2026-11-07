# 計画書 — GitHub 調達スキルの初期シード商品登録（60件）

作成日: 2026-11-06 / 対象ブランチ: main
依頼: social-media-operations の `data/github/README.md` にある初期シードのうち、**ライセンスをクリアしているもの**を商品（ペルソナ出品）として登録する。出品者はリポジトリのオーナー名で作成する。

## 1. 対象データ（実測）

- 正本: `social-media-operations` の `data/github/processed/catalog.jsonl`（1 Skill = 1 行）＋ `data/github/README.md`（棚の一覧）
- 本文: `data/github/raw/<retrieved_at>/<id>-<カテゴリ名>/<owner>/<repo>/<sha>/<skill_path>`（不変・追記のみ）
- ライセンス判定はカタログの `license_status` のみを使う（`publication_status` は承認フロー用で使わない）。

| `license_status` | 件数 | 扱い |
|---|---|---|
| `verified` + MIT | 57 | **登録対象** |
| `verified` + Apache-2.0 | 3 | **登録対象** |
| `ambiguous`（`NOASSERTION` 含む） | 19 | 対象外（`private/skills/` 扱い・再配布禁止） |
| `missing` | 7 | 対象外 |

**登録対象 = 60 件、リポジトリオーナー = 23 名**（`addyosmani` 25 件、`openclaw` 6 件、`morluto` 5 件、`DietrichGebert` 4 件、他 19 名各 1〜2 件）。

対象外の例（混入防止）: `anthropics/skills` 系（ambiguous/missing）、`money-outreach` 系（NOASSERTION）、`follow-builders`（missing）、`deep-research`（missing）、`clippy`（missing）。

## 2. ライセンス判断（根拠）

- `license_spdx` は GitHub API 由来で `repos.jsonl` にも記録されている（例: `morluto/rea` → `license_key: mit` / `MIT License`）。
- README の扱いに従う: `verified` は棚に置ける。ただし**再配布（商品としての提供）の可否は別途確認**が必要で、MIT / Apache-2.0 とも**帰属表示が条件**になる。
- LICENSE 全文は取得していないため、次の**帰属ブロックを各商品の説明文に必須記載**とする（© はリポジトリオーナー名で表記）:

```
出典: <repo_url>（コミット <commit_sha> 時点の SKILL.md 全文）
ライセンス: <MIT License / Apache License 2.0>（カタログ判定: verified）
取得: <retrieved_at> / SHA256: <sha256>（登録時に照合）
```

- 本文（`skill_markdown`）は**原文のまま**（改変なし＝ Apache-2.0 の変更表示が不要な状態に保つ）。
- `validation_warnings: ["license_scope_repo"]` は「リポジトリ単位の判定」である旨の注意として受け止め、ファイル単位の例外は本文の目視（T4 の抜き打ち確認）で担保する。

## 3. 出品者（ユーザー）の作成方針

- **リポジトリオーナー名で1ユーザーずつ作成**（23 名）。例: `DietrichGebert`、`addyosmani`、`openclaw`。
- `username` は小文字の `[a-z0-9_]` に正規化（3〜20 文字、`_user` 補完ルールは既存の import 仕様に従う）。
- メールアドレスは **README の「連絡先」欄を使わない**（個人のメールアドレス等の PII を含むため）。代わりに合成アドレス `<owner-slug>@agentbank.dev` を使う。
- 経路は Issue #135 の `import:users`（`db/import/` に今回用の CSV を置く。既存サンプルは上書きしない）。
- `given_name` / `family_name` はオーナー名、`display_name` はオーナー名、`locale: ja`、`is_admin: false`、`password` は空欄（ランダム生成）。

## 4. 商品（Listing）の登録方針

- 経路は Issue #135 の `import:listings`。冪等キー `(title, author_id)`、`ON_CONFLICT=skip`、**既定ドライラン → `COMMIT=1`** の順で流す。
- 固定値: `price_cents=1000`、`currency=JPY`、`open=true`、`listing_shape_id=14`（既存ペルソナ出品と同じ）。
- `title`: 「<和名> — <機能>」形式（例: 既存の「さくら — ライティングアシスタント」に倣う）。60 件分は実装時に catalog の `name` / `description` から日本語化する。
- `description`: 日本語 1〜2 行の商品説明 ＋ §2 の帰属ブロック（必須）。
- `skill_markdown`: **raw の SKILL.md 全文**（sha256 照合済みのもの）。
- `author_email`: §3 で作ったオーナーユーザーの合成アドレス。
- `category`: 次表の agent-bank カテゴリ（DB 実測の `url` を使う）。

### カテゴリマッピング（実装時の既定値）

| 調達側の分類 | agent-bank の `category.url`（表示名） |
|---|---|
| 24 ライティング | `category1`（ライティングアシスタント） |
| 25 コード | `category2`（コードアシスタント） |
| 翻訳 | `fan-yi`（翻訳） |
| 要約 | `category4`（要約） |
| 画像 | `hua-xiang-sheng-cheng`（画像生成。絵寄りなら `category9` アート・イラスト） |
| データ分析 | `detafen-xi1`（データ分析。調査寄りなら `category17` リサーチアシスタント） |
| リサーチ / リサーチA | `risati`（リサーチ） |
| メール | `category19`（メール文面作成） |
| 会議メモ | `category20`（会議メモ） |
| マーケ | `maketeingu`（マーケティング） |
| デザイン | `dezain`（デザイン） |
| 教育 | `jiao-yu-xue-xi`（教育・学習） |
| 未設定（旧 52 行） | skill ごとに上表から判断。迷うものは `sheng-cheng-ai`（生成AI）に寄せず、実装時に owner へ確認リストとして出す |

※ `default-category`（デフォルトカテゴリ）は使わない（システム用）。

## 5. 手順

1. **T1: 突合せスクリプト** — `catalog.jsonl` の verified 60 件について、raw ファイルの存在＋ `sha256` 照合を行い、不一致・欠落があればその skill を除外リストに入れる（登録しない）。
2. **T2: `db/import/seed_github_users_*.csv`** — 23 オーナー分を作成。ドライランで件数確認 → `COMMIT=1`。
> **タイトル方針（Issue #137 で変更）**: 当初は「和名 — 機能」形式で作成したが、カード・ページ
> タイトルとして冗長なため **機能名のみ** に統一した（例: `しんだん — SEOサイト監査` →
> `SEOサイト監査`）。既存データは `lamprey:normalize_listing_titles` で正規化する。
> ジェネレータ（`script/generate_github_seed_csvs.py`）と CSV も同じ形式。

3. **T3: `db/import/seed_github_listings_*.csv`** — 60 件分を作成（タイトル・説明の日本語化を含む）。ドライラン → `COMMIT=1` → 再実行で全件 skip（冪等確認）。
4. **T4: 検証** — `/ja/browse` に 60 件が並ぶこと、抜き打ち 3 件で DB の `skill_markdown` が原文と一致すること、`open=true` / `price_cents=1000` / 著者がオーナーユーザーであること。
5. **T5: 報告** — 登録件数・除外件数と理由・帰属ブロックの記載例を Issue（新規に起票）に記録する。

## 6. 検証の受入条件

- [ ] sha256 照合で 60/60 が一致（不一致は除外＋理由記録）
- [ ] users: 23 件作成、2回目は全件 skip
- [ ] listings: 60 件作成、2回目は全件 skip
- [ ] `/ja/browse` に 60 件が表示される
- [ ] 抜き打ち 3 件で `skill_markdown` が原文と一致、`description` に帰属ブロックあり
- [ ] ambiguous / missing の skill が 1 件も登録されていない（タイトル一覧で確認）

## 7. リスクとスコープ外

- MIT の © 表示はリポジトリオーナー名での表記に留める（LICENSE 全文の埋め込みはしない）。より厳密な対応が必要になれば、LICENSE 取得を別タスク化する。
- `skill_markdown` が長いファイルはチャットの system prompt としてそのまま渡る（現行仕様）。トークン上限の扱いは既存のクリップ処理（#104）に任せ、今回の計画では変えない。
- 出品画像は付けない（`product-link` はカテゴリのデフォルト絵に落ちる既存仕様）。
- 価格は一律 1000（既存ペルソナと同一）。個別の値付けは本計画の対象外。
- social-media-operations 側のリポジトリには**一切書き込まない**（読み取りのみ）。
- 本番への反映は本計画の対象外。開発で検証後、デプロイは別途判断する。
