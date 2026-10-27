# frozen_string_literal: true

require 'rails_helper'

# アクセシビリティ残件の回帰（Issue #83）。
# 対応済み項目の後退と、今回の残件修正の契約をソース断面で担保する。
RSpec.describe "アクセシビリティ残件", type: :model do
  let(:show) { File.read(Rails.root.join("app/views/listings/show.haml")) }
  let(:mypage) { File.read(Rails.root.join("app/views/people/show.haml")) }
  let(:settings) { File.read(Rails.root.join("app/views/settings/show.haml")) }
  let(:stripe) { File.read(Rails.root.join("app/assets/javascripts/thumbnail_stripe.js")) }

  it "出品詳細に h1 がある" do
    expect(show).to include("%h1.raku-breadcrumb__current")
  end

  it "タブは aria-controls・tabpanel・roving tabindex で関連付く" do
    expect(show).to include('"aria-controls": "panel-overview"')
    expect(show).to include('role: "tabpanel"')
    expect(show).to include('"aria-labelledby": "tab-features"')
  end

  it "RakuTabs は修飾キー付き矢印をブラウザに譲る" do
    expect(show).to include("e.altKey || e.ctrlKey || e.metaKey")
  end

  it "サムネイル img に名前（出品タイトル）がある" do
    expect(show).to match(/image-thumbnail-template.*alt: @listing\.title/m)
  end

  it "サムネイルの選択はキーボード操作できる" do
    expect(stripe).to include('attr("role", "button")')
    expect(stripe).to include("keydown")
  end

  it "画像ナビ（前・次）に accessible name がある" do
    expect(show).to include("t('lamprey.listings.prev_image')")
    expect(show).to include("t('lamprey.listings.next_image')")
    expect(I18n.t("lamprey.listings.prev_image", locale: :ja)).to eq("前の画像")
    expect(I18n.t("lamprey.listings.next_image", locale: :ja)).to eq("次の画像")
  end

  it "マイページは h1・nav・テーブルの scope を持つ" do
    expect(mypage).to include("%h1.raku-profile__name")
    expect(mypage).to include("%nav.raku-sidebar__nav")
    expect(mypage).to include('%th{scope: "col"}')
  end

  it "マイページの操作ボタンに aria-label がある" do
    expect(mypage).to include("aria: {label: t('lamprey.mypage.action_edit')}")
  end

  it "スキル一覧のサムネイルは装飾扱い（直後に同名リンクがある）" do
    expect(mypage).to match(/raku-table__skill-thumb\{[^}]*alt: ""/m)
  end

  it "settings の装飾アイコンは aria-hidden で、説明文は入力に紐付く" do
    expect(settings).not_to include("%span.alert-box-icon\n")
    expect(settings).to include('"aria-describedby" => "person_street_address_description"')
    expect(settings).to include('"aria-describedby" => "person_image_description"')
    expect(settings).to include('"aria-describedby" => "person_description_description"')
  end

  # Issue #78 再オープン指摘の回帰。ChatPanel のモーダル・履歴・色の契約を
  # ソース断面で担保する（ブラウザ実機・axe は未実施のため対象外）。
  describe "チャットパネルのモーダルと履歴（#78）" do
    let(:chat) { File.read(Rails.root.join("client/app/startup/ChatPanelApp.js")) }
    let(:dialog) { File.read(Rails.root.join("client/app/utils/modalDialog.js")) }
    let(:wallet) { File.read(Rails.root.join("client/app/components/WalletTopup/WalletTopupModal.js")) }
    let(:chat_css) { File.read(Rails.root.join("client/app/components/ChatPanel/chatPanel.css")) }
    let(:wallet_css) { File.read(Rails.root.join("client/app/components/WalletTopup/wallet-topup.css")) }

    it "履歴行は div role=button と入れ子 button を持たない" do
      expect(chat).not_to include("role: 'button'")
      expect(chat).to include("chatPanel__historyItemSelect")
    end

    it "リネームボタンと入力に履歴名入りの accessible name がある" do
      expect(chat).to include("tFormat('history_rename'")
      expect(I18n.t("lamprey.chat.history_rename", locale: :ja)).to include("%{title}")
      expect(I18n.t("lamprey.chat.history_rename", locale: :en)).to include("%{title}")
    end

    it "有効な履歴行は aria-current で示す" do
      expect(chat).to include("'aria-current'")
    end

    it "リネーム入力の Esc はパネル全体に伝播しない" do
      expect(chat).to match(/e\.key === 'Escape'[\s\S]*?e\.stopPropagation\(\);[\s\S]*?renamingId: null/)
    end

    it "初期フォーカスは disabled の要素を避けてフォールバックする" do
      expect(dialog).to include("el.disabled")
    end

    it "フォーカスが外に逃げた場合は document レベルで復帰させる" do
      expect(chat).to include("pullFocusInside(e, this.overlayRef)")
      expect(dialog).to include("pullFocusInside")
    end

    it "Wallet モーダルのクリックは外側オーバーレイに伝播しない" do
      expect(wallet).to include("onClick: function (e) { e.stopPropagation(); }")
    end

    it "Wallet 展開中は親パネルの aria-modal を二重化しない" do
      expect(chat).to include("'aria-hidden': state.showTopupModal")
    end

    it "メッセージ欄は追加のみ通知し、成功・接続中は role=status で通知する" do
      expect(chat).to include("'aria-relevant': 'additions'")
      expect(chat).to include("role: 'status'")
      expect(wallet).to include("role: 'status'")
    end

    it "キーボード到達するリネームボタンはフォーカス時に可視化される" do
      expect(chat_css).to include(".chatPanel__historyItem:focus-within .chatPanel__historyRenameBtn")
      expect(chat_css).to include(".chatPanel__historyRenameBtn:focus-visible")
      expect(chat_css).to include(".chatPanel__historyItemSelect:focus-visible")
    end

    it "フォーカスリングは 3:1 以上の #ff6b6b に統一する" do
      expect(chat_css).to include("outline: 2px solid #ff6b6b")
      expect(chat_css).not_to include("outline: 2px solid #c41e3a")
    end

    it "暗背景の通常テキストに 3:1 未満のグレーを使わない" do
      [chat_css, wallet_css].each do |css|
        expect(css).not_to include("color: #666")
        expect(css).not_to include("color: #555")
        expect(css).not_to include("color: #707070")
      end
    end
  end
end
