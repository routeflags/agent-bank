# frozen_string_literal: true

require "rails_helper"

# Issue #106 Phase 2a: 評価集計の正規化タスク。
#
# 既定はドライラン（DB を変えない）、`COMMIT=1` で適用。何度実行しても
# 2 回目以降は対象 0 件になる（冪等）。
RSpec.describe "lamprey:normalize_listing_ratings", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lamprey:normalize_listing_ratings")
  end

  let(:community) { FactoryBot.create(:community) }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) { FactoryBot.create(:listing, community_id: community.id, author: author) }

  # 初期データの手動値（実データに存在した 4.5 等）を再現する。
  def stub_manual_rating(rating, count: 0)
    listing.update_columns(avg_rating: rating, reviews_count: count)
  end

  def run_task(commit: false)
    task = Rake::Task["lamprey:normalize_listing_ratings"]
    task.reenable

    if commit
      ENV["COMMIT"] = "1"
    else
      ENV.delete("COMMIT")
    end

    capture_stdout { task.invoke }
  ensure
    ENV.delete("COMMIT")
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  it "既定はドライランで、avg_rating を書き換えない" do
    stub_manual_rating(4.5)

    output = run_task

    expect(output).to include("mode=dry-run")
    expect(output).to include("listing ##{listing.id}")
    expect(output).to include("対象 1 件")
    expect(listing.reload.avg_rating).to eq(4.5)
  end

  it "ドライランでも reviews_count の不整合を検出する" do
    stub_manual_rating(0.0, count: 5)

    output = run_task

    expect(output).to include("reviews_count 5 -> 0")
    expect(listing.reload.reviews_count).to eq(5)
  end

  it "COMMIT=1 で Testimonial が0件の手動値を 0.0 に戻す" do
    stub_manual_rating(4.5)

    output = run_task(commit: true)

    expect(output).to include("適用しました: 1 件")
    expect(listing.reload.avg_rating).to eq(0.0)
    expect(listing.reviews_count).to eq(0)
  end

  it "COMMIT=1 で実レビューに合わせて集計を上書きする" do
    other_reviewer = FactoryBot.create(:person, community_id: community.id)
    Testimonial.create!(listing_id: listing.id, author_id: author.id,
                        receiver_id: author.id, grade: 0.75)
    Testimonial.create!(listing_id: listing.id, author_id: other_reviewer.id,
                        receiver_id: author.id, grade: 0.5)
    stub_manual_rating(4.5)

    run_task(commit: true)

    expect(listing.reload.avg_rating).to eq(3.5)
    expect(listing.reviews_count).to eq(2)
  end

  it "整合している出品は対象にしない（2回目は0件）" do
    stub_manual_rating(4.5)
    run_task(commit: true)

    output = run_task(commit: true)

    expect(output).to include("対象 0 件")
    expect(listing.reload.avg_rating).to eq(0.0)
  end
end
