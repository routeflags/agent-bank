# 楽市楽間 UI 改善 設計書 — DESIGN.md 準拠フェーズ2

- **作成日**: 2026-10-06
- **根拠**: `DESIGN.md`（UI Design Specification）/ 2026-10-06 実施の画面レビュー結果
- **対象リポジトリ**: routeflags/agent-bank（branch `feat/agent-bank`）
- **ステータス**: 承認待ち（実装着手前の設計）

---

## 1. 目的と背景

2026-10-06 に `DESIGN.md` と全主要画面（12画面）を照合するレビューを実施した。
その結果、以下の未準拠項目が検出された。本書は各是正項目の**実装設計**を定義し、
画面追加・改修時に一貫したダークプレミアムUIへ収束させるための計画である。

**レビュー検出の主な未準拠（本設計の対象）**:

| # | 検出内容 | 該当DESIGN.md条項 | 優先度 |
|---|----------|-------------------|--------|
| A | Global Header に compact search がない | §7 / §11 | HIGH |
| B | 設定画面がライトテーマのまま | §2 / §4 | HIGH |
| C | 出品管理・旧browse系がライトテーマのまま | §2 / §4 | HIGH |
| D | プロフィールのデッドリンク（`href="#"`）と偽トレンド表示 | §16 / §25.10 | MEDIUM |
| E | トップに Marketplace metrics セクションがない | §12 | MEDIUM |
| F | 絵文字アイコン / Gold hex散在 / カード角丸12px | §18 / §24 / §20 | LOW |

**対応済み（本書のスコープ外・完了）**: Primary CTA の赤→Gold 統一、
`:focus-visible` アウトライン追加（commit `aaca6d2e4`）。

---

## 2. スコープ / 非スコープ

### スコープ
- 上記 A〜F の是正実装
- 既存レガシー（Sharetribe core）スタイルのダークテーマ上書き拡張
- 回帰検証（axe / hover監査 / E2E）の維持・拡張

### 非スコープ
- チャット画面（§13〜15）の再設計 — 開発DBに会話データがなく検証不能なため
  データ用意後に別途レビューする
- Reactコンポーネント（topbar_v1 有効時）の変更 — 本環境では無効
- 管理画面（admin2）のデザイン刷新 — 別基準で管理
- 色値そのものの変更 — DESIGN.md §4/§25.10 により**既存トークンが正**

---

## 3. Design Token 方針

実装は色の直接記述を避け、既存トークン（`app/assets/stylesheets/themes/_dark_variables.scss`）を
唯一の真実とする。DESIGN.md §4 の近似値と実装トークンの対応は以下の通り。

| DESIGN.md トークン | 実装トークン | 実値 | 用途 |
|--------------------|------------------|------|------|
| `--color-bg` | `--bg-primary` | `#1a1a1a` | ページ背景 |
| `--color-bg-elevated` | `--bg-secondary` | `#1e1e1e` | ヘッダー/フッター |
| `--color-surface` | `--bg-card` | `#242424` | カード/パネル |
| `--color-surface-hover` | `--bg-card-hover` | `#2a2a2a` | カードhover |
| `--color-border` | `--border-color` | `#333333` | 枠線 |
| `--color-text-primary` | `--text-primary` | `#ffffff` | 主情報 |
| `--color-text-secondary` | `--text-secondary` | `#999999` | 補助情報 |
| `--color-text-muted` | `--text-muted` | `#909090` | メタデータ |
| `--color-brand-gold` | `--accent-gold` | `#d4a853` | CTA/選択/評価 |
| `--color-brand-gold-light` | `--accent-gold-hover` | `#c09840` | Gold hover |
| `--color-brand-red` | `--accent-red` | `#c41e3a` | Battle/破壊的操作限定 |

**追加すべき新トークン（本書で新設）**:

``` css
/* header search 専用（§11: light surface + dark text） */
--color-search-surface: #f5f5f5;   /* 実装時、既存検索入力の実測値を優先 */
--color-search-text:    #333333;

/* radius 補正（§20: Card 6–10px） */
--radius-card: 8px;   /* 既存 --radius-md に統合してよい */
```

