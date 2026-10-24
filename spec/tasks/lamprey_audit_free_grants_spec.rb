# frozen_string_literal: true

require "rails_helper"

# 読み取り専用監査 Rake タスクのスペック（Issue #25）。
#
# 旧逆ガード（free 遷移×有料 listing で UserPlanSubscription と初回トークンを
# 付与）を再現したデータを作り、
#   * 検出できること（直接証拠・判定区分・件数）
#   * 絞り込み引数（期間・community）が効くこと
#   * 何も書き換えないこと（READ ONLY + カウント不変）
# を出力と DB の両面から担保する。
RSpec.describe "lamprey:audit:free_grants", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("lamprey:audit:free_grants")
  end

  let(:community) { FactoryBot.create(:community) }
  let(:other_community) { FactoryBot.create(:community) }
  let(:buyer) { FactoryBot.create(:person, community_id: community.id, username: "audit_buyer") }
  let(:author) { FactoryBot.create(:person, community_id: community.id) }
  let(:paid_listing) do
    FactoryBot.create(
      :listing,
      community_id: community.id, author: author,
      title: "有料ペルソナ", price: Money.new(1000, "USD")
    )
  end
  # Issue #52: 価格 0 の出品は新規作成できない。旧来データ相当としてバリデーションを迂回する。
  let(:free_listing) do
    FactoryBot.build(
      :listing,
      community_id: community.id, author: author,
      title: "価格0（旧来データ）", price: 0
    ).tap { |l| l.save!(validate: false) }
  end

  def create_free_tx(listing:, buyer:, community:, **attrs)
    FactoryBot.create(
      :transaction,
      { starter: buyer, listing: listing, community: community, current_state: "free" }.merge(attrs)
    )
  end

  def create_confirmed_tx(listing:, buyer:, community:)
    FactoryBot.create(
      :transaction,
      starter: buyer, listing: listing, community: community, current_state: "confirmed"
    )
  end

  def run_task(since: nil, until_date: nil, community_id: nil)
    task = Rake::Task["lamprey:audit:free_grants"]
    task.reenable
    task.invoke(since, until_date, community_id&.to_s)
  end

  def run_task_output(**kwargs)
    original = $stdout
    $stdout = StringIO.new
    run_task(**kwargs)
    $stdout.string
  ensure
    $stdout = original
  end

  def db_counts
    [UserPlanSubscription.count, CreditTransaction.count, Wallet.count, Transaction.count]
  end

  context "旧逆ガードで付与済みの取引がある場合" do
    before do
      # 旧実装は free 遷移時にこの処理を呼んでいた（Issue #18 で修正）
      UserPlanSubscriptionService.create_on_purchase(free_tx)
    end

    let(:free_tx) { create_free_tx(listing: paid_listing, buyer: buyer, community: community) }

    it "この取引由来の付与を検出し巻き戻し候補と判定する" do
      output = run_task_output

      expect(output).to include("transaction_id=#{free_tx.id} current_state=free")
      expect(output).to include("reference=initial_purchase_#{free_tx.id} ←この取引由来")
      expect(output).to match(/巻き戻し候補（この取引の free 遷移で付与された直接証拠あり） : 1 件/)
      expect(output).to match(/対象（free×有料 listing）\s*: 1 件/)
      expect(output).to match(/オーナー判断が必要（巻き戻し候補＋要判断＋要確認） : 1 件/)
    end

    it "購入権利・トークン・ウォレットの明細を出力する" do
      output = run_task_output

      expect(output).to match(/購入権利\s+: subscription_id=\d+ status=active/)
      expect(output).to match(/初回トークン: credit_transaction_id=\d+ amount_cents=\d+/)
      expect(output).to match(/wallet\s+: wallet_id=\d+ balance_cents=\d+/)
    end

    it "一切書き換えない（READ ONLY・カウント不変）" do
      before_counts = db_counts
      run_task_output
      expect(db_counts).to eq(before_counts)
    end
  end

  context "付与のない対象取引" do
    let!(:free_tx) { create_free_tx(listing: paid_listing, buyer: buyer, community: community) }

    it "対象として拾いつつ付与なしと判定する" do
      output = run_task_output

      expect(output).to include("transaction_id=#{free_tx.id}")
      expect(output).to match(/購入権利\s+: なし/)
      expect(output).to match(/初回トークン: なし/)
      expect(output).to match(/付与なし : 1 件/)
      expect(output).to match(/オーナー判断が必要（巻き戻し候補＋要判断＋要確認） : 0 件/)
    end
  end

  context "実購入（confirmed）の裏付けがある場合" do
    it "実購入の裏付けありと判定する（この free 取引は誤検知側）" do
      free_tx = create_free_tx(listing: paid_listing, buyer: buyer, community: community)
      confirmed_tx = create_confirmed_tx(listing: paid_listing, buyer: buyer, community: community)
      UserPlanSubscriptionService.create_on_purchase(confirmed_tx)

      output = run_task_output

      expect(output).to include("transaction_id=#{free_tx.id}")
      expect(output).to include("transaction_id=#{confirmed_tx.id} (confirmed, reference一致)")
      expect(output).to match(/実購入の裏付けあり（巻き戻し不要の可能性） : 1 件/)
      expect(output).not_to include("initial_purchase_#{free_tx.id}")
    end

    it "この取引由来トークンと実購入が併存する場合は要判断と判定する" do
      free_tx = create_free_tx(listing: paid_listing, buyer: buyer, community: community)
      # 旧実装が先に付与 → 後の実購入は idempotent にスキップされる（reference は残らない）
      UserPlanSubscriptionService.create_on_purchase(free_tx)
      confirmed_tx = create_confirmed_tx(listing: paid_listing, buyer: buyer, community: community)
      UserPlanSubscriptionService.create_on_purchase(confirmed_tx)

      output = run_task_output

      expect(output).to include("reference=initial_purchase_#{free_tx.id} ←この取引由来")
      expect(output).to include("transaction_id=#{confirmed_tx.id} (confirmed, reference未確認)")
      expect(output).to match(/要判断（この取引由来トークン＋実購入の裏付けあり） : 1 件/)
    end
  end

  context "対象外の取引" do
    it "価格0（旧来データ）の listing の free 取引は対象にしない" do
      free_tx = create_free_tx(listing: free_listing, buyer: buyer, community: community)

      output = run_task_output

      expect(output).not_to include("transaction_id=#{free_tx.id}")
      expect(output).to match(/対象（free×有料 listing）\s*: 0 件/)
    end

    it "有料 listing でも confirmed の取引は対象にしない" do
      confirmed_tx = create_confirmed_tx(listing: paid_listing, buyer: buyer, community: community)

      output = run_task_output

      expect(output).not_to include("transaction_id=#{confirmed_tx.id}")
      expect(output).to match(/対象（free×有料 listing）\s*: 0 件/)
    end
  end

  context "絞り込み引数" do
    it "community_id 指定で他の community の取引を除外する" do
      own_tx = create_free_tx(listing: paid_listing, buyer: buyer, community: community)
      other_buyer = FactoryBot.create(:person, community_id: other_community.id, username: "other_buyer")
      other_listing = FactoryBot.create(
        :listing,
        community_id: other_community.id,
        price: Money.new(1000, "USD")
      )
      other_tx = create_free_tx(listing: other_listing, buyer: other_buyer, community: other_community)

      all_output = run_task_output
      expect(all_output).to include("transaction_id=#{own_tx.id}", "transaction_id=#{other_tx.id}")

      filtered = run_task_output(community_id: other_community.id)
      expect(filtered).to include("transaction_id=#{other_tx.id}")
      expect(filtered).not_to include("transaction_id=#{own_tx.id}")
      expect(filtered).to match(/community_id=#{other_community.id}/)
    end

    it "since/until 指定で期間外の取引を除外する" do
      old_tx = create_free_tx(listing: paid_listing, buyer: buyer, community: community,
                              created_at: 60.days.ago, last_transition_at: 60.days.ago)

      unfiltered = run_task_output
      expect(unfiltered).to include("transaction_id=#{old_tx.id}")

      filtered = run_task_output(since: 30.days.ago.to_date.iso8601,
                                 until_date: Time.zone.today.iso8601)
      expect(filtered).not_to include("transaction_id=#{old_tx.id}")
      expect(filtered).to match(/対象（free×有料 listing）\s*: 0 件/)
    end
  end

  context "不正な引数" do
    it "日付を解釈できない場合は中断する" do
      expect { run_task_output(since: "not-a-date") }.to raise_error(SystemExit)
    end

    it "since が until より後の場合は中断する" do
      expect do
        run_task_output(since: Time.zone.today.iso8601, until_date: 10.days.ago.to_date.iso8601)
      end.to raise_error(SystemExit)
    end

    it "community_id が整数でない場合は中断する" do
      expect { run_task_output(community_id: "abc") }.to raise_error(SystemExit)
    end
  end
end
