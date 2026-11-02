# frozen_string_literal: true

require 'spec_helper'

# /admin throttle のパス判定（Issue #120）
describe "Rack::Attack.admin_path?" do
  it "ロケール接頭辞付きを含めて /admin 配下を対象にする" do
    expect(Rack::Attack.admin_path?("/admin")).to eq true
    expect(Rack::Attack.admin_path?("/admin/")).to eq true
    expect(Rack::Attack.admin_path?("/admin/general/privacy")).to eq true
    expect(Rack::Attack.admin_path?("/ja/admin")).to eq true
    expect(Rack::Attack.admin_path?("/ja/admin/general/privacy")).to eq true
    expect(Rack::Attack.admin_path?("/en-US/admin")).to eq true
  end

  it "類似パスや一般画面は対象外にする" do
    expect(Rack::Attack.admin_path?("/admin2")).to eq false
    expect(Rack::Attack.admin_path?("/ja/admin2")).to eq false
    expect(Rack::Attack.admin_path?("/administrators")).to eq false
    expect(Rack::Attack.admin_path?("/ja/administrators")).to eq false
    expect(Rack::Attack.admin_path?("/ja")).to eq false
    expect(Rack::Attack.admin_path?("/ja/docs")).to eq false
    expect(Rack::Attack.admin_path?("/")).to eq false
    expect(Rack::Attack.admin_path?("")).to eq false
  end
end