---

## 4. 画面別設計

### 4.1 Global Header compact search（P1 / 項目A）

**目的**: §7 のヘッダー構成（Logo / Primary Nav / **Search** / Utility / User）と
§11「通常画面ではGlobal Header内のcompact searchに縮小」を満たす。

**配置**:

``` text
┌──────────────────────────────────────────────────────────────┐
│ Logo │ PrimaryNav(サブナビ)     [ Search__________ 🔍 ] │ User │
└──────────────────────────────────────────────────────────────┘
```

- 追加位置: `app/views/layouts/_global_header.haml` の `.header-wrapper` 内、
  ユーザーエリア（`.header-right`）の直前
- マークアップ: 独立した GET フォーム（トップの `#homepage-filters` とは別物。
  §11 は「通常画面」を対象とするためトップページでは非表示でよい）

``` haml
.header-search
  = form_tag landing_page_path, method: :get, class: "header-search__form" do
    = text_field_tag :q, params[:q], class: "header-search__input",
      placeholder: t("homepage.index.what_do_you_need"), aria: { label: "検索" }
    = button_tag type: :submit, class: "header-search__button", aria: { label: "検索する" } do
      🔍
```

**動作**:
- 送信先: `/`（`homepage#index`）。キーワード `q` は既存Hero検索と同じ
  パラメータ（`app/views/homepage/index.haml:40` の `name="q"` と同一）を
  使用するため、検索ロジックの変更は不要
- 送信後はトップの検索結果へ遷移（Hero検索と同じ結果状態になる）
- `params[:q]` を初期値に再表示

**スタイル**（`themes/_dark_header.scss` に追加）:

``` scss
.header-search { margin-left: 16px; flex: 0 1 320px; min-width: 180px; }
.header-search__input {
  width: 100%;
  background: var(--color-search-surface);  /* light surface */
  color: var(--color-search-text);          /* dark text（§11） */
  border: 1px solid var(--border-color);
  border-radius: var(--radius-sm);
  padding: 8px 12px;
  font-size: 14px;
}
.header-search__button {
  background: var(--accent-gold);
  color: #1a1a1a;                           /* §10 Primary = Gold + dark text */
  border: none;
  border-radius: var(--radius-sm);
  padding: 8px 12px;
  cursor: pointer;
  &:hover { background: var(--accent-gold-hover); }
}
```

**レスポンシブ**:
- `≤768px`: `.header-search` を非表示（ヒーロー検索が主導線のため。
  §21「装飾は最初に削除」ではなく主導線を優先し、検索は
  モバイルでは引き続きHero/絞り込みを使う）
- ヒットエリア: 入力・ボタンとも高さ 38px 以上を確保（§22 の 44px 目標に対し
  ボタンは padding で調整）

**影響ファイル**:
- `app/views/layouts/_global_header.haml`（マークアップ追加）
- `app/assets/stylesheets/themes/_dark_header.scss`（スタイル）
- `config/locales/ja.yml`（placeholder が未定義なら追加）

**受け入れ基準**:
- 全ページのヘッダーに検索が表示され、`?q=生成AI` 相当の結果がHero検索と一致する
- hover コントラスト 4.5:1 以上（gold ボタンは dark text で 7.9:1 相当）
- axe / hover監査 / E2E がグリーンを維持（E2E に TC「ヘッダー検索→結果」を1件追加）

---

### 4.2 設定画面のダークテーマ化（P1 / 項目B）

**対象**: `settings#show` 系
- `app/views/settings/show.haml`
- `app/views/settings/account.haml`
- `app/views/settings/notifications.haml`
- `app/views/settings/transactions.haml`
- `app/views/settings/listings.haml`
- `app/views/settings/_notification_checkbox.haml` ほか部分テンプレート

**方針**: テンプレートは変更せず、**ダークテーマのCSS上書きを拡張**する
（レガシー構造への侵入を最小化する既存方針 `themes/_dark_*.scss` に従う）。

