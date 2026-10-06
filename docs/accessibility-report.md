# アクセシビリティ監査レポート（axe-core）

- **実施日時**: 2026/10/6 21:15:51
- **対象**: Agent Bank フロントエンド（日本語版 /ja）
- **ツール**: axe-core（@axe-core/playwright 11.x）+ Chromium（Playwright）
- **ルールセット**: wcag2a / wcag2aa / wcag21a / wcag21aa
- **対象ページ数**: 16
- **違反合計ノード数**: 0（なし）

## サマリ

| # | ページ | HTTP | 違反ルール数 | 違反ノード数 |
|---|--------|:----:|-------------:|-------------:|
| 1 | トップページ | 200 | 0 | 0 |
| 2 | ログイン | 200 | 0 | 0 |
| 3 | 新規登録 | 200 | 0 | 0 |
| 4 | パスワード再設定 | 200 | 0 | 0 |
| 5 | 購入者プロフィール | 200 | 0 | 0 |
| 6 | ペルソナ詳細（14） | 200 | 0 | 0 |
| 7 | ペルソナ詳細（15） | 200 | 0 | 0 |
| 8 | ペルソナ詳細（16） | 200 | 0 | 0 |
| 9 | ペルソナ詳細（17） | 200 | 0 | 0 |
| 10 | ペルソナ詳細（18） | 200 | 0 | 0 |
| 11 | ペルソナ詳細（19） | 200 | 0 | 0 |
| 12 | メールボックス | 200 | 0 | 0 |
| 13 | ペルソナ問い合わせフォーム | 200 | 0 | 0 |
| 14 | ペルソナランキング | 200 | 0 | 0 |
| 15 | ペルソナバトル | 200 | 0 | 0 |
| 16 | ドキュメント | 200 | 0 | 0 |

## 再実行方法

```bash
AUDIT_TOKEN=<buyer login token> node scripts/a11y_audit.js
```

---

## ホバーコントラスト監査（追補 2026-10-06 21:20）

- **ツール**: `scripts/a11y_hover_audit.js`（Playwright + 祖先背景合成による WCAG 比率計算）
- **状態数**: 8（前回6 + 出品フォーム + ログイン画面〔フラッシュ付き〕）
- **結果**: 違反 0 件

### 本次の是正内容

| 対象 | 状態 | 修正前 | 修正後 | 変更ファイル |
|------|------|--------|--------|--------------|
| 新規出品フォームのカテゴリ選択リンク | hover | #7cc3b6 on #e8e8e8 = 1.66:1 | #7cc3b6 on #242424 = 7.64:1 | `themes/_dark_variables.scss` |
| 同上（選択済み） | selected | #59b3a2 on #e8e8e8 = 2.06:1 | #59b3a2 on #242424 = 6.21:1 + gold枠 | 同上 |
| フラッシュ通知内のリンク | hover | #7cc3b6 on #e8e8e8 = 1.66:1 | #17554a on #e8e8e8 ≈ 7.0:1 + 下線 | `components/_raku_utils.scss` |
| ログイン/送信ボタン | hover | white on #3483de = 3.86:1 | white on #a81830 = 7.3:1 | 同上 |
| ランキングの出品者リンク | base | 色のみ（axe `link-in-text-block`） | 下線付き | `components/_raku_pages.scss` |

### 根本原因: 新規出品フォームの選択肢が表示されない問題

`homepage.js` が `relocate()` で `#header-menu-mobile-anchor` を移動先に
`#header-menu-desktop-anchor`（ラクヘッダーには存在しない）を指定していた。
デスクトップ幅では relocate() が移動先 undefined で例外を投げ、**jQuery 1.x の
ready キューがここで中断**するため、それ以降に登録されたハンドラ（新規出品
フォームのカテゴリ選択初期化を含む）が実行されず、全選択肢が `.hidden` の
まま表示されない状態だった。

**修正**: `#filters` と同じ存在チェックガードを追加。フォーム初期化が復旧し、
カテゴリ選択肢（9件）が正しく表示される。

### ナビゲーションのアクティブ状態

ランキング / バトル / ドキュメントはすべてトップへのプレースホルダー
リンクで、どのページでもアクティブにならなかった。それぞれ独立したページ
（`/ja/rankings`・`/ja/battles`・`/ja/docs`）を追加し、`raku_nav_active?`
ヘルパーで現在地に応じて `is-active` を付与するようにした。

### 再実行方法

```bash
AUDIT_TOKEN=<buyer login token> node scripts/a11y_hover_audit.js   # hover 8状態
AUDIT_TOKEN=<buyer login token> node scripts/a11y_audit.js          # axe 16ページ
AUDIT_TOKEN=<buyer login token> node spec/e2e/navigation_spec.js    # E2E 25件
```
