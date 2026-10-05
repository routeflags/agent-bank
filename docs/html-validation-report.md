# HTML バリデーションレポート

- **実施日時**: 2026-10-05 15:01:10 UTC
- **対象**: Agent Bank フロントエンド全ページ（日本語版 /ja）
- **ツール**: html-validate 11.16.2（`html-validate:recommended` + WCAG ルール等、`.htmlvalidate.json` 準拠）
- **対象ページ数**: 16（HTTP 200: 13 / 5xx エラー: 2 / リダイレクト: 1）
- **総計**: エラー 280 件 / 警告 23 件

## サマリ

| # | ページ | 認証 | HTTP | エラー | 警告 |
|---|--------|:----:|:----:|-------:|-----:|
| 1 | トップページ | - | 200 | 42 | 6 |
| 2 | ログイン | - | 200 | 22 | 0 |
| 3 | 新規登録 | - | 200 | 31 | 0 |
| 4 | パスワード再設定 | - | 200 | 24 | 2 |
| 5 | 購入者プロフィール | - | 200 | 15 | 3 |
| 6 | 出品者プロフィール | - | 500 | 0 | 0 |
| 7 | ペルソナ詳細（さくら — ライティングアシスタント） | - | 200 | 18 | 2 |
| 8 | ペルソナ詳細（コード太郎 — コード生成・レビュー） | - | 200 | 18 | 2 |
| 9 | ペルソナ詳細（みずたま — 日英翻訳） | - | 200 | 18 | 2 |
| 10 | ペルソナ詳細（はなこ — カスタマーサポート） | - | 200 | 18 | 2 |
| 11 | ペルソナ詳細（ゆき — ロールプレイ会話） | - | 200 | 18 | 2 |
| 12 | ペルソナ詳細（けんじ — データ分析） | - | 200 | 18 | 2 |
| 13 | メールボックス | あり | 200 | 17 | 0 |
| 14 | 設定 | あり | 302 | 0 | 0 |
| 15 | ペルソナ問い合わせフォーム | あり | 200 | 21 | 0 |
| 16 | 注文開始 | あり | 500 | 0 | 0 |

## ルール別集計（HTTP 200 ページ）

| ルール | エラー | 警告 |
|--------|-------:|-----:|
| `void-style` | 112 | 0 |
| `no-conditional-comment` | 104 | 0 |
| `wcag/h30` | 17 | 0 |
| `no-implicit-close` | 13 | 0 |
| `script-type` | 13 | 0 |
| `wcag/h37` | 12 | 0 |
| `autocomplete-password` | 3 | 0 |
| `element-permitted-content` | 2 | 0 |
| `no-dup-id` | 2 | 0 |
| `text-content` | 1 | 0 |
| `attribute-boolean-style` | 1 | 0 |
| `no-inline-style` | 0 | 15 |
| `no-trailing-whitespace` | 0 | 7 |
| `prefer-button` | 0 | 1 |

## ページ別 内訳（上位ルール）

### トップページ (`/`)

- `void-style`: エラー 18
- `no-conditional-comment`: エラー 8
- `wcag/h30`: エラー 6
- `wcag/h37`: エラー 6
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `element-permitted-content`: エラー 1
- `text-content`: エラー 1

### ログイン (`/ja/login`)

- `void-style`: エラー 10
- `no-conditional-comment`: エラー 8
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `attribute-boolean-style`: エラー 1
- `autocomplete-password`: エラー 1

### 新規登録 (`/ja/signup`)

- `void-style`: エラー 13
- `no-conditional-comment`: エラー 8
- `wcag/h30`: エラー 3
- `autocomplete-password`: エラー 2
- `no-dup-id`: エラー 2
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `element-permitted-content`: エラー 1

### パスワード再設定 (`/ja/people/password/new`)

- `void-style`: エラー 14
- `no-conditional-comment`: エラー 8
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `no-trailing-whitespace`: 警告 1
- `prefer-button`: 警告 1

