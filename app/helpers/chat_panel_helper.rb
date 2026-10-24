# frozen_string_literal: true

# Builds the i18n props hash consumed by the ChatPanel React component
# (client/app/startup/ChatPanelApp.js). Keys mirror lamprey.chat.*.
module ChatPanelHelper
  # ChatPanel へ渡す lamprey.chat.* のキー一覧。
  # 表示文言を追加したらここに 1 行足す（値の取り出しは chat_panel_i18n が行う）。
  CHAT_I18N_KEYS = %i[
    wallet_topup_title wallet_topup_close wallet_current_balance
    wallet_custom_label wallet_amount_placeholder wallet_invalid_amount
    wallet_pay_failed wallet_success wallet_processing
    wallet_submit wallet_redirecting wallet_add_credits
    wallet_buy wallet_add_preparing wallet_add_preparing_body
    wallet_topup_unavailable_reason purchase_preparing_body purchase_not_configured
    purchase_checkout_failed purchase_payment_unconfigured purchase_usd_charge
    topup_fixed_title topup_select_plan topup_fx_note
    topup_usd_estimate topup_credit_label topup_invalid_plan
    wallet_insufficient_with_purchase purchase_without_balance purchase_direct_default
    dev_purchase_success dev_purchase_failed new_chat_title
    insufficient_tokens purchase_required error_generic
    wallet_insufficient connect_failed session_create_failed
    history_title history_new history_today
    history_past_week history_earlier history_empty
    loading empty_state input_placeholder
    disclaimer balance_label settings_title
    settings_model settings_token_limit settings_tokens_unit
    settings_output_length output_short output_standard
    output_long settings_tone tone_polite
    tone_casual tone_professional tone_friendly
    message_tokens result_panel_heading result_panel_jump
    result_badge result_title attach_button
    attach_remove attach_upload_failed attach_invalid_type
    attach_too_large a11y_dialog a11y_open
    a11y_close a11y_input a11y_send
  ].freeze

  def chat_panel_i18n
    chat = I18n.t("lamprey.chat")
    chat = chat.respond_to?(:symbolize_keys) ? chat.symbolize_keys : {}

    CHAT_I18N_KEYS.index_with { |key| chat[key] }
  end

  # 開発/テスト専用の購入付与（DevPersonaPurchase）が有効か。
  # ChatPanel の購入ボタンは、有効なときだけ実際の購入 API を呼ぶ。
  # 無効な環境（本番など）では従来どおり「準備中」を表示する。
  #
  # @return [Boolean]
  def dev_purchase_enabled?
    DevPersonaPurchase.enabled?
  end
end
