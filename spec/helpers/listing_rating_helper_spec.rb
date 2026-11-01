# frozen_string_literal: true

require 'spec_helper'

# 検証用の最小 Struct（集計カラムだけを持つ出品相当）。
RatedListing = Struct.new(:avg_rating, :reviews_count)
# 検索結果の ListingIndexViewUtils::ListingItem 相当（集計カラムを持たない）。
ListingItemLike = Struct.new(:id, :title, :avg_rating)

# Issue #106 Phase 2b: 評価表示の判定と整形。
#
# 「評価あり」の判定は reviews_count を正とする（avg_rating > 0 は正規化前の
# 手動値で誤表示するため使わない）。表示形式は「★ 4.2 (3)」、未評価は「—」。
RSpec.describe ListingRatingHelper, type: :helper do
  def with_ja(&block)
    I18n.with_locale(:ja, &block)
  end

  describe '#listing_rated?' do
    it 'reviews_count が 1 以上なら評価あり' do
      expect(helper.listing_rated?(RatedListing.new(4.25, 3))).to be(true)
    end

    it 'reviews_count が 0 なら avg_rating に手動値があっても評価なし' do
      expect(helper.listing_rated?(RatedListing.new(4.5, 0))).to be(false)
    end

    it 'reviews_count を持たないオブジェクトは評価なし（例外にしない）' do
      expect(helper.listing_rated?(ListingItemLike.new(1, 'x', 4.5))).to be(false)
    end

    it 'nil は評価なし' do
      expect(helper.listing_rated?(nil)).to be(false)
    end
  end

  describe '#listing_rating_stars' do
    it '小数 1 桁で丸める（4.25 → ★ 4.3）' do
      expect(with_ja { helper.listing_rating_stars(RatedListing.new(4.25, 3)) }).to eq('★ 4.3')
    end

    it '整数値でも小数 1 桁を落とさない（4.0 → ★ 4.0）' do
      expect(with_ja { helper.listing_rating_stars(RatedListing.new(4.0, 1)) }).to eq('★ 4.0')
    end

    it '未評価は —（★ 0.0 を出さない）' do
      expect(with_ja { helper.listing_rating_stars(RatedListing.new(4.5, 0)) }).to eq('—')
    end
  end

  describe '#listing_rating_count' do
    it '件数を丸括弧で返す' do
      expect(with_ja { helper.listing_rating_count(RatedListing.new(4.25, 3)) }).to eq('(3)')
    end

    it '未評価は nil（呼び出し側が要素ごと出さない）' do
      expect(with_ja { helper.listing_rating_count(RatedListing.new(4.5, 0)) }).to be_nil
    end
  end

  describe '#listing_rating_text' do
    it '評価ありは「★ 4.3 (3)」の 1 行にまとめる' do
      expect(with_ja { helper.listing_rating_text(RatedListing.new(4.25, 3)) }).to eq('★ 4.3 (3)')
    end

    it '未評価は —' do
      expect(with_ja { helper.listing_rating_text(RatedListing.new(0.0, 0)) }).to eq('—')
    end

    it 'ListingItem 相当（reviews_count 無し）でも例外にならない' do
      expect(with_ja { helper.listing_rating_text(ListingItemLike.new(1, 'x', 4.5)) }).to eq('—')
    end

    it 'ListingItem 相当でも事前読み込み値を渡せば評価を出す（一覧カードの経路）' do
      preloaded = { 1 => { avg_rating: 4.25, reviews_count: 3 } }
      item = ListingItemLike.new(1, 'x', 0.0)

      expect(with_ja { helper.listing_rating_text(item, preloaded: preloaded) }).to eq('★ 4.3 (3)')
    end

    it '英語ロケールでも同じ形式で出す' do
      expected = I18n.with_locale(:en) { helper.listing_rating_text(RatedListing.new(4.25, 3)) }
      expect(expected).to eq('★ 4.3 (3)')
    end
  end
end
