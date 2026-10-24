# frozen_string_literal: true

require 'rails_helper'

# フローティング 💬 アイコン削除の回帰 spec（Issue #31）。
#
# - ChatPanelApp が trigger ボタンを描画しない
# - チャットの入口が「このスキルを利用する」CTA（window.LampreyChat.open）に一本化されている
RSpec.describe "チャット導線一本化", type: :model do
  let(:js) { File.read(Rails.root.join("client/app/startup/ChatPanelApp.js")) }
  let(:css) { File.read(Rails.root.join("client/app/components/ChatPanel/chatPanel.css")) }
  let(:show) { File.read(Rails.root.join("app/views/listings/show.haml")) }

  it "trigger ボタン（chatPanel__trigger）を描画しない" do
    expect(js).not_to include("chatPanel__trigger")
  end

  it "閉状態では null を返す（フローティング表示なし）" do
    expect(js).to match(/if \(!state\.isOpen\) \{\s*return null;/m)
  end

  it "trigger 用 CSS が残っていない" do
    expect(css).not_to include("chatPanel__trigger")
  end

  it "CTA から window.LampreyChat.open() で開ける" do
    expect(show).to include("window.LampreyChat && window.LampreyChat.open()")
    expect(js).to include("window.LampreyChat")
  end

  it "ChatPanelApp は出品詳細のみにマウントされる" do
    mounts = Dir.glob(Rails.root.join("app/views/**/*.haml")).select do |f|
      File.read(f).include?("ChatPanelApp")
    end.map { |f| f.to_s.sub(Rails.root.to_s + "/", "") }
    expect(mounts).to eq(["app/views/listings/show.haml"])
  end
end
