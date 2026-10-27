# frozen_string_literal: true

require 'spec_helper'

# 短縮表示ヘルパー（Issue #95）の境界値。
RSpec.describe CompactNumberHelper, type: :helper do
  it "1,000 未満は全桁表示する" do
    expect(helper.compact_number(0)).to eq("0")
    expect(helper.compact_number(999)).to eq("999")
  end

  it "1,000 以上は K で短縮する" do
    expect(helper.compact_number(1000)).to eq("1K")
    expect(helper.compact_number(1200)).to eq("1.2K")
    expect(helper.compact_number(999_999)).to eq("1M")
  end

  it "100万以上は M、10億以上は B で短縮する" do
    expect(helper.compact_number(1_000_000)).to eq("1M")
    expect(helper.compact_number(2_500_000)).to eq("2.5M")
    expect(helper.compact_number(1_200_000_000)).to eq("1.2B")
  end

  it "nil は 0 として扱う" do
    expect(helper.compact_number(nil)).to eq("0")
  end
end
