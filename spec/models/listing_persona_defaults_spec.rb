# frozen_string_literal: true

require "rails_helper"

# ペルソナ出品の既定（Issue #138）。
#
# 画面からの出品と同じ状態に、モデル層でも揃えることを固定する:
#   * 既定の run_mode は `run_online`（DB 既定も同じ）
#   * 既定の AI モデルが 1 件だけ付く（モデル定義が無い環境では何もしない）
#   * 明示指定は上書きしない
RSpec.describe Listing, "ペルソナ既定" do
  let(:community) { FactoryBot.create(:community) }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }

  context "AiModel が存在するとき" do
    let!(:ai_model) { FactoryBot.create(:ai_model) }

    it "run_online と既定モデルが付く" do
      listing = FactoryBot.create(:listing, community_id: community.id, author: author, title: "既定確認")
      listing.reload
      expect(listing.default_run_mode).to eq("run_online")
      expect(listing.supported_run_modes).to eq(["run_online"])
      expect(listing.listing_ai_models.count).to eq(1)
      expect(listing.listing_ai_models.first.is_default).to be(true)
    end

    it "明示した run_mode は上書きしない" do
      listing = FactoryBot.create(:listing, community_id: community.id, author: author,
                                            title: "明示指定", default_run_mode: "download")
      expect(listing.reload.default_run_mode).to eq("download")
    end
  end

  context "AiModel が 1 件も無いとき" do
    it "モデルは付かないが run_online になる" do
      listing = FactoryBot.create(:listing, community_id: community.id, author: author, title: "モデル無し")
      expect(listing.reload.default_run_mode).to eq("run_online")
      expect(listing.listing_ai_models.count).to eq(0)
    end
  end
end
