require 'spec_helper'

describe HomepageController, type: :controller do
  render_views

  let(:plan) do
    {
      expired: false,
      features: {
        whitelabel: true,
        admin_email: true,
        footer: false
      },
      created_at: Time.zone.now,
      updated_at: Time.zone.now
    }
  end

  describe "title and description" do
    before(:each) do
      @community = FactoryBot.create(:community)
      @request.host = "#{@community.ident}.lvh.me"
      @request.env[:current_marketplace] = @community
      @request.env[:current_plan] = plan
      @user = create_admin_for(@community)
      @user.update(is_admin: true)
      sign_in_for_spec(@user)
    end

    describe "#index" do
      # Nothing in SEO for Homepage/CLP, nothing in Social Media
      # <title>: the default value
      # <meta description>: the default value
      # <og:title> and <twitter:title>: the default value
      # <og:description> and <twitter:description>: the default value
      it "renders default title and description" do
        get :index
        doc = Nokogiri::HTML(response.body)
        expect(doc.at('title')&.text).to eq('Sharetribe - Test slogan')
        expect(doc.at("meta[name='description']")&.[]('content')).to eq('Test description - Test slogan')
        expect(doc.at("meta[property='og:title']")&.[]('content')).to eq('Sharetribe - Test slogan')
        expect(doc.at("meta[name='twitter:title']")&.[]('content')).to eq('Sharetribe - Test slogan')
        expect(doc.at("meta[property='og:description']")&.[]('content')).to eq('Test description - Test slogan')
        expect(doc.at("meta[name='twitter:description']")&.[]('content')).to eq('Test description - Test slogan')
      end

      # Something in SEO for Homepage/CLP, nothing in Social Media
      # <title>: the SEO value
      # <meta description>: the SEO value
      # <og:title> and <twitter:title>: the default value
      # <og:description> and <twitter:description>: the default value
      it "renders updated meta title and description" do
        @community.community_customizations.first.update(meta_title: "SEO Title", meta_description: "SEO Description")
        get :index
        doc = Nokogiri::HTML(response.body)
        expect(doc.at('title')&.text).to eq('SEO Title')
        expect(doc.at("meta[name='description']")&.[]('content')).to eq('SEO Description')
        expect(doc.at("meta[property='og:title']")&.[]('content')).to eq('Sharetribe - Test slogan')
        expect(doc.at("meta[name='twitter:title']")&.[]('content')).to eq('Sharetribe - Test slogan')
        expect(doc.at("meta[property='og:description']")&.[]('content')).to eq('Test description - Test slogan')
        expect(doc.at("meta[name='twitter:description']")&.[]('content')).to eq('Test description - Test slogan')
      end

      # Nothing in SEO for Homepage/CLP, something in Social Media
      # <title>: the default
      # <meta description>: the default
      # <og:title> and <twitter:title>: the Social Media value
      # <og:description> and <twitter:description>: the Social Media value
      it 'renders updated meta title and description' do
        @community.community_customizations.first.update(social_media_title: 'Social Title', social_media_description: 'Social Description')
        get :index
        doc = Nokogiri::HTML(response.body)
        expect(doc.at('title')&.text).to eq('Sharetribe - Test slogan')
        expect(doc.at("meta[name='description']")&.[]('content')).to eq('Test description - Test slogan')
        expect(doc.at("meta[property='og:title']")&.[]('content')).to eq('Social Title')
        expect(doc.at("meta[name='twitter:title']")&.[]('content')).to eq('Social Title')
        expect(doc.at("meta[property='og:description']")&.[]('content')).to eq('Social Description')
        expect(doc.at("meta[name='twitter:description']")&.[]('content')).to eq('Social Description')
      end

      # Something in SEO for Homepage/CLP, something in Social Media
      # <title>: the SEO value
      # <meta description>: the SEO value
      # <og:title> and <twitter:title>: the Social Media value
      # <og:description> and <twitter:description>: the Social Media value
      it 'renders updated meta title and description' do
        @community.community_customizations.first.update(
          meta_title: 'SEO Title', meta_description: 'SEO Description',
          social_media_title: 'Social Title', social_media_description: 'Social Description')
        get :index
        doc = Nokogiri::HTML(response.body)
        expect(doc.at('title')&.text).to eq('SEO Title')
        expect(doc.at("meta[name='description']")&.[]('content')).to eq('SEO Description')
        expect(doc.at("meta[property='og:title']")&.[]('content')).to eq('Social Title')
        expect(doc.at("meta[name='twitter:title']")&.[]('content')).to eq('Social Title')
        expect(doc.at("meta[property='og:description']")&.[]('content')).to eq('Social Description')
        expect(doc.at("meta[name='twitter:description']")&.[]('content')).to eq('Social Description')
      end

      it "renders updated meta title and description when search params are provided" do
        @community.community_customizations.first.update(search_meta_title: "Search results for {{keywords_searched}}", search_meta_description: "Search results for {{keywords_searched}} at {{location_searched}}")
        get :index, params: {q: 'books', lq: 'New York'}
        doc = Nokogiri::HTML(response.body)
        expect(doc.at('title')&.text).to eq('Search results for books')
        expect(doc.at("meta[name='description']")&.[]('content')).to eq('Search results for books at New York')
      end

      it "renders updated meta title and description when search by category is used" do
        @community.community_customizations.first.update(category_meta_title: "Search results for {{category_name}}", category_meta_description: "Search results for category {{category_name}}")
        @category = FactoryBot.create(:category, :community => @community)
        @category.translation_attributes = {en: {name: "Test Category"}}
        @category.save
        get :index, params: {category: @category.url}
        category_name = @category.display_name(I18n.locale)
        doc = Nokogiri::HTML(response.body)
        expect(doc.at('title')&.text).to eq("Search results for #{category_name}")
        expect(doc.at("meta[name='description']")&.[]('content')).to eq("Search results for category #{category_name}")
      end
    end
  end

  describe '#index' do
    let(:community) { FactoryBot.create(:community) }

    before(:each) do
      @request.env["devise.mapping"] = Devise.mappings[:person]
      @request.host = "#{community.ident}.lvh.me"
      @request.env[:current_marketplace] = community
    end

    let(:listing) { FactoryBot.create(:listing, community_id: community.id) }
    let(:pending_listing) do
      FactoryBot.create(:listing, community_id: community.id,
                                  state: Listing::APPROVAL_PENDING)
    end

    it 'shows approved listing' do
      listing
      get :index
      listings = assigns(:listings)
      expect(listings.count).to eq 1
    end

    it 'does not show pending listing' do
      pending_listing
      get :index
      listings = assigns(:listings)
      expect(listings.count).to eq 0
    end

    # Issue #26: SEO 用の prev/next も一覧ページ/トップの切り替えルール
    # （raku_listing_index_path）経由で組み立てること。
    describe 'seo pagination links の遷移先' do
      it '/browse 表示時は /browse 基準の prev/next を返す' do
        get :index
        controller.instance_variable_set(:@listing_page, true)

        links = controller.send(:seo_pagination_links, { 'q' => 'books' }, 2, 3)

        # ロケール接頭辞（default_url_options 由来）の有無は環境依存なので問わない。
        # 大切なのはトップ（/）へ落ちず /browse 基準で組み立てること。
        expect(links[:prev]).to match(%r{\A/(?:[a-z-]+/)?browse\?})
        expect(links[:prev]).to include('q=books')
        expect(links[:prev]).to include('page=1')
        expect(links[:next]).to match(%r{\A/(?:[a-z-]+/)?browse\?})
        expect(links[:next]).to include('page=3')
        expect(links[:next]).not_to include('locale=')
      end

      it 'トップ表示時は従来どおりトップ基準の prev/next を返す' do
        get :index

        links = controller.send(:seo_pagination_links, { 'q' => 'books' }, 1, 2)

        expect(links[:prev]).to be_nil
        expect(links[:next]).to start_with('/?')
        expect(links[:next]).to include('q=books')
        expect(links[:next]).to include('page=2')
        expect(links[:next]).not_to include('/browse')
      end
    end
  end
end
