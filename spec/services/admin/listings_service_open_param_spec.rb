# frozen_string_literal: true

require "spec_helper"

# Issue #72: 出品編集画面の公開/非公開ラジオ。
#
# `update_by_author_params` は所有者の更新時にマージされるパラメータを返す。
# ここに `open` が正しく乗ることを固定する（以前は非公開→保存で自動再開していた）。
describe Admin::ListingsService do
  let(:community) { double("community", pre_approved_listings?: false) }
  let(:person) { double("person", has_admin_rights?: true) }
  let(:listing) { double("listing", approved?: true, approval_rejected?: false) }

  def service(params)
    described_class.new(community: community, params: params, person: person)
  end

  def params_with(open_value)
    { id: 1, listing: open_value.nil? ? {} : { open: open_value } }
  end

  it "listing[open]=1 で公開にする" do
    expect(service(params_with("1")).update_by_author_params(listing)).to include(open: true)
  end

  it "listing[open]=0 で非公開にする" do
    expect(service(params_with("0")).update_by_author_params(listing)).to include(open: false)
  end

  it "open パラメータが無ければ公開状態を変えない" do
    expect(service(params_with(nil)).update_by_author_params(listing)).not_to have_key(:open)
  end

  it "事前承認コミュニティでは承認待ち状態を保ったまま open を反映する" do
    pre_approved = double("community", pre_approved_listings?: true)
    non_admin = double("person", has_admin_rights?: false)
    svc = described_class.new(community: pre_approved, params: params_with("0"), person: non_admin)

    result = svc.update_by_author_params(listing)

    expect(result[:open]).to be(false)
    expect(result[:state]).to eq(Listing::APPROVAL_PENDING)
  end
end
