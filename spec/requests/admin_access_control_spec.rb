# frozen_string_literal: true

require 'spec_helper'

# /admin 配下の IP 許可リスト制限の振る舞いテスト（Issue #120）
#
# ENV は実行時に参照されるため、with_admin_env でリクエストごとに切り替えて検証する。
#
# 期待するステータス:
# - 302 … 制限を通過し、未ログインのため ensure_is_admin がログインへ送った
# - 403 … IP 許可リストで拒否
#
# なお管理画面本体の描画（200）は、この作業ツリーに webpack のビルド成果物
# （vendor-bundle 等）が無いため検証対象外にしている（環境依存の既存制約）。
describe "管理画面の IP 制限（/admin）", type: :request do
  let(:admin_path) { "/ja/admin/general/privacy" }
  let(:denied_ip) { "198.51.100.7" }
  let(:allowed_cidr) { "203.0.113.0/24" }
  let(:allowed_ip) { "203.0.113.42" }

  before do
    @domain = "admin-acl.custom.org"
    FactoryBot.create(:community, domain: @domain, use_domain: true,
                                  settings: { "locales" => ["ja"] })
  end

  def get_admin(headers = {})
    get "http://#{@domain}#{admin_path}", headers: headers
  end

  def get_admin_from(remote_ip)
    get_admin({ "X-Forwarded-For" => remote_ip })
  end

  context "ADMIN_ALLOWED_IPS が未設定のとき" do
    it "何もせず、従来どおり ensure_is_admin がログインへリダイレクトする" do
      with_admin_env({}) do
        get_admin
        expect(response.status).to eq 302
      end
    end

    it "許可外相当の IP でも遮断しない" do
      with_admin_env("ADMIN_ALLOWED_IPS" => "") do
        get_admin_from(denied_ip)
        expect(response.status).to eq 302
      end
    end

    it "一般画面に影響しない" do
      with_admin_env({}) do
        get "http://#{@domain}/ja"
        expect(response.status).not_to eq 403
      end
    end
  end

  context "ADMIN_ALLOWED_IPS を設定したとき" do
    it "許可リスト内の IP は通過する" do
      with_admin_env("ADMIN_ALLOWED_IPS" => "127.0.0.1") do
        get_admin
        expect(response.status).to eq 302
      end
    end

    it "CIDR 内の IP は通過する" do
      with_admin_env("ADMIN_ALLOWED_IPS" => allowed_cidr) do
        get_admin_from(allowed_ip)
        expect(response.status).to eq 302
      end
    end

    it "0.0.0.0/0 は全許可（IP 制限を実質無効化）" do
      with_admin_env("ADMIN_ALLOWED_IPS" => "0.0.0.0/0") do
        get_admin_from(denied_ip)
        expect(response.status).to eq 302
      end
    end

    it "複数指定（IP と CIDR の混在・空白入り）を解釈する" do
      with_admin_env("ADMIN_ALLOWED_IPS" => "127.0.0.1, #{allowed_cidr}") do
        get_admin_from(allowed_ip)
        expect(response.status).to eq 302
      end
    end

    it "許可外の IP は 403（ログイン画面へリダイレクトしない）" do
      with_admin_env("ADMIN_ALLOWED_IPS" => allowed_cidr) do
        get_admin_from(denied_ip)
        expect(response.status).to eq 403
      end
    end

    it "解釈できない設定は全拒否（403）に倒す" do
      with_admin_env("ADMIN_ALLOWED_IPS" => "not-an-ip") do
        get_admin
        expect(response.status).to eq 403
      end
    end
  end

  context "制限を設定しても一般画面は影響を受けない" do
    it "許可外 IP でも /ja は 403 にならない" do
      with_admin_env("ADMIN_ALLOWED_IPS" => allowed_cidr) do
        get "http://#{@domain}/ja", headers: { "X-Forwarded-For" => denied_ip }
        expect(response.status).not_to eq 403
      end
    end
  end
end
