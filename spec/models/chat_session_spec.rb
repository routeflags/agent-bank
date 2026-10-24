# frozen_string_literal: true

require "rails_helper"

# ペルソナの振る舞いを決める system_prompt の組み立てを検証する。
# 出品に入力したスキルが抜けていたため、スキルを含むことを明示しておく。
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
      skill_markdown: skill_markdown
    )
  end
  let(:chat_session) do
    FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
  end

  describe "#system_prompt" do
    it "出品の説明文に続いてスキルを含める" do
      prompt = chat_session.system_prompt

      expect(prompt).to include("あなたは「はるか」という相談相手です。")
      expect(prompt).to include("スキル:")
      expect(prompt).to include("相手の感情を言語化して返す")
      expect(prompt.index("あなたは")).to be < prompt.index("スキル:")
    end

    context "スキルが未入力の場合" do
      let(:skill_markdown) { "" }

      it "スキルの見出しを含めない" do
        expect(chat_session.system_prompt).not_to include("スキル:")
      end
    end

    context "外部APIが設定されている場合" do
      before do
        listing.update!(external_apis: { "search" => { "description" => "商品検索" } }.to_json)
      end

      it "スキルの後に外部APIの説明を含める" do
        prompt = chat_session.system_prompt

        expect(prompt.index("スキル:")).to be < prompt.index("利用可能な外部 API")
        expect(prompt).to include("search: 商品検索")
      end
    end
  end
end
