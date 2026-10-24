# frozen_string_literal: true

require "spec_helper"

# Issue #11 / #12: 出品フォームから「AI実行モード」と「場所」の入力欄を外す。
#
# フォーム全体を描画するリクエストスペックは Sharetribe のセッションストア
# 依存で不安定なため、テンプレート構造の契約として検証する。サーバー側の
# 既定値（default_run_mode = run_online）は
# spec/view_utils/listing_form_view_utils_spec.rb で担保している。
RSpec.describe "出品フォームの入力欄", type: :view do
  let(:form_content) do
    Rails.root.join("app/views/listings/form/_form_content.haml").read
  end

  it "AI実行モードの選択欄を描画しない" do
    expect(form_content).not_to include("listings/form/run_mode")
  end

  it "場所の入力欄を描画しない" do
    expect(form_content).not_to include("listings/form/origin")
    expect(form_content).not_to include("show_location?")
  end
end