**新設**: `themes/_dark_settings.scss`（`require_tree ./themes` 自動読込）

``` scss
body.dark-theme {
  /* ページ土台（レガシーの白背景を全面的に暗転） */
  .settings,
  .settings-section,
  .custom-field,
  .notification-checkbox { /* 実クラスは実装時に DevTools で確定 */ }

  /* フォームコントロールは _dark_variables の Forms 上書きで概ね充足。
     追加が必要なレガシー固有部品のみ本ファイルに書く */
}
```

**実装手順**:
1. `/ja/:username/settings` を開き、ライト背景が出る要素を DevTools で列挙
   （背景・罫線・hover・disabled・エラー表示の5状態）
2. 各要素に `--bg-*` / `--text-*` / `--border-color` を適用
3. ラジオ/チェックボックスは既存 `accent-color: var(--accent-gold)` を再確認
4. フォーカス表示は §22 の `:focus-visible`（4.1/`_dark_variables.scss` 追加済み）を確認

**受け入れ基準**:
- 設定全サブ画面で `#e8e8e8` / `#ffffff` の面が残らない（検索: スクリーンショット +
  `getComputedStyle` の背景色走査スクリプト）
- 入力のテキスト/背景コントラスト 4.5:1 以上
- hover監査に「設定（ログイン中）」状態を1つ追加し0違反

---

### 4.3 出品管理・旧browse画面のダークテーマ化（P1 / 項目C）

**対象**:
- ユーザーメニュー「出品を管理する」→ `/ja/:username?show_closed=true`
  （`people#show` の show_closed 変種。raku-mypage 本体は既にダーク）
- 旧 Sharetribe 絞り込み付き出品一覧（`listings#browse` /
  `GET /ja/listings/browse`、レガシーのライトなフィルタサイドバーを含む）

**方針**: 4.2 と同じく CSS 上書きで暗転。新設 `themes/_dark_browse.scss` または
`_dark_settings.scss` に統合（部品が共通なら1ファイルに集約する）。

**対象部品（レビュー時の観測値）**:
- 絞り込み/検索サイドバーのライトパネル（`#e8e8e8` 相当）→ `--bg-card`
- セクション見出し・項目ホバー → `--text-*` / `--bg-card-hover`
- 出品行のカード化は既存 `_dark_cards.scss` の適用漏れを優先して拡張

**受け入れ基準**:
- 出品管理・browse 両画面でライト面ゼロ
- 出品行のタイトル/メタ情報コントラスト 4.5:1 以上
- axe 対象ページに両画面を追加し0違反

---

### 4.4 プロフィール修正（P2 / 項目D）

**対象**: `app/views/people/show.haml`（raku-mypage ダッシュボード）

**修正1 — デッドリンク解消**:

| 現状 | 修正 |
|------|------|
| 出品管理 `href: "#"` | `person_listings_path` 相当の実在URL（メニューの出品管理リンクと同一） |
| 売上確認 `href: "#"` | ページ未実装のため**非表示**（`- if` を外すのではなく nav 項目ごと条件分離） |
| 分析レポート `href: "#"` | 同上（未実装のため非表示） |
| お知らせ `href: "#"` | 同上（バッジ`0`も併せて非表示） |

方針: 未実装機能へのリンクを置かない（§25.10「不明な値を推測して固定しない」の
精神）。実装時に同じテンプレートへ戻す。

**修正2 — 偽トレンドの削除**:
- `.raku-summary__trend` の `↑ +12.5% 前月比` 等はハードコード値。
  値が 0（＝実データ未連携）のとき表示しない

``` haml
- if summary_value.to_i > 0
  .raku-summary__trend.raku-summary__trend--up ↑ +X% 前月比
```

- 将来、コントローラで前月比を算出して注入する（本設計では表示制御のみ。
  集計ロジックは 4.5 の metrics 設計と統合して行う）

