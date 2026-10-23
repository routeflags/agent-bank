# Agent Guide — Lamprey（AI ペルソナマーケットプレイス）

> **対象言語: 日本語** — このプロダクトは日本市場向けにリリースされます。
> UI、ドキュメント、コミットメッセージ、コミュニケーションはすべて日本語をベースとします。

このリポジトリは [Sharetribe Go](https://github.com/sharetribe/sharetribe) のフォークです。
AI ペルソナのマーケットプレイスとして機能を拡張しています。

---

## プロジェクト概要

| 項目 | 値 |
|------|-----|
| プロジェクト名 | Lamprey（ランプリー） |
| ベース | Sharetribe Go (Ruby on Rails) |
| 目的 | AI ペルソナの販売・チャットプラットフォーム |
| ブランチ | `feat/agent-bank` |
| Ruby | 3.4.10 |
| Rails | 8.1.2 |
| React | 16.1.1（フック未対応 → クラスコンポーネント） |
| DB | MySQL |
| 開発環境 | Docker Compose（`docker-compose.dev.yml`） |

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│  フロントエンド                                    │
│  React 16.1 (クラスコンポーネント)                   │
│  Webpack → app-bundle.js                        │
├─────────────────────────────────────────────────┤
│  Rails (Sharetribe Go)                           │
│  ├─ App Controllers (Sharetribe コア)             │
│  ├─ API::V1 (チャット REST API)                   │
│  ├─ Action Cable (WebSocket / SSE)               │
│  └─ Services (Billing, AI, Persona)              │
├─────────────────────────────────────────────────┤
│  AI Providers                                   │
│  ├─ OpenAI (GPT-4o, GPT-4o-mini)                │
│  ├─ Anthropic (Claude Sonnet, Haiku)             │
│  └─ StreamingClient (Net::HTTP SSE)              │
├─────────────────────────────────────────────────┤
│  MySQL                                          │
│  ├─ Sharetribe Core Tables                      │
│  ├─ AI Tables (ai_providers, ai_models, etc.)   │
│  ├─ Chat Tables (chat_sessions, chat_messages)  │
│  └─ Billing (wallets, billing_agreements, etc.) │
└─────────────────────────────────────────────────┘
```

---

## ディレクトリ構成（重要箇所）

```
lamprey/
├── AGENTS.md                    # ← このファイル（エージェント起点）
├── app/
│   ├── models/
│   │   ├── ai_model.rb          # AI モデル定義
│   │   ├── ai_provider.rb       # AI プロバイダー（OpenAI, Anthropic）
│   │   ├── chat_session.rb      # チャットセッション
│   │   ├── chat_message.rb      # チャットメッセージ
│   │   ├── listing.rb           # 出品（ペルソナ）
│   │   ├── listing_ai_model.rb  # 出品 ↔ AI モデル関連
│   │   ├── wallet.rb            # ウォレット（決済）
│   │   ├── usage_record.rb      # 使用量記録
│   │   ├── billing_agreement.rb # 請求同意
│   │   ├── user_plan_subscription.rb  # プラン契約
│   │   └── person.rb            # ユーザー
│   ├── controllers/
│   │   └── api/
│   │       ├── api.rb           # module API（ Zeitwerk: API が正しい）
│   │       └── v1/
│   │           ├── v1.rb        # module API::V1
│   │           ├── chat_sessions_controller.rb
│   │           └── chat_stream_controller.rb
│   ├── channels/
│   │   └── persona_chat_channel.rb  # Action Cable チャネル
│   └── services/
│       ├── billing_service.rb
│       └── billing_config.rb
├── client/
│   └── app/
│       ├── startup/
│       │   ├── clientRegistration.js  # React コンポーネント登録
│       │   └── serverRegistration.js
│       └── components/
│           └── ChatPanel/
│               ├── ChatPanel.js      # チャットパネル（クラスコンポーネント）
│               ├── ChatHeader.js
│               ├── ChatMessage.js
│               ├── ChatInput.js
│               └── chatPanel.css
├── config/
│   ├── locales/
│   │   ├── ja.yml              # 日本語翻訳（メイン）
│   │   ├── admin2/ja.yml       # 管理画面日本語翻訳
│   │   ├── model/ja.yml        # モデル日本語翻訳
│   │   └── devise.ja.yml       # Devise 日本語翻訳
│   └── routes.rb
├── docker-compose.dev.yml      # 開発環境
└── Dockerfile.dev              # ruby:3.4.10-bookworm
```

---

## 開発環境

### 起動

```bash
# Docker 環境起動
docker compose -f docker-compose.dev.yml up -d

# サーバー確認
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/

# ログ確認
docker compose -f docker-compose.dev.yml logs web -f
```

### ログイン

| 項目 | 値 |
|------|-----|
| URL | `http://localhost:3000/login` |
| ユーザー名 | `admin2` |
| パスワード | `TestPassword1!` |

### Webpack（フロントエンドビルド）

```bash
# client ディレクトリで実行
cd client
npx webpack --mode=development --config webpack.client.config.js
```

### DB 操作

```bash
# Rails コンソール
docker compose -f docker-compose.dev.yml exec web bin/rails console

# マイグレーション
docker compose -f docker-compose.dev.yml exec web bin/rails db:migrate

# SQL 直接実行
docker compose -f docker-compose.dev.yml exec web bin/rails runner "puts ActiveRecord::Base.connection.tables.sort"
```

### ローカル開発環境（Docker 不要）

Docker は 1.5GB のメモリを消費するため、ローカル直接実行で開発可能。

**必要なツール:**

| ツール | バージョン | インストール方法 |
|--------|-----------|----------------|
| Ruby | 3.4.10 | `rbenv install 3.4.10` |
| MySQL | 8.x | `brew install mysql@8.4` |
| Redis | 7.x | `brew install redis` |
| Node.js | 18.16.0 | `nodenv install 18.16.0` |

**起動手順:**

```bash
# MySQL / Redis 起動
brew services start mysql@8.4
brew services start redis

# DB 作成
mysql -u root -e "CREATE DATABASE sharetribe_development CHARACTER SET utf8mb4;"
mysql -u root -e "CREATE USER 'sharetribe'@'localhost' IDENTIFIED BY 'secret';"
mysql -u root -e "GRANT ALL ON sharetribe_development.* TO 'sharetribe'@'localhost';"

# セットアップ
bin/rails db:migrate
bin/rails db:seed
cd client && npm install && cd ..
cd client && npx webpack --mode=development --config webpack.client.config.js

# サーバー起動
bin/rails server -b 0.0.0.0 -p 3000
```

**⚠️ ローカル環境の制約:**

| 項目 | ローカル | Docker |
|------|:-------:|:------:|
| **ThinkingSphinx** | ❌ 未インストール | ✅ |
| **Delayed::Job ワーカー** | ❌ 動作させない | ✅ |
| **PersonaExecutorJob** | 手動実行のみ | 自動キュー投入 |
| **Action Cable** | ✅ async | ✅ async |

> **重要**: ローカルでは Sphinx をインストールしない。ワーカー（Delayed::Job）も動作させない。
> ワーカーが必要なテスト（PersonaExecutorJob 等）は Docker 環境で実行すること。
> ローカルでは `rails runner` で直接 Job を実行してテストする。

---

## カスタムモデル一覧（Sharetribe コア以外）

### AI 関連

| テーブル | モデル | 説明 |
|---------|--------|------|
| `ai_providers` | `AiProvider` | OpenAI / Anthropic 等のプロバイダー |
| `ai_models` | `AiModel` | GPT-4o, Claude Sonnet 等のモデル定義 |
| `listing_ai_models` | `ListingAiModel` | 出品 ↔ AI モデルの多対多関連 |

### チャット関連

| テーブル | モデル | 説明 |
|---------|--------|------|
| `chat_sessions` | `ChatSession` | ユーザー ↔ ペルソナのチャットセッション |
| `chat_messages` | `ChatMessage` | チャットメッセージ（user/assistant/system） |

### 決済関連

| テーブル | モデル | 説明 |
|---------|--------|------|
| `wallets` | `Wallet` | ユーザーウォレット |
| `credit_transactions` | `CreditTransaction` | クレジット取引 |
| `billing_agreements` | `BillingAgreement` | 請求同意 |
| `usage_records` | `UsageRecord` | API 使用量記録 |
| `user_plan_subscriptions` | `UserPlanSubscription` | プラン契約 |
| `user_plan_subscription_transitions` | `UserPlanSubscriptionTransition` | プラン状態遷移 |

---

## API エンドポイント

### チャット REST API（認証必須）

| メソッド | パス | 説明 |
|---------|------|------|
| GET | `/api/v1/chat_sessions` | セッション一覧 |
| POST | `/api/v1/chat_sessions` | セッション作成 |
| GET | `/api/v1/chat_sessions/:id` | セッション詳細 |
| PATCH | `/api/v1/chat_sessions/:id` | セッション更新 |
| GET | `/api/v1/chat_sessions/:id/stream` | SSE ストリーミング |

### Action Cable（WebSocket）

| パス | 説明 |
|------|------|
| `/cable` | Action Cable エンドポイント |
| `PersonaChatChannel` | チャットチャネル |

---

## React コンポーネント（重要制約）

**React 16.1.1 はフックに対応していません。すべてクラスコンポーネントで実装してください。**

```jsx
// OK: クラスコンポーネント
class ChatPanel extends React.Component {
  constructor(props) {
    super(props);
    this.state = { messages: [] };
  }
  render() { return <div>...</div>; }
}

// NG: フック（React 16.1.1 では動かない）
function ChatPanel() {
  const [messages, setMessages] = useState([]);
}
```

- CSS モジュールインポート: `import './chatPanel.css'`
- 登録: `client/startup/clientRegistration.js` で `ReactOnRails.register()`

---

## エージェント一覧

このプロジェクトでは以下のエージェントが利用可能です。

| エージェント | 役割 |
|------------|------|
| **Product Manager** | タスク分解、計画書作成、実装依頼 |
| **Plan Architect** | 計画のコードベース照合、重複防止 |
| **Implementer** | コード実装（リーダブルコード原則） |
| **Markup Engineer** | SCSS/CSS、Twig テンプレート |
| **Web Designer** | ビジュアルデザイン、Figma |
| **Web Writer** | 記事作成、商品説明文 |
| **Web Director** | 制作進行管理 |
| **QA** | 品質検証 |
| **Reviewer** | コードレビュー |
| **Debugger** | デバッグ、エラー調査 |
| **Super Hacker** | トラブルシューティング |
| **Researcher** | 技術調査 |
| **Growth Marketer** | SEO、広告運用 |
| **CFO** | 財務分析 |
| **Secretary** | 経営補佐 |

---

## コーディング規約

### バックエンド（Ruby / Rails）

- **名前空間**: `Eccube\` → `src/Eccube/`（コア）、`Customize\` → `app/Customize/`、`Plugin\` → `app/Plugin/`
- **クラス名**: PascalCase（例: `ProductController`）
- **メソッド名**: camelCase（例: `getQueryBuilderBySearchData`）
- **コアファイルの直接編集は禁止**: `src/Eccube/` は触らない。`app/Customize/` でカスタマイズ
- **API コントローラのモジュール名**: `API`（`Api` ではない — `inflect.acronym 'API'`）
- **ライセンスヘッダ**: 新規ファイルには EC-CUBE 標準のライセンスブロックを付与

### フロントエンド（SCSS / React）

- **SCSS 変数優先**: マジックナンバー禁止
- **BEM 命名**: `.block__element--modifier`
- **ネストは 3 段階まで**
- **React はクラスコンポーネントのみ**（React 16.1.1 フック未対応）
- **Bootstrap 5 を活用**

### テスト

- **単体テスト (Unit)**: `spec/models/`, `spec/services/`
- **統合テスト (Integration)**: DAMA DoctrineTestBundle
- **Web テスト (Functional)**: `AbstractWebTestCase` 継承
- **UI テスト**: `CommandTester`（コマンド）、Playwright（ブラウザ）

---

## 日本語化（Locales）

翻訳ファイルは以下の場所にあります。

| ファイル | 内容 | 行数 |
|---------|------|------|
| `config/locales/ja.yml` | メイン翻訳（共通、チャット、決済等） | 2,228 |
| `config/locales/admin2/ja.yml` | 管理画面翻訳 | 1,454 |
| `config/locales/model/ja.yml` | ActiveRecord モデル翻訳 | 25 |
| `config/locales/devise.ja.yml` | Devise 認証翻訳 | — |

- 日本語ロケールでアクセス: `http://localhost:3000/ja/`
- デフォルトルケール: `en`（日本語リリース前に `ja` に変更検討）

---

## データベース接続

```bash
# 本番 MySQL（SSH トンネル経由、ポート 3307）
mysql -h 127.0.0.1 -P 3307 -u xs044720_eccube -p'cbFVYc7hQcbFVY' xs044720_eccube4

# 開発 MySQL（SSH トンネル経由、ポート 3308）
mysql -h 127.0.0.1 -P 3308 -u xs990883_eccube -p'=[~-Pm|eZ+Jc' xs990883_dev

# トンネル起動
bash .github/bin/start_mysql_tunnel.sh
```

---

## 注意事項（このプロジェクト固有）

1. **React 16.1.1**: フック使えない。必ずクラスコンポーネント
2. **API モジュール名**: `Api` ではなく `API`（`inflect.acronym 'API'`）
3. **Docker ボリュームの遅延**: webpack のファイル変更が反映されないことがある。`rm -rf node_modules/.cache` + ファイルタッチ
4. **Sharetribe Auth**: Devise のモンキーパッチ。ログインは `emails` テーブル経由（LEFT JOIN）
5. **Person#name()**: 引数が必須（`community_or_display_type`）。`@person.name` はエラー
6. **category_id**: nil だと 500 エラー。デフォルト値 `|| 0` が必要
7. **Gemfile / Dockerfile**: Ruby 3.4.10 に固定。バージョン不一致でコンテナ起動失敗

---

## 最近の変更履歴

| コミット | 内容 |
|---------|------|
| `d06e851` | Phase 6 — AI ペルソナ検索拡張 |
| `078feb3` | Phase 5 — AI ペルソナチャット UI + API E2E テスト |
| `89c42a3` | Phase 4 — ペルソナ実装基盤 + SSE ストリーミング |
| `9bf3dc9` | Phase 3 レビュー指摘事項の修正 |
| `87abd81` | Phase 3 — SSE ストリーミング + Action Cable + チャット基盤 |
| `9b63b49` | Phase 2 — 決済（Wallet, Subscriptions, Usage Records） |
| `89b2696` | Phase 1 — ファウンデーション（AI Models, Persona Fields, OTP） |

---

## 実装フェーズ

| Phase | 内容 | 状態 |
|-------|------|------|
| 1 | ファウンデーション（AI モデル、ペルソナ、OTP） | ✅ 完了 |
| 2 | 決済（ウォレット、サブスクリプション、使用量記録） | ✅ 完了 |
| 3 | SSE ストリーミング + Action Cable + チャット基盤 | ✅ 完了 |
| 4 | ペルソナ実装基盤（AI プロバイダーアダプター） | ✅ 完了 |
| 5 | チャット UI + API E2E テスト | ✅ 完了 |
| 6 | 検索拡張（ペルソナフィルター） | ✅ 完了 |
| 7 | 日本語化 + UI/UX 改善 | 🔄 進行中 |
| 8 | 本番デプロイ | ⏳ 予定 |

---

## 最後に

この文書を読んだら、**環境を確認して、状態を報告してください**。

報告項目:
1. Docker 環境が起動しているか
2. DB 接続が可能か
3. ページ表示が正常か（`curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/`）
4. 最新のエラーログに問題がないか

---

# エージェント開発・運用ポリシー

## 1. 役割と責任

エージェントは、開発を委任されたディレクターとして、自律的に判断・実行・検証する。

- 不明確な要件は直ちにオーナーへ確認せず、既存の要件・設計・決定記録を参照して解決を試みる。
- 委譲された権限内で判断し、必要に応じてサブエージェントへ作業を委任する。
- 判断の根拠、仮定、不確実性を記録し、事実と区別する。

## 2. 意思決定プロセス

以下の順序で判断する。

1. **既存情報**：要件・設計・過去の決定を確認
2. **整合性**：プロジェクト・事業目標との整合を評価
3. **可逆性**：変更・撤回できるか評価
4. **コスト・リスク**：費用、副作用、影響範囲を評価
5. **権限判定**：権限内なら合理的な暫定判断
6. **記録**：判断根拠・仮定・影響範囲を記録
7. **実行・委任**：作業を実行またはサブエージェントへ委任

暫定判断は後から変更可能な状態を維持する。

## 3. 権限と承認

**自律実行可能：** 調査、設計、実装、テスト、可逆的変更、権限内のコミット・push、Issue管理。

**オーナー承認が必要：**

- 課金が発生しうる操作
- 外部送信・公開・本番環境への副作用
- 不可逆な操作
- 他リポジトリへの書き込みなど権限外の変更

承認待ちはIssueに記録し、実行コマンドと手順を準備する。承認済みと推定してはならない。

## 4. 開発・運用サイクル

1. Issueを確認し、優先度と依存関係を評価
2. 着手時に作業中ステータスを設定
3. 実行・委任し、成果物を受入基準で検証
4. 合格後、コミット・push・必要な報告を実施
5. 検証結果・実測値を記録してIssueを終了
6. 独立して実行可能なIssueがあれば継続
7. 実行可能なIssueがなければ停止

## 5. Issue管理

| 状態 | 運用 |
|------|------|
| 未着手 | 実行可能な作業を選定 |
| 作業中 | 進捗・担当・検証状況を管理 |
| 保留 | 残件・未確認事項・必要な承認・次の一手を記録 |
| 完了 | 受入結果と実測値を記録して終了 |

当該プロジェクトに作業がないIssueは、根拠を記録して終了してよい。ラベル名や管理コマンドは各プロジェクトの規約に従う。

## 6. 基本原則

- **自律性**：権限内の判断を不必要にエスカレーションしない。
- **権限遵守**：未承認の操作を実行しない。
- **事実と仮定の分離**：推測を確定事項として扱わない。
- **検証可能性**：完了判定には客観的な証拠を用いる。
- **継続と停止**：実行可能な作業がある限り継続し、なければ停止する。
