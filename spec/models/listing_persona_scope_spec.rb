# frozen_string_literal: true

require 'spec_helper'

describe Listing, 'AI Persona search scopes', type: :model do
  let!(:community) { FactoryBot.create(:community) }
  let!(:listing_shape) { FactoryBot.create(:listing_shape, community_id: community.id) }

  let!(:run_online_listing) do
    FactoryBot.create(:listing,
      community_id: community.id,
      listing_shape_id: listing_shape.id,
      default_run_mode: 'run_online')
  end

  let!(:download_listing) do
    FactoryBot.create(:listing,
      community_id: community.id,
      listing_shape_id: listing_shape.id,
      default_run_mode: 'download')
  end

  let!(:no_persona_listing) do
    FactoryBot.create(:listing,
      community_id: community.id,
      listing_shape_id: listing_shape.id,
      default_run_mode: nil)
  end

  describe '.run_online' do
    it 'returns only listings with default_run_mode == run_online' do
      results = Listing.run_online
      expect(results).to include(run_online_listing)
      expect(results).not_to include(download_listing)
      expect(results).not_to include(no_persona_listing)
    end
  end

  describe '.download_mode' do
    it 'returns only listings with default_run_mode == download' do
      results = Listing.download_mode
      expect(results).to include(download_listing)
      expect(results).not_to include(run_online_listing)
      expect(results).not_to include(no_persona_listing)
    end
  end

  describe '.free_mode' do
    let!(:free_listing) do
      FactoryBot.create(:listing,
        community_id: community.id,
        listing_shape_id: listing_shape.id,
        default_run_mode: 'free')
    end

    it 'returns only listings with default_run_mode == free' do
      results = Listing.free_mode
      expect(results).to include(free_listing)
      expect(results).not_to include(run_online_listing)
      expect(results).not_to include(download_listing)
      expect(results).not_to include(no_persona_listing)
    end
  end

  describe '.with_ai_model' do
    let!(:ai_model) { FactoryBot.create(:ai_model, ai_provider: FactoryBot.create(:ai_provider)) }
    let!(:other_ai_model) { FactoryBot.create(:ai_model, ai_provider: FactoryBot.create(:ai_provider), slug: 'gpt-3', model_id: 'gpt-3') }

    before do
      FactoryBot.create(:listing_ai_model, listing: run_online_listing, ai_model: ai_model)
      FactoryBot.create(:listing_ai_model, listing: download_listing, ai_model: other_ai_model)
    end

    it 'returns only listings associated with the specified AI model' do
      results = Listing.with_ai_model(ai_model.id)
      expect(results).to include(run_online_listing)
      expect(results).not_to include(download_listing)
      expect(results).not_to include(no_persona_listing)
    end
  end

  describe '.persona_only' do
    it 'returns only listings with a non-blank default_run_mode' do
      results = Listing.persona_only
      expect(results).to include(run_online_listing)
      expect(results).to include(download_listing)
      expect(results).not_to include(no_persona_listing)
    end
  end

  describe 'combined scopes' do
    let!(:free_listing) do
      FactoryBot.create(:listing,
        community_id: community.id,
        listing_shape_id: listing_shape.id,
        default_run_mode: 'free')
    end

    it 'persona_only excludes free mode listings too when filtering by run_online' do
      results = Listing.persona_only.run_online
      expect(results).to include(run_online_listing)
      expect(results).not_to include(free_listing)
      expect(results).not_to include(no_persona_listing)
    end

    it 'persona_only excludes free mode listings too when filtering by download' do
      results = Listing.persona_only.download_mode
      expect(results).to include(download_listing)
      expect(results).not_to include(free_listing)
      expect(results).not_to include(no_persona_listing)
    end
  end
end