**修正3 — 統計値の実データ化（最小限）**:
- 「出品数」は既に `@service.listings.total_entries` を使用 ✓
- 「利用数/フォロワー/販売件数」は現状ハードコード `0`。
  実データが取れる項目（`listings.total_sold` の合計等）のみ差し替え、
  取れない項目は **表示しない**（0の見せかけを避ける）

**受け入れ基準**:
- `href="#"` が raku-mypage 内に0件
- 値0のKPIに増減率が表示されない
- ダッシュボードの数字がDB集計と一致（手動照合）

---

### 4.5 トップページ Marketplace metrics（P2 / 項目E）

**目的**: §12 の構成（Hero → **Marketplace metrics** → Categories → Featured → Trust）の
metrics セクションを追加する。

**位置**: Hero セクション直後、新着/高評価タブ（フィード）の直前。

**表示項目とデータソース**（すべて `Listing.currently_open` ベースで集計）:

| 表示 | クエリ概要 | 例 |
|------|-----------|----|
| 登録ペルソナ数 | `Listing.currently_open.count` | 128 |
| 総利用回数 | `Listing.currently_open.sum(:times_viewed)` | 12,480 |
| 総販売数 | `Listing.currently_open.sum(:total_sold)` | 3,210 |
| 平均評価 | `Listing.currently_open.where("avg_rating > 0").average(:avg_rating)` | 4.3 |

- キャンバス無し・カード4枚横並び（`_raku_utils.scss` 系クラスを流用、
  新規コンポーネント禁止 §25.2 — 既存 `.raku-summary__item` パターンを流用）
- 数値は White primary、単位・ラベルは muted（§16 KPI 方針と同一）
- Gold は「平均評価」の★等の重要な数値箇所のみ（§4 Gold usage）
- ローディング/空/エラー状態（§23 LoadingState/EmptyState/ErrorState）を併せて定義

**実装位置**:
- マークアップ: `app/views/homepage/index.haml`（Hero の後ろに
  `.raku-metrics` セクション）
- 集計: `HomepageController#index` で `@marketplace_metrics` をハッシュ生成
  （N+1 防止のため単一SQLの集計を優先。カウント系4クエリまで）
- スタイル: `components/_raku_pages.scss` に追記（新ファイル不要）

**受け入れ基準**:
- 4指標が実DB集計と一致
- 表示コントラスト 4.5:1 以上、数値は 24px 以上の Large text
- axe / hover監査 / E2E グリーン維持

---

### 4.6 低優先度（P3 / 項目F）

| 項目 | 設計方針 |
|------|----------|
| 絵文字アイコン → outlineアイコン（§18） | フェーズ分割で実施。既存の `icon_map_tag` / font-awesome を優先して流用し、絵文字を段階的に置換。ナビ（🔍📦🏆⚔️📚）→ サイドバー → クイックアクションの順。**stroke/色は `--text-secondary` / `--accent-gold` のみ** |
| Gold hex 散在（§24） | `_raku_utils.scss` 等の直接hex（`#d4a843` 等8箇所）を `var(--accent-gold*)` へ一括置換。**値は変えず参照だけトークン化** |
| カード角丸 12px → 6–10px（§20） | `--radius-lg: 12px` をカード用途でのみ `--radius-md: 8px` に変更（`_monthly_summary` / `_category_grid` / `_skill_table` / `_quick_actions` / `_stats_bar` / `_review_list`）。ヒーロー等の装飾用途（`--radius-xl`）は変更しない |

---

## 5. 実装フェーズ計画

| フェーズ | 内容 | 依存 | 想定diff規模 |
|----------|------|------|--------------|
| P1-a | 4.1 ヘッダー検索 | なし | 小（2ファイル+TC1件） |
| P1-b | 4.2 設定画面ダーク化 | なし | 中（新規scss 1 + 監査状態追加） |
| P1-c | 4.3 出品管理/ browse ダーク化 | P1-b（部品共通化の判断を先に） | 中 |
| P2-a | 4.4 プロフィール修正 | なし | 小 |
| P2-b | 4.5 metrics セクション | なし | 中（controller + view + scss + TC） |
| P3 | 4.6 低優先度3点 | P1/P2 完了後 | 小×3 |

