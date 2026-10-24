# frozen_string_literal: true

require "rails_helper"

# ペルソナの振る舞いを決める system_prompt の組み立てを検証する。
# スキルマークダウンが商品であり、店头の説明文は AI には渡さない。
RSpec.describe ChatSession, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:skill_markdown) { "## 傾聴スキル\n- 相手の感情を言語化して返す" }
  let(:listing) do
    FactoryBot.create(
      :listing,
      community_id: community.id,
      author: person,
      short_description: "あなたは「はるか」という相談相手です。",
      description: "悩みに寄り添うAIペルソナです。",
      skill_markdown: skill_markdown
    )
  end
  let(:chat_session) do
    FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
  end

  describe "#system_prompt" do
    it "スキルマークダウンをそのままシステムプロンプトにする" do
      expect(chat_session.system_prompt).to eq("## 傾聴スキル\n- 相手の感情を言語化して返す")
    end

    it "出品の説明文（short_description / description）を含めない" do
      prompt = chat_session.system_prompt

      expect(prompt).not_to include("はるか")
      expect(prompt).not_to include("悩みに寄り添う")
    end

    context "スキルが未入力の場合" do
      let(:skill_markdown) { "" }

      it "説明文があっても nil を返す" do
        expect(chat_session.system_prompt).to be_nil
      end
    end

    context "外部APIが設定されている場合" do
      before do
        listing.update!(external_apis: { "search" => { "description" => "商品検索" } }.to_json)
      end

      it "スキルの後に外部APIの説明を続ける" do
        prompt = chat_session.system_prompt

        expect(prompt.index("傾聴スキル")).to be < prompt.index("利用可能な外部 API")
        expect(prompt).to include("search: 商品検索")
      end
    end
  end
end
