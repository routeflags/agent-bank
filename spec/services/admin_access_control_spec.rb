# frozen_string_literal: true

require 'spec_helper'

# app/services/admin_access_control.rb の単体テスト（Issue #120）
describe AdminAccessControl do
  describe '.allowed_ip_ranges' do
    it 'ENV が未設定なら nil（IP 制限しない）' do
      with_admin_env({}) do
        expect(described_class.allowed_ip_ranges).to be_nil
        expect(described_class.ip_restriction_enabled?).to eq false
      end
    end

    it '空文字は未設定として扱う' do
      with_admin_env('ADMIN_ALLOWED_IPS' => '  ') do
        expect(described_class.allowed_ip_ranges).to be_nil
      end
    end

    it '単一 IP・CIDR・複数指定（空白入り）を解釈する' do
      with_admin_env('ADMIN_ALLOWED_IPS' => '127.0.0.1, 203.0.113.0/24') do
        ranges = described_class.allowed_ip_ranges
        expect(ranges.size).to eq 2
        expect(ranges.map(&:to_s)).to eq %w[127.0.0.1 203.0.113.0]
      end
    end

    it 'IPv6（::1 など）も解釈できる' do
      with_admin_env('ADMIN_ALLOWED_IPS' => '::1,203.0.113.10') do
        expect(described_class.allowed_ip_ranges.size).to eq 2
        expect(described_class.ip_allowed?('::1')).to eq true
      end
    end

    it '一部が不正でも解釈できた分は有効になる' do
      with_admin_env('ADMIN_ALLOWED_IPS' => '127.0.0.1,not-an-ip') do
        expect(described_class.allowed_ip_ranges.map(&:to_s)).to eq %w[127.0.0.1]
      end
    end

    it 'すべて不正なら空配列（＝全拒否）にし、警告ログを出す' do
      with_admin_env('ADMIN_ALLOWED_IPS' => 'not-an-ip') do
        expect(Rails.logger).to receive(:warn).with(/ADMIN_ALLOWED_IPS /)
        expect(described_class.allowed_ip_ranges).to eq []
      end
    end
  end

  describe '.ip_allowed?' do
    it '未設定ならすべて許可する' do
      with_admin_env({}) do
        expect(described_class.ip_allowed?('198.51.100.7')).to eq true
      end
    end

    it '完全一致の IP を許可する' do
      with_admin_env('ADMIN_ALLOWED_IPS' => '203.0.113.42') do
        expect(described_class.ip_allowed?('203.0.113.42')).to eq true
        expect(described_class.ip_allowed?('203.0.113.43')).to eq false
      end
    end

    it 'CIDR 内の IP を許可し、外は拒否する' do
      with_admin_env('ADMIN_ALLOWED_IPS' => '203.0.113.0/24') do
        expect(described_class.ip_allowed?('203.0.113.1')).to eq true
        expect(described_class.ip_allowed?('198.51.100.1')).to eq false
      end
    end

    it '0.0.0.0/0 は全許可' do
      with_admin_env('ADMIN_ALLOWED_IPS' => '0.0.0.0/0') do
        expect(described_class.ip_allowed?('198.51.100.7')).to eq true
      end
    end

    it 'IPv4 射影 IPv6 アドレスを IPv4 として判定する' do
      with_admin_env('ADMIN_ALLOWED_IPS' => '127.0.0.1') do
        expect(described_class.ip_allowed?('::ffff:127.0.0.1')).to eq true
      end
    end

    it 'remote_ip が nil または不正なら拒否する（fail closed）' do
      with_admin_env('ADMIN_ALLOWED_IPS' => '127.0.0.1') do
        expect(described_class.ip_allowed?(nil)).to eq false
        expect(described_class.ip_allowed?('')).to eq false
        expect(described_class.ip_allowed?('unknown')).to eq false
      end
    end
  end
end
