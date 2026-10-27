# frozen_string_literal: true

# Builds the i18n props hash consumed by the ChatPanel React component
# (client/app/startup/ChatPanelApp.js). Keys mirror lamprey.chat.*.
module ChatPanelHelper
  # ChatPanel へ渡す lamprey.chat.* のキー一覧。
  # 表示文言を追加したらここに 1 行足す（値の取り出しは chat_panel_i18n が行う）。
  # 課金は残高（ウォレット）一本（Issue #51）。ペルソナ購入の文言は持たない。
  CHAT_I18N_KEYS = %i[
    wallet_topup_title wallet_topup_close wallet_current_balance
    wallet_custom_label wallet_amount_placeholder wallet_invalid_amount
    wallet_pay_failed wallet_success wallet_processing
    wallet_submit wallet_redirecting wallet_add_credits
    wallet_topup_unavailable_reason
    topup_fixed_title topup_select_plan topup_fx_note
    topup_usd_estimate topup_credit_label topup_invalid_plan
    new_chat_title
    insufficient_tokens error_generic
    wallet_insufficient connect_failed session_create_failed
    history_title history_new history_today
    history_past_week history_earlier history_empty
    history_rename
    loading empty_state input_placeholder
    disclaimer balance_label settings_title
    settings_model settings_token_limit settings_tokens_unit
    settings_token_unlimited
    settings_output_length output_short output_standard
    output_long settings_tone tone_polite
    tone_casual tone_professional tone_friendly
    message_tokens result_panel_heading
    result_badge result_title attach_button
    attach_remove attach_upload_failed attach_invalid_type
    attach_too_large a11y_dialog a11y_open
    a11y_close a11y_input a11y_send
    a11y_connected a11y_disconnected
    truncated_notice truncated_continue truncated_continue_prompt
    copy copied
  ].freeze

  def chat_panel_i18n
    chat = I18n.t("lamprey.chat")
    chat = chat.respond_to?(:symbolize_keys) ? chat.symbolize_keys : {}

    CHAT_I18N_KEYS.index_with { |key| chat[key] }
  end
end
