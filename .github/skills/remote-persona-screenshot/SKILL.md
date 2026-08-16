---
name: remote-persona-screenshot
description: |
  Web ページのスクリーンショットを撮影するスキル。
  「スクリーンショット撮って」「画面キャプチャして」「プレビュー見せて」
  「各ページの状態を確認して」などの依頼で使う。
---

# スクリーンショット撮影スキル

Playwright を使って Web ページのスクリーンショットを撮影する。

## 基本方針

- 作業ディレクトリはプロジェクトルート
- 保存先は `screenshots/{YYYYMMDD}/`
- ファイル名は `{用途}_{ページ名}.png`
- 全ページ 200 OK であることを前提に撮影する

## 対象ページ一覧

| ページ | URL パターン | 備考 |
|--------|------------|------|
| トップページ | `/` | ダークテーマ、ヒーロー、統計、カテゴリ |
| 検索結果 | `/?q={キーワード}&view=grid` | キーワード検索 |
| カテゴリ表示 | `/?category={category}` | カテゴリフィルター |
| スキル詳細 | `/listings/{id}-{slug}` | タブ、評価、価格、CTA |
| チャット | ページ内の 💬 ボタン | 3カラム、履歴、設定 |
| マイページ | `/{username}` | サイドバー、プロフィール、サマリー |
| ログイン | `/login` | フォーム |
| サインアップ | `/signup` | フォーム |
| 管理画面 | `/admin2/` | ダッシュボード |

## 撮影フロー

### 1. 全ページ一括撮影（未ログイン）

```bash
# トップページ
curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/"

# スキル詳細
curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/listings/20-{slug}"

# 検索結果
curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/?q=AI&view=grid"
```

### 2. Playwright で撮影

```javascript
// トップページ（フルページ）
await page.goto('http://localhost:3000/');
await page.screenshot({ path: 'screenshots/{date}/top_hero.png', fullPage: true });

// スキル詳細
await page.goto('http://localhost:3000/listings/20-{slug}');
await page.screenshot({ path: 'screenshots/{date}/skill_detail.png', fullPage: true });

// チャット（トリガーボタンクリック後）
await page.click('button[aria-label="Open AI chat"]');
await page.waitForTimeout(2000);
await page.screenshot({ path: 'screenshots/{date}/chat_open.png' });
```

### 3. ログインが必要なページ

```javascript
// ログイン
await page.goto('http://localhost:3000/login');
await page.fill('#main_person_login', 'admin2@capafy.com');
await page.fill('#main_person_password', 'TestPassword1!');
await page.click('button:has-text("Log in")');
await page.waitForTimeout(2000);

// マイページ
await page.goto('http://localhost:3000/tailangtian');
await page.screenshot({ path: 'screenshots/{date}/mypage.png', fullPage: true });
```

## ファイル命名規則

| ページ | ファイル名 |
|--------|-----------|
| トップページ | `top_hero.png` |
| 検索結果 | `top_search.png` |
| カテゴリ表示 | `top_category.png` |
| スキル詳細 | `skill_detail.png` |
| チャットパネル | `chat_open.png` |
| チャット履歴 | `chat_history.png` |
| マイページ | `mypage.png` |
| ログイン | `login.png` |
| サインアップ | `signup.png` |

## 完了条件

- 全ページ 200 OK で表示されること
- スクリーンショットが `screenshots/{YYYYMMDD}/` に保存されること
- 各ページの主要コンポーネントが視覚的に確認できること
- エラーログに問題がないこと

## よくある問題

| 問題 | 原因 | 対処 |
|------|------|------|
| 500 エラー | マイグレーション未実行 | `bin/rails db:migrate` |
| 404 | ルート未設定 | `bin/rails routes` で確認 |
| ログインリダイレクト | セッション切れ | 再ログイン |
| 画像が表示されない | 画像未アップロード | デフォルト画像を設定 |
