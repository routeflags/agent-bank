# frozen_string_literal: true

# Builds the i18n props consumed by the MypageWallet React component
# (client/app/startup/MypageWalletApp.js). The charge modal reuses the
# lamprey.chat.* top-up strings, so this merges ChatPanelHelper's dict
# with the mypage-specific button label (Issue #58).
module MypageHelper
  include ChatPanelHelper

  def mypage_wallet_i18n
    chat_panel_i18n.merge(
      wallet_charge: I18n.t("lamprey.mypage.wallet_charge")
    )
  end
end
