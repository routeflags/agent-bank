# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ResultDetector do
  describe ".result?" do
    context "code artifact" do
      it "flags a message containing a fenced code block" do
        content = "Here is the function you asked for:\n\n```ruby\ndef hello\n  puts 'hi'\nend\n```\n\nLet me know if you need changes."
        expect(described_class.result?(content)).to be true
      end

      it "flags a code block without a language tag" do
        content = "```\nsome raw output\n```"
        expect(described_class.result?(content)).to be true
      end
    end

    context "structured document" do
      let(:long_doc) do
        <<~DOC
          # Analysis

          This is a detailed analysis of the quarterly results covering
          multiple dimensions of the business including revenue, costs,
          customer acquisition, and retention metrics across all regions.

          ## Revenue

          Revenue grew steadily throughout the quarter driven primarily by
          the new enterprise tier launched in March. Regional breakdown
          shows particular strength in APAC markets.

          ## Costs

          Infrastructure costs remained flat while headcount grew modestly.
          Overall unit economics improved by 12% compared to prior quarter.
        DOC
      end

      it "flags a long document with multiple headers" do
        expect(described_class.result?(long_doc)).to be true
      end

      it "does not flag short prose even with headers" do
        content = "## Steps\n\n1. Open the file\n2. Edit the line"
        expect(described_class.result?(content)).to be false
      end
    end

    context "normal conversational replies" do
      it "does not flag a short answer" do
        expect(described_class.result?("Yes, you can use the `rails` command to generate a model.")).to be false
      end

      it "does not flag a greeting" do
        expect(described_class.result?("こんにちは！何をお手伝いしましょうか？")).to be false
      end

      it "does not flag a bullet list without code or document structure" do
        content = "- option A\n- option B\n- option C"
        expect(described_class.result?(content)).to be false
      end
    end

    context "edge cases" do
      it "returns false for nil" do
        expect(described_class.result?(nil)).to be false
      end

      it "returns false for empty string" do
        expect(described_class.result?("")).to be false
      end

      it "returns false for whitespace only" do
        expect(described_class.result?("   \n  ")).to be false
      end
    end
  end
end
