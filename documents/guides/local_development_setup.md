# ローカル開発環境セットアップ手順書

> **目的**: Docker に依存しないローカル開発環境を構築し、メモリ使用量を削減する
> **対象**: macOS (Apple Silicon / Intel)
> **作成日**: 2026-08-16

---

## 1. 現状の問題

| 項目 | Docker | ローカル（目標） |
|------|--------|:--------------:|
| メモリ使用量 | **1.5GB** | **~300MB** |
| 起動時間 | 30秒〜1分 | 5秒 |
| ビルド速度 | ボリューム遅延あり | 高速 |
| DB操作 | コンテナ経由 | 直接アクセス |

---

## 2. 必要なツール

| ツール | バージョン | インストール方法 |
|--------|-----------|----------------|
| Homebrew | 最新 | `brew update` |
| rbenv | 1.2.x | `brew install rbenv ruby-build` |
| Ruby | 3.4.10 | `rbenv install 3.4.10` |
| MySQL | 8.x | `brew install mysql` |
| Redis | 7.x | `brew install redis` |
| Node.js | 18.16.0 | `nodenv` or `nvm` |
| Yarn | 1.x | `brew install yarn` |
| ImageMagick | 最新 | `brew install imagemagick` |

---

## 3. セットアップ手順

### Step 1: Ruby インストール

```bash
# rbenv がなければインストール
brew install rbenv ruby-build

# rbenv を初期化
echo 'eval "$(rbenv init -)"' >> ~/.zshrc
source ~/.zshrc

# Ruby 3.4.10 をインストール
rbenv install 3.4.10
rbenv local 3.4.10

# 確認
ruby -v  # => ruby 3.4.10
```

### Step 2: MySQL インストール

```bash
brew install mysql@8.4
brew services start mysql@8.4

# データベース作成
mysql -u root -e "CREATE DATABASE sharetribe_development CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -e "CREATE USER 'sharetribe'@'localhost' IDENTIFIED BY 'secret';"
mysql -u root -e "GRANT ALL PRIVILEGES ON sharetribe_development.* TO 'sharetribe'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"
```

### Step 3: Redis インストール

```bash
brew install redis
brew services start redis

# 確認
redis-cli ping  # => PONG
```

### Step 4: Node.js インストール

```bash
# nodenv がなければインストール
brew install nodenv
nodenv init

# Node.js 18.16.0 をインストール
nodenv install 18.16.0
nodenv local 18.16.0

# 確認
node -v  # => v18.16.0
```

### Step 5: Bundle Install

```bash
cd /Users/bookair18/orca/workspaces/lamprey
bundle install
```

### Step 6: npm インストール

```bash
cd client
npm install
cd ..
```

### Step 7: DB 設定ファイル作成

```bash
cat > config/database.yml << 'EOF'
development:
  adapter: mysql2
  database: sharetribe_development
  encoding: utf8mb4
  collation: utf8mb4_unicode_ci
  username: sharetribe
  password: secret
  host: localhost
  port: 3306
  pool: 5
  timeout: 5000

test:
  adapter: mysql2
  database: sharetribe_test
  encoding: utf8mb4
  collation: utf8mb4_unicode_ci
  username: sharetribe
  password: secret
  host: localhost
  port: 3306
  pool: 5
  timeout: 5000
EOF
```

### Step 8: .env ファイル作成

```bash
cat > .env.local << 'EOF'
RAILS_ENV=development
SECRET_KEY_BASE=local_dev_secret_key_base
DATABASE_HOST=localhost
DATABASE_PORT=3306
DATABASE_NAME=sharetribe_development
DATABASE_USERNAME=sharetribe
DATABASE_PASSWORD=secret
REDIS_URL=redis://localhost:6379/0
EOF
```

### Step 9: DB セットアップ

```bash
# マイグレーション実行
bin/rails db:migrate

# シードデータ投入
bin/rails db:seed
```

### Step 10: Webpack ビルド

```bash
cd client
npx webpack --mode=development --config webpack.client.config.js
cd ..
```

### Step 11: Rails サーバー起動

```bash
bin/rails server -b 0.0.0.0 -p 3000
```

### Step 12: Action Cable ワーカー起動（別ターミナル）

```bash
bin/rails jobs:work
```

---

## 4. 確認コマンド

```bash
# サーバー起動確認
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/
# => 200

# DB 接続確認
bin/rails runner "puts ActiveRecord::Base.connection.tables.count"
# => 89

# Redis 接続確認
bin/rails runner "puts Redis.new.ping"
# => PONG
```

---

## 5. トラブルシューティング

| 問題 | 原因 | 対処 |
|------|------|------|
| `bundle install` でエラー | MySQL ヘッダーファイル不足 | `brew install mysql-client` |
| `mysql2` エラー | libmysqlclient | `brew link mysql-client --force` |
| Node.js バージョン不一致 | `.node-version` | `nodenv local 18.16.0` |
| ポート 3306 が使用中 | 別プロセス | `lsof -i :3306` で確認 |
| Redis 接続エラー | 未起動 | `brew services start redis` |
| Webpack ビルドエラー | node_modules 不整合 | `rm -rf node_modules && npm install` |

---

## 6. Docker との切り替え

### ローカル → Docker に戻す場合

```bash
# Docker 環境起動
docker compose -f docker-compose.dev.yml up -d

# .env ファイルを Docker 用に復元
cp .env .env.local.bak
```

### Docker → ローカルに戻す場合

```bash
# Docker 停止
docker compose -f docker-compose.dev.yml down

# .env ファイルをローカル用に切替
cp .env.local .env
```

---

## 7. 推奨ツール

| ツール | 用途 |
|--------|------|
| TablePlus | MySQL GUI クライアント |
| Postman | API テスト |
| iTerm2 | ターミナル（分割表示） |
| VSCode + Ruby LSP | エディタ |
