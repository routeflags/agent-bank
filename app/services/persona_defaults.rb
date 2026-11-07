# frozen_string_literal: true

# ペルソナ出品の既定値（Issue #138）。
#
# CSV/シードから作った出品は `default_run_mode` が DB 既定の `download` になり、
# `listing_ai_models` も空のため**チャットが起動できない**（ChatPanel が出ず、
# 押しても取引メッセージへ流れる）。画面から出品した場合の既定
# （`ListingFormViewUtils` の `run_online`）と揃える。
#
# 既定モデルは既存出品で最も使われている `GPT-4o Mini`。無ければ先頭のモデル。
module PersonaDefaults
  DEFAULT_MODEL_NAME = "GPT-4o Mini"

  module_function

  def run_mode
    "run_online"
  end

  def supported_run_modes
    [run_mode]
  end

  # @return [AiModel, nil]
  def ai_model
    AiModel.find_by(name: DEFAULT_MODEL_NAME) || AiModel.order(:id).first
  end

  # 既定モデルが未設定の出品にだけ付ける（既存の選択は壊さない）。
  def ensure_default_ai_model!(listing)
    return if listing.listing_ai_models.exists?

    model = ai_model
    return if model.nil?

    listing.listing_ai_models.create!(ai_model: model, is_default: true)
  end
end
