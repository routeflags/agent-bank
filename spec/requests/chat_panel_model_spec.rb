# frozen_string_literal: true

require "rails_helper"

# ChatPanel の「実行設定 > モデル」に渡す props（Issue #139）。
#
# 画面のモデルはサーバーが実際に解決・課金するモデル（listing_ai_models の
# is_default、Ai::ProviderFactory と同じ行）でなければならない。
# 以前はクライアント側に 'gpt-4o' が直書きされていて、モデル一覧の先頭や
# 古い既定を表示していた。ここでは props が DB の既定に追従することを見る。
describe "Chat panel model props", type: :request do
  before do
    skip "webpack ビルド成果物（app/assets/webpack）が無いため" unless webpack_assets_available?
  end

  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
    ActionController::Base.allow_forgery_protection = original
  end

  let(:domain) { "chat-model-#{rand(1_000_000)}.custom.org" }
  let(:community) do
    FactoryBot.create(:community, domain: domain, use_domain: true,
                                  settings: { "locales" => %w[ja] })
  end
  let(:author) do
    FactoryBot.create(:person, username: "modelauthor#{rand(10_000)}",
                               community_id: community.id, member_of: community)
  end
  let(:listing) do
    FactoryBot.create(:listing, community_id: community.id, author: author,
                                default_run_mode: "run_online")
  end
  let(:provider) { FactoryBot.create(:ai_provider, slug: "openai") }

  # モデル一覧の先頭（＝以前画面に出ていた既定でないモデル）
  let!(:first_model) do
    FactoryBot.create(:ai_model, ai_provider: provider, name: "GPT-4o",
                                 slug: "gpt-4o", model_id: "gpt-4o",
                                 cost_per_1k_input: 0.0025, cost_per_1k_output: 0.01)
  end
  # 出品の既定（listing_ai_models.is_default = true）
  let!(:default_model) do
    FactoryBot.create(:ai_model, ai_provider: provider, name: "GPT-4o Mini",
                                 slug: "gpt-4o-mini", model_id: "gpt-4o-mini",
                                 cost_per_1k_input: 0.00015, cost_per_1k_output: 0.0006)
  end

  # 出品作成時の after_save（PersonaDefaults.ensure_default_ai_model!）が
  # GPT-4o Mini を既定として付ける。画面のモデルはその行を読む。
  def show_listing
    get "http://#{domain}/ja/listings/#{listing.id}"
    expect(response.status).to eq(200), "listing show が #{response.status} で失敗"
  end

  it "出品の既定モデル（is_default）を props で渡す" do
    show_listing

    expect(listing.listing_ai_models.defaults.first.ai_model).to eq(default_model)
    expect(response.body).to include('"model":{"name":"GPT-4o Mini"')
    expect(response.body).not_to include('"name":"GPT-4o"')
  end

  it "単価を 100 万トークンあたりの USD で渡す" do
    show_listing

    expect(response.body).to include('"input_price_per_million":"0.15"')
    expect(response.body).to include('"output_price_per_million":"0.60"')
  end

  it "既定を切り替えると props もそのモデルになる（クライアント側の直書きが無い）" do
    listing.listing_ai_models.defaults.first.update!(ai_model: first_model)

    show_listing

    expect(response.body).to include('"model":{"name":"GPT-4o"')
    expect(response.body).to include('"input_price_per_million":"2.50"')
  end

  it "既定が未設定ならモデル無しで描画する（画面は「未設定」）" do
    listing.listing_ai_models.destroy_all

    show_listing

    expect(response.body).to include('"model":null')
  end
end
