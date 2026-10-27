# frozen_string_literal: true

require "rails_helper"

# Issue #57: ペルソナのスキルは system ロールで先頭に固定する。
# user メッセージの先頭に指示を埋め込まないことを担保する。
RSpec.describe Ai::ChatCompletionsBuilder do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }
  let(:skill_markdown) { "## 傾聴スキル\n- 相手の感情を言語化して返す" }
  let(:listing) do
    FactoryBot.create(
      :listing,
      community_id: community.id,
      author: person,
      skill_markdown: skill_markdown
    )
  end
  let(:chat_session) do
    FactoryBot.create(:chat_session, person_id: person.id, listing_id: listing.id)
  end

  describe "#build" do
    context "履歴がある場合" do
      before do
        FactoryBot.create(:chat_message, chat_session: chat_session, role: "user", content: "こんにちは", seq: 1)
        FactoryBot.create(
          :chat_message, chat_session: chat_session, role: "assistant", content: "こんにちは、どうしましたか？", seq: 2
        )
      end

      it "戻り値の先頭が system メッセージである" do
        messages = described_class.new(chat_session).build

        expect(messages.first[:role]).to eq("system")
        expect(messages.first[:content]).to eq("## 傾聴スキル\n- 相手の感情を言語化して返す")
      end

      it "履歴を時系列順に system の後へ続ける" do
        messages = described_class.new(chat_session).build

        expect(messages.map { |m| m[:role] }).to eq(%w[system user assistant])
      end

      it "user メッセージの本文を改変しない" do
        messages = described_class.new(chat_session).build

        expect(messages[1]).to eq({ role: "user", content: "こんにちは" })
      end

      it "system ロールのエラー通知を送信対象に含めない" do
        FactoryBot.create(:chat_message, chat_session: chat_session, role: "system", content: "残高が不足しています。", seq: 3)

        roles = described_class.new(chat_session).build.map { |m| m[:role] }

        expect(roles).to eq(%w[system user assistant])
      end
    end

    context "スキルが未入力の場合" do
      let(:skill_markdown) { "" }

      it "system メッセージを作らず先頭が user になる" do
        FactoryBot.create(:chat_message, chat_session: chat_session, role: "user", content: "こんにちは", seq: 1)

        messages = described_class.new(chat_session).build

        expect(messages.map { |m| m[:role] }).not_to include("system")
        expect(messages.first).to eq({ role: "user", content: "こんにちは" })
      end
    end

    # Issue #102: 実行設定（出力の長さ・トーン）が system prompt に反映されること。
    # 実 API での効き目は script/measure_output_length.rb で測る（short 135字 /
    # long 624字）。ここでは「指示文が組み立てられているか」を固定する。
    context "実行設定が渡された場合" do
      def system_content(settings)
        described_class.new(chat_session, settings).build.first[:content]
      end

      it "output_length: short は簡潔さの指示を末尾に足す" do
        expect(system_content("output_length" => "short"))
          .to end_with(described_class::LENGTH_INSTRUCTIONS["short"])
      end

      it "output_length: long は詳細さの指示を末尾に足す" do
        expect(system_content("output_length" => "long"))
          .to end_with(described_class::LENGTH_INSTRUCTIONS["long"])
      end

      it "output_length: standard は指示を足さない" do
        expect(system_content("output_length" => "standard")).to eq(skill_markdown)
      end

      it "未知の output_length では指示を足さない" do
        expect(system_content("output_length" => "evil")).to eq(skill_markdown)
      end

      it "tone は 4 種類すべてが指示文に変換される" do
        described_class::TONE_INSTRUCTIONS.each do |tone, instruction|
          expect(system_content("tone" => tone)).to end_with(instruction)
        end
      end

      it "未知の tone では指示を足さない" do
        expect(system_content("tone" => "evil")).to eq(skill_markdown)
      end

      it "スキルが空なら実行設定だけの system メッセージになる" do
        listing.update_columns(skill_markdown: "")

        expect(system_content("output_length" => "short"))
          .to eq(described_class::LENGTH_INSTRUCTIONS["short"])
      end

      it "スキルも設定も空なら system メッセージを作らない" do
        listing.update_columns(skill_markdown: "")

        messages = described_class.new(chat_session, {}).build

        expect(messages.map { |m| m[:role] }).not_to include("system")
      end
    end

  end
end
