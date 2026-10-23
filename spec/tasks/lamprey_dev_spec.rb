# frozen_string_literal: true

require 'rails_helper'

# 開発用購入付与 Rake タスクのスペック。
# ドキュメント（documents/guides/dev_persona_purchase_flow.md）に記載した
# 手順が実際に動作することを担保する。
RSpec.describe "lamprey:dev:grant_persona", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lamprey:dev:grant_persona")
  end

  let(:community) { FactoryBot.create(:community) }
  let(:buyer) { FactoryBot.create(:person, community_id: community.id, username: "devbuyer") }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) do
    FactoryBot.create(:listing, community_id: community.id, author: author, title: "開発用ペルソナ")
  end

  def run_task(listing_ref, person_ref)
    task = Rake::Task["lamprey:dev:grant_persona"]
    task.reenable
    task.invoke(listing_ref, person_ref)
  end

  after do
    ENV.delete(DevPersonaPurchase::ENABLE_FLAG)
  end

  # 各例でユーザーを作成しておく（rake タスクは username / email で解決する）
  before { buyer }

  it "username 指定で購入権利を付与する（フラグ不要）" do
    expect { run_task(listing.id.to_s, "devbuyer") }
      .to change(UserPlanSubscription, :count).by(1)
      .and output(/購入権利を付与しました/).to_stdout
  end

  it "email 指定でも購入権利を付与できる" do
    email = buyer.emails.first&.address || FactoryBot.create(:email, person: buyer).address

    expect { run_task(listing.id.to_s, email) }
      .to change(UserPlanSubscription, :count).by(1)
  end

  it "購入済みなら duplicate を表示して二重付与しない" do
    run_task(listing.id.to_s, "devbuyer")

    expect { run_task(listing.id.to_s, "devbuyer") }
      .not_to change(UserPlanSubscription, :count)
    expect { run_task(listing.id.to_s, "devbuyer") }
      .to output(/既に購入済みです/).to_stdout
  end

  it "存在しないペルソナなら中断する" do
    expect { run_task("-1", "devbuyer") }.to raise_error(SystemExit)
  end

  it "存在しないユーザーなら中断する" do
    expect { run_task(listing.id.to_s, "no-such-user") }.to raise_error(SystemExit)
  end

  it "production では実行できない" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

    expect { run_task(listing.id.to_s, "devbuyer") }.to raise_error(SystemExit)
  end
end
