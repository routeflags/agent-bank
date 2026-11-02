# frozen_string_literal: true

require 'spec_helper'

# /admin 配下の専用 throttle（rack-attack）の実効性テスト（Issue #120）
#
# テスト環境では config/initializers/rack_attack.rb が
# Rack::Attack.enabled = false にしているため、この describe の中だけで明示的に
# 有効化し、終了時に元の状態へ戻す。
describe "管理画面のレート制限（rack-attack）", type: :request do
  def admin_limit
    Rack::Attack::ADMIN_THROTTLE_LIMIT
  end

  # throttle カウンタだけを消す（Rack::Attack.reset! は文字列 matcher で
  # ActiveSupport 8 では失敗するため、Regexp で消す）
  def clear_rack_attack_cache
    Rack::Attack.cache.store.delete_matched(/rack::attack/)
  end

  around do |example|
    previous = Rack::Attack.enabled
    Rack::Attack.enabled = true
    clear_rack_attack_cache
    example.run
  ensure
    clear_rack_attack_cache
    Rack::Attack.enabled = previous
  end

  before do
    @domain = "admin-throttle.custom.org"
    FactoryBot.create(:community, domain: @domain, use_domain: true,
                                  settings: { "locales" => ["ja"] })
  end

  def get_admin_path(path = "/ja/admin/general/privacy")
    get "http://#{@domain}#{path}"
  end

  it "同一 IP から /admin へ上限を超えてアクセスすると 429 になる" do
    statuses = Array.new(admin_limit + 1) do
      get_admin_path
      response.status
    end

    # 上限まではアプリまで届く（未ログインなのでログインへリダイレクト）
    expect(statuses.first(admin_limit).uniq).to eq [302]
    expect(statuses.last).to eq 429
  end

  it "429 以降も /admin 以外のパスは遮断されない" do
    (admin_limit + 1).times { get_admin_path }
    expect(response.status).to eq 429

    get "http://#{@domain}/ja"
    expect(response.status).not_to eq 429
  end

  it "ログイン試行制限（session/ip）とは独立している" do
    (admin_limit + 1).times { get_admin_path }
    expect(response.status).to eq 429

    # /admin の制限を消費していても、ログイン POST は 429 にならない
    post "http://#{@domain}/ja/sessions",
         params: { person: { login: "nobody", password: "wrong" } }
    expect(response.status).not_to eq 429
  end
end
