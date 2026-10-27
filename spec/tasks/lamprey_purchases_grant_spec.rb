# frozen_string_literal: true

require "rails_helper"

# 管理者による手動付与 Rake タスクのスペック（Issue #24）。
#
# 決済手段を持たないコミュニティ（payment_process: none — ファクトリの
# community は決済設定を持たないこの構成）でも、オーナー承認ベースの手動付与
# で有料ペルソナを利用できるようにする正式な経路。次のことを固定する:
#   * operator 必須（未指定なら中断し何も付与しない）
#   * 冪等性（active な購入権利があれば二重付与しない）
#   * payment_reference の形式（manual_grant:<operator>:<ISO8601>）
#   * production 環境でも動作すること
#   * 実行ログに operator と対象が残ること
RSpec.describe "lamprey:purchases:grant", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lamprey:purchases:grant")
  end

  let(:community) { FactoryBot.create(:community) }
  let(:buyer) { FactoryBot.create(:person, community_id: community.id, username: "grantbuyer") }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }
  let(:listing) do
    FactoryBot.create(:listing, community_id: community.id, author: author, title: "有料ペルソナ")
  end

  def run_task(listing_ref, person_ref, operator_ref)
    task = Rake::Task["lamprey:purchases:grant"]
    task.reenable
    task.invoke(listing_ref, person_ref, operator_ref)
  end

  # 付与時に作られるウォレットトップアップの監査参照を返す
  # （Wallet#topup! は CreditTransaction.metadata の stripe_payment_id に保持する）
  def granted_payment_reference
    wallet = Wallet.find_by!(person_id: buyer.id, community_id: community.id)
    credit_tx = CreditTransaction.where(wallet_id: wallet.id, transaction_type: "topup").last
    JSON.parse(credit_tx.metadata.to_s)["stripe_payment_id"]
  end

  # 各例でユーザーを作成しておく（タスクは username / email / id で解決する）
  before { buyer }

  it "username 指定で operator ごと購入権利と初回トークンを付与する" do
    expect { run_task(listing.id.to_s, "grantbuyer", "owner1") }
      .to change(UserPlanSubscription, :count).by(1)
      .and output(/購入権利を付与しました/).to_stdout

    subscription = UserPlanSubscription.last
    expect(subscription.status).to eq("active")
    expect(subscription.person_id).to eq(buyer.id)
    expect(subscription.listing_id).to eq(listing.id)
  end

  it "person を email で指定しても付与できる" do
    email = buyer.emails.first&.address || FactoryBot.create(:email, person: buyer).address

    expect { run_task(listing.id.to_s, email, "owner1") }
      .to change(UserPlanSubscription, :count).by(1)
  end

  it "person を id で指定しても付与できる" do
    expect { run_task(listing.id.to_s, buyer.id.to_s, "owner1") }
      .to change(UserPlanSubscription, :count).by(1)
  end

  it "payment_reference は manual_grant:<operator>:<ISO8601> 形式で記録される" do
    run_task(listing.id.to_s, "grantbuyer", "owner1")

    reference = granted_payment_reference
    expect(reference).to start_with("manual_grant:owner1:")
    iso_part = reference.delete_prefix("manual_grant:owner1:")
    expect { Time.iso8601(iso_part) }.not_to raise_error
  end

  it "付与前の警告出力に対象明細（person / listing / 付与トークン数）が含まれる" do
    output = capture_stdout { run_task(listing.id.to_s, "grantbuyer", "owner1") }

    expect(output).to include("管理者による手動付与を実行します")
    expect(output).to include("operator      : owner1")
    expect(output).to include("person        : grantbuyer (person_id=#{buyer.id})")
    expect(output).to include("listing       : #{listing.id}")
    expect(output).to include("付与トークン数")
  end

  it "operator 未指定（空文字）なら中断し、何も付与しない" do
    expect { run_task(listing.id.to_s, "grantbuyer", "") }.to raise_error(SystemExit)
    expect(UserPlanSubscription.count).to eq(0)
    expect(Wallet.count).to eq(0)
  end

  it "operator 無し（引数2つのみ）でも中断する" do
    task = Rake::Task["lamprey:purchases:grant"]
    task.reenable

    expect { task.invoke(listing.id.to_s, "grantbuyer") }.to raise_error(SystemExit)
    expect(UserPlanSubscription.count).to eq(0)
  end

  it "既に active な購入権利があれば二重付与せず、その旨を出して正常終了する" do
    run_task(listing.id.to_s, "grantbuyer", "owner1")

    expect { run_task(listing.id.to_s, "grantbuyer", "owner1") }
      .to output(/既に active な購入権利があります。二重付与はしません/).to_stdout
    expect(UserPlanSubscription.count).to eq(1)
    # トークンも再付与されない（トップアップが増えない）
    expect { run_task(listing.id.to_s, "grantbuyer", "owner1") }.not_to change(CreditTransaction, :count)
  end

  it "production 環境でも動作する" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

    expect { run_task(listing.id.to_s, "grantbuyer", "owner1") }
      .to change(UserPlanSubscription, :count).by(1)
  end

  it "実行ログ（Rails.logger）に operator と対象が残る" do
    allow(Rails.logger).to receive(:info).and_call_original

    run_task(listing.id.to_s, "grantbuyer", "owner1")

    expect(Rails.logger).to have_received(:info)
      .with(a_string_matching(/operator=owner1 person_id=#{buyer.id} listing_id=#{listing.id}/))
  end

  it "存在しないペルソナなら中断する" do
    expect { run_task("-1", "grantbuyer", "owner1") }.to raise_error(SystemExit)
  end

  it "存在しないユーザーなら中断する" do
    expect { run_task(listing.id.to_s, "no-such-user", "owner1") }.to raise_error(SystemExit)
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
