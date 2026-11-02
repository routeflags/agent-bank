# frozen_string_literal: true

require 'spec_helper'
# lib/ は自動読み込み対象外なので明示的に読み込む（production.rb と同じ）
require_relative '../../lib/tls_settings'

# lib/tls_settings.rb の単体テスト（Issue #120 / #121）
describe TlsSettings do
  it "FORCE_SSL の真値で有効になる" do
    %w[1 true TRUE yes on].each do |value|
      with_env("FORCE_SSL" => value, "APP_DOMAIN" => nil) do
        expect(described_class.force_ssl?).to eq true
      end
    end
  end

  it "FORCE_SSL が偽値・空・未設定なら無効" do
    ["0", "false", "", "  ", nil].each do |value|
      with_env("FORCE_SSL" => value, "APP_DOMAIN" => nil) do
        expect(described_class.force_ssl?).to eq false
      end
    end
  end

  it "APP_DOMAIN が https:// で始まれば有効" do
    with_env("FORCE_SSL" => nil, "APP_DOMAIN" => "https://example.com") do
      expect(described_class.force_ssl?).to eq true
    end
  end

  it "APP_DOMAIN がホスト名のみ（現在の .env の使い方）なら無効" do
    with_env("FORCE_SSL" => nil, "APP_DOMAIN" => "example.com") do
      expect(described_class.force_ssl?).to eq false
    end
  end
end
