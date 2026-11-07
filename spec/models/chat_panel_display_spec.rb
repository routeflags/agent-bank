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

  # Issue #139: モデルはサーバーが解決した props.model だけを出す。
  # 以前は 'gpt-4o' が直書きされていて、出品の既定（GPT-4o Mini）と
  # 食い違ったまま既定より高価なモデル名を表示していた。
  it "#139: モデルは props から描画し、クライアント側に既定を持たない" do
    expect(js).to include("this.props.model")
    expect(js).not_to include("selectedModel")
    expect(js).not_to match(/['\"]gpt-4o['\"]/)
    expect(js).not_to include("chatPanel-modelSelect")
  end

  # Issue #139: フェンス付きコードブロックの改行を保つ。
  it "#139: コードブロックは pre で改行を保持する（CSS）" do
    css = File.read(Rails.root.join("client/app/components/ChatPanel/chatPanel.css"))
    expect(css).to match(/\.chatMessage__bubble pre \{[^}]*white-space: pre/m)
  end
end
