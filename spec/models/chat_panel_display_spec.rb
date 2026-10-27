# frozen_string_literal: true

require 'rails_helper'

# ChatPanel フロントの表示回帰（Issue #85・#86・#89）。
# ブラウザ実行が無い環境のためソース契約で担保する。
RSpec.describe "ChatPanel の表示契約", type: :model do
  let(:js) { File.read(Rails.root.join("client/app/startup/ChatPanelApp.js")) }

  it "#85: チャージボタンは可否にかかわらず「追加する」に統一する" do
    expect(js).to include("}, t('wallet_submit'))")
    expect(js).not_to include("t('wallet_add_preparing')")
  end

  it "#85: 利用不可時は disabled＋理由行で案内する" do
    expect(js).to include("disabled: !state.topupEnabled")
    expect(js).to include("wallet-topup-unavailable")
    expect(js).to include("t('wallet_topup_unavailable_reason')")
  end

  it "#85: 追加ボタンは Gold 系（サイトのチャージ導線と統一）である" do
    css = File.read(Rails.root.join("client/app/components/WalletTopup/wallet-topup.css"))
    expect(css).to include("--wallet-accent")
    expect(css).to match(/\.wallet-balance__topupBtn \{[^}]*var\(--wallet-accent/m)
  end

  it "#86: 確定イベントの全文で逐次組立文を置換する（順序崩れの自己修復）" do
    expect(js).to include("data.content")
    expect(js).to match(/typeof data\.content === 'string'/m)
    expect(js).to include("content: fullContent")
  end

  it "#86: 全文が無ければ組立文を維持する（後方互換）" do
    expect(js).to include("data.content.length > 0")
  end

  it "#89: ヘッダーに persona_name を描画する" do
    expect(js).to include("this.props.persona_name")
    expect(js).to include("chatPanel__personaName")
  end

  it "#89: props 未渡し時のみ汎用名にフォールバックする" do
    expect(js).to include("this.props.persona_name || 'AI Assistant'")
  end
end