- 各フェーズは**独立してコミット**し、コミットごとに§6の検証を通す
- P1-a と P1-b は並行着手可。P1-c は P1-b の部品調査結果を受けて開始

---

## 6. 検証基準（各フェーズ共通）

```bash
# 1. hover コントラスト（対象状態を追加した場合は件数確認）
AUDIT_TOKEN=<token> node scripts/a11y_hover_audit.js     # → 0 failures

# 2. axe（対象ページを scripts/a11y_audit.js の PAGES に追加）
AUDIT_TOKEN=<token> node scripts/a11y_audit.js           # → 全ページ0 violations

# 3. E2E
AUDIT_TOKEN=<token> node spec/e2e/navigation_spec.js     # → 全件合格 + 追加TC

# 4. スタイル回帰の目視（スクリーンショット）
#    修正対象画面を1440px / 375px で撮影し、ライト面ゼロ・Gold限定運用を確認
```

- コントラストの合否は既存ホバー監査の判定ロジック（祖先背景合成＋WCAG比、
  4.5:1 / Large 3:1）に従う
- 追加したUIのキーボード操作（Tab移動→`:focus-visible` 表示）を1画面ずつ手動確認

---

## 7. リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| レガシーCSSの詳細度勝負でダーク上書きが効かない | ライト面残留 | `body.dark-theme` スコープ＋必要なら既存パッチ同様 `!important`（`_raku_utils.scss` の先例に倣い、適用箇所にコメントで理由を明記） |
| SCSS編集での括弧不一致→全ページ500 | ブロッキング | 変更後に `python3` での括弧バランス確認＋`curl` で200確認をコミット前必須手順に（2026-10-06 に発生済みの事故例あり） |
| ヘッダー検索追加でのレイアウト崩れ | 全ページ | `.header-wrapper` は flex。`min-width` 付き `flex: 0 1 320px` で縮退。768px以下は非表示 |
| metrics集計のパフォーマンス | トップ表示 | カウント4本までの集計に限定し、必要ならキャッシュ（既存 fragment cache を流用） |
| E2E/監査の見逃し回帰 | 品質 | 各フェーズで§6を必須ゲートに。監査スクリプトの状態追加を「修正の一部」として同じPRに含める |

---

## 8. 準拠トレーサビリティ（条項対応表）

| DESIGN.md 条項 | 本書の対応 |
|----------------|------------|
| §2 Dark Premium | 4.2 / 4.3（ライト面の暗転） |
| §4 Color System / Gold・Red usage | 3（トークン対応表）/ 4.1（検索CTA）/ 対応済み commit `aaca6d2e4` |
| §7 Global Header | 4.1 |
| §10 Buttons | 対応済み `aaca6d2e4` + 4.1（検索ボタン） |
| §11 Search | 4.1 |
| §12 Marketplace Home | 4.5 |
| §16 My Page / Dashboard | 4.4 |
| §18 Iconography | 4.6（フェーズ分割） |
| §20 Border / Radius | 4.6 |
| §22 Accessibility | 6（検証基準）+ 対応済み focus-visible |
| §24 Design Tokens | 3（新トークン定義）+ 4.6（hexトークン化） |
| §25 AI Agent Rules | 全設計で既存コンポーネント/トークンを優先する方針を明記 |

---

## 9. 未決事項（承認時に確認）

1. **ヘッダー検索のモバイル方針**: 非表示でよいか（本書案）、还是要はモバイルメニュー内に配置するか
2. **売上確認/分析レポート/お知らせ**: 非表示でよいか（本書案）、还是要は「準備中」ページを先に用意するか
3. **metrics のキャッシュ**: 即時集計でよいか、60秒程度のキャッシュを挟むか
4. **P3 の着手時期**: P1/P2 完了後でよいか、アイコン置換のみ先行するか
