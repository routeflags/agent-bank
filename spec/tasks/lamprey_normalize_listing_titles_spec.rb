# frozen_string_literal: true

require "rails_helper"

# 出品タイトル正規化タスクのスペック（Issue #137）。
#
# 固定すること:
#   * 既定はドライラン（DB を変えない）
#   * COMMIT=1 で「ペルソナ名 — 」の前置きだけが落ちる
#   * 区切りの無いタイトルには触らない
#   * slug と updated_at を変えない（既存リンク・並び順を壊さない）
RSpec.describe "lamprey:normalize_listing_titles", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lamprey:normalize_listing_titles")
  end

  let(:community) { FactoryBot.create(:community) }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }
  let!(:target) do
    FactoryBot.create(:listing, community_id: community.id, author: author,
                                title: "しんだん — SEOサイト監査")
  end
  let!(:plain) do
    FactoryBot.create(:listing, community_id: community.id, author: author, title: "日英翻訳")
  end

  after { ENV.delete("COMMIT") }

  def run_task
    task = Rake::Task["lamprey:normalize_listing_titles"]
    task.reenable
    task.invoke
  end

  it "ドライランでは DB を変更しない" do
    run_task
    expect(target.reload.title).to eq("しんだん — SEOサイト監査")
  end

  it "COMMIT=1 で機能名だけになる" do
    ENV["COMMIT"] = "1"
    run_task
    expect(target.reload.title).to eq("SEOサイト監査")
  end

  it "区切りの無いタイトルには触らない" do
    ENV["COMMIT"] = "1"
    run_task
    expect(plain.reload.title).to eq("日英翻訳")
  end

  # slug は `id-title` の合成（Listing#to_param）なので URL の見た目は変わるが、
  # 先頭の id が変わらないため既存リンクは解決できる。updated_at は動かさない。
  it "URL の id 部分と updated_at を変えない" do
    id_before = target.to_param.split("-").first
    updated_before = target.updated_at
    ENV["COMMIT"] = "1"
    run_task
    target.reload
    expect(target.to_param.split("-").first).to eq(id_before)
    expect(target.updated_at).to eq(updated_before)
  end
end
