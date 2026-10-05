# ============================================================
# Sharetribe Go — Local Development Makefile
# ============================================================

SHELL        := /bin/zsh
.DEFAULT_GOAL := help
RUBY         := $(shell cat .ruby-version 2>/dev/null || echo "3.4.8")
NODE         := $(shell cat .node-version 2>/dev/null || echo "18.16.0")
DB_DEV       := sharetribe_development
DB_TEST      := sharetribe_test

# ── Colors ──────────────────────────────────────────────────
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RESET  := \033[0m

# ============================================================
#  Setup
# ============================================================

.PHONY: setup
setup: build-test-assets ## 全体セットアップ（gem + npm + DB 初期化 + アセットビルド）
	@echo "$(GREEN)▶ Ruby $(RUBY) / Node $(NODE) を確認中...$(RESET)"
	@bundle install
	@npm install
	@cd client && npm install --ignore-scripts
	@cp -n config/database.example.yml config/database.yml 2>/dev/null || true
	@cp -n config/config.example.yml   config/config.yml   2>/dev/null || true
	@bundle exec rake db:create db:schema:load
	@echo "$(GREEN)✔ セットアップ完了！$(RESET)"

.PHONY: build-test-assets
build-test-assets: ## テスト用アセットをビルド
	@echo "$(GREEN)▶ テスト用アセットをビルド中...$(RESET)"
	@cd client && npm run build:test
	@echo "$(GREEN)✔ アセットビルド完了！$(RESET)"

.PHONY: build-test-assets-stub
build-test-assets-stub: ## スタブファイルでテスト用アセットを作成（ビルド失敗時のフォールバック）
	@mkdir -p app/assets/webpack
	@touch app/assets/webpack/vendor-bundle.js
	@touch app/assets/webpack/app-bundle.js
	@touch app/assets/webpack/server-bundle.js
	@echo "$(GREEN)✔ スタブアセットを作成しました$(RESET)"

.PHONY: setup-db
setup-db: ## データベースだけ再作成
	@bundle exec rake db:drop db:create db:schema:load

.PHONY: migrate
migrate: ## マイグレーション実行
	@bundle exec rake db:migrate

# ============================================================
#  Server
# ============================================================

.PHONY: server
server: ## Puma で開発サーバー起動 (port 3000)
	@bundle exec rails server -p 3000

.PHONY: server-bg
server-bg: ## 開発サーバーをバックグラウンドで起動
	@bundle exec rails server -p 3000 -d
	@echo "$(GREEN)✔ サーバーをバックグラウンドで起動しました (port 3000)$(RESET)"

.PHONY: stop
stop: ## バックグラウンドサーバーを停止
	@-kill `cat tmp/pids/server.pid 2>/dev/null` 2>/dev/null && echo "$(GREEN)✔ サーバーを停止しました$(RESET)" || echo "$(YELLOW)⚠ サーバーは稼働していません$(RESET)"

.PHONY: foreman
foreman: ## foreman で Procfile.static を起動（フル開発環境）
	@foreman start -f Procfile.static

.PHONY: foreman-hot
foreman-hot: ## foreman で Procfile.hot を起動（ホットリロード付き）
	@foreman start -f Procfile.hot

.PHONY: client-assets
client-assets: ## クライアントアセットをビルド（ウォッチ付き）
	@script/export_routes_js.sh && cd client && npm run build:dev:client

.PHONY: server-assets
server-assets: ## サーバーアセットをビルド（ウォッチ付き）
	@script/export_translations.sh && script/wait_for_routes_js.sh && cd client && npm run build:dev:server

# ============================================================
#  Database
# ============================================================

.PHONY: seed
seed: ## シードデータ投入
	@bundle exec rake db:seed

.PHONY: reset-db
reset-db: ## DB リセット（drop + create + load + seed）
	@bundle exec rake db:drop db:create db:schema:load db:seed

# ============================================================
#  Search (Sphinx)
# ============================================================

.PHONY: sphinx-index
sphinx-index: ## Sphinx インデックス再構築
	@bundle exec rake ts:index

.PHONY: sphinx-start
sphinx-start: ## Sphinx デーモン起動
	@bundle exec rake ts:start

.PHONY: sphinx-stop
sphinx-stop: ## Sphinx デーモン停止
	@bundle exec rake ts:stop

# ============================================================
#  Background Jobs
# ============================================================

.PHONY: jobs
jobs: ## delayed_job ワーカー起動
	@bundle exec rake jobs:work

# ============================================================
#  Testing
# ============================================================

.PHONY: test
test: ## RSpec テスト実行
	@bundle exec rspec

.PHONY: test-spec
test-spec: ## 単一スペック実行 (FILE=spec/models/user_spec.rb)
	@bundle exec rspec $(FILE)

.PHONY: test-cucumber
test-cucumber: ## Cucumber テスト実行
	@bundle exec cucumber

.PHONY: test-all
test-all: ## 全テスト実行 (RSpec + Cucumber)
	@bundle exec rspec && bundle exec cucumber

# ============================================================
#  Code Quality
# ============================================================

.PHONY: lint
lint: ## Rubocop lint
	@bundle exec rubocop

.PHONY: lint-fix
lint-fix: ## Rubocop auto-fix
	@bundle exec rubocop -A

# ============================================================
#  Utils
# ============================================================

.PHONY: console
console: ## Rails コンソール起動
	@bundle exec rails console

.PHONY: routes
routes: ## ルート一覧表示
	@bundle exec rails routes

.PHONY: mailcatcher
mailcatcher: ## Mailcatcher 起動 (http://localhost:1080)
	@mailcatcher

.PHONY: clean
clean: ## 一時ファイル・ビルド成果物を削除
	@rm -rf tmp/cache tmp/pids log/*.log
	@rm -rf client/node_modules/.cache
	@echo "$(GREEN)✔ キャッシュをクリアしました$(RESET)"

# ============================================================
#  Docker
# ============================================================

.PHONY: docker-build
docker-build: ## Docker イメージビルド
	@docker-compose build

.PHONY: docker-up
docker-up: ## Docker コンテナ起動
	@docker-compose up -d

.PHONY: docker-down
docker-down: ## Docker コンテナ停止
	@docker-compose down

.PHONY: docker-logs
docker-logs: ## Docker ログ表示
	@docker-compose logs -f

# ============================================================
#  Help
# ============================================================

.PHONY: help
help: ## ヘルプ表示
	@echo ""
	@echo "$(GREEN)Sharetribe Go — 開発コマンド一覧$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