### 購入者プロフィール (`/ja/gourutailangte`)

- `no-conditional-comment`: エラー 8
- `void-style`: エラー 5
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `no-inline-style`: 警告 3

### ペルソナ詳細（さくら — ライティングアシスタント） (`/ja/listings/14-sakura-raiteinguasisutanto`)

- `no-conditional-comment`: エラー 8
- `void-style`: エラー 6
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `wcag/h30`: エラー 1
- `wcag/h37`: エラー 1
- `no-inline-style`: 警告 1
- `no-trailing-whitespace`: 警告 1

### ペルソナ詳細（コード太郎 — コード生成・レビュー） (`/ja/listings/15-kodotai-lang-kodosheng-cheng-rebiyu`)

- `no-conditional-comment`: エラー 8
- `void-style`: エラー 6
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `wcag/h30`: エラー 1
- `wcag/h37`: エラー 1
- `no-inline-style`: 警告 1
- `no-trailing-whitespace`: 警告 1

### ペルソナ詳細（みずたま — 日英翻訳） (`/ja/listings/16-mizutama-ri-ying-fan-yi`)

- `no-conditional-comment`: エラー 8
- `void-style`: エラー 6
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `wcag/h30`: エラー 1
- `wcag/h37`: エラー 1
- `no-inline-style`: 警告 1
- `no-trailing-whitespace`: 警告 1

### ペルソナ詳細（はなこ — カスタマーサポート） (`/ja/listings/17-hanako-kasutamasapoto`)

- `no-conditional-comment`: エラー 8
- `void-style`: エラー 6
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `wcag/h30`: エラー 1
- `wcag/h37`: エラー 1
- `no-inline-style`: 警告 1
- `no-trailing-whitespace`: 警告 1

### ペルソナ詳細（ゆき — ロールプレイ会話） (`/ja/listings/18-yuki-rorupureihui-hua`)

- `no-conditional-comment`: エラー 8
- `void-style`: エラー 6
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `wcag/h30`: エラー 1
- `wcag/h37`: エラー 1
- `no-inline-style`: 警告 1
- `no-trailing-whitespace`: 警告 1

### ペルソナ詳細（けんじ — データ分析） (`/ja/listings/19-kenzi-detafen-xi`)

- `no-conditional-comment`: エラー 8
- `void-style`: エラー 6
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `wcag/h30`: エラー 1
- `wcag/h37`: エラー 1
- `no-inline-style`: 警告 1
- `no-trailing-whitespace`: 警告 1

### メールボックス (`/ja/gourutailangte/inbox`)

- `no-conditional-comment`: エラー 8
- `void-style`: エラー 6
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `wcag/h30`: エラー 1

### ペルソナ問い合わせフォーム (`/ja/listings/14-sakura-raiteinguasisutanto/contact`)

- `void-style`: エラー 10
- `no-conditional-comment`: エラー 8
- `no-implicit-close`: エラー 1
- `script-type`: エラー 1
- `wcag/h30`: エラー 1

## 検証不能ページ（5xx）

| ページ | パス | 原因 |
|--------|------|------|
| 出品者プロフィール | `/ja/alexm` | NoMethodError（プロフィール表示処理） |
| 注文開始 | `/ja/listings/14-sakura-raiteinguasisutanto/initiate` | `NoMethodError: undefined method '*' for nil` — `TransactionService::Order#item_total`（出品に価格が設定されていないため。ペルソナは price_enabled=false の shape で作成） |

## 既知のコメント

- HAML 由来の self-closing 要素（`<img/>` 等）が `void-style` 違反の主因。`html-validate --fix` でテンプレート側を一括修正可能
- `no-inline-style` 警告は raku デザインのインラインスタイル指定に由来（デザイン仕様上の意図的な指定を含む）
- 5xx ページはバリデーション対象外（エラーページ HTML のため）

## 再実行方法

```bash
bundle exec rails runner scripts/html_validation_report.rb
```
