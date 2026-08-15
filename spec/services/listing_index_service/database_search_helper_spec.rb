# frozen_string_literal: true

require 'spec_helper'

describe ListingIndexService::Search::DatabaseSearchHelper do

  describe '.needs_search?' do
    it 'returns true when keywords are present' do
      search = { keywords: 'test' }
      expect(described_class.needs_search?(search)).to be true
    end

    it 'returns false when no search params are present' do
      search = {}
      expect(described_class.needs_search?(search)).to be false
    end

    # Persona-related params are handled by the DB query path,
    # so they should NOT trigger a Sphinx search.
    it 'returns false when only run_mode is present' do
      search = { run_mode: 'run_online' }
      expect(described_class.needs_search?(search)).to be false
    end

    it 'returns false when only ai_model_id is present' do
      search = { ai_model_id: 1 }
      expect(described_class.needs_search?(search)).to be false
    end

    it 'returns false when only has_persona is present' do
      search = { has_persona: true }
      expect(described_class.needs_search?(search)).to be false
    end

    it 'returns true when keywords and run_mode are both present' do
      search = { keywords: 'test', run_mode: 'run_online' }
      expect(described_class.needs_search?(search)).to be true
    end

    it 'returns false when has_persona is false' do
      search = { has_persona: false }
      expect(described_class.needs_search?(search)).to be false
    end

    it 'returns false when ai_model_id is blank' do
      search = { ai_model_id: '' }
      expect(described_class.needs_search?(search)).to be false
    end
  end

  describe '.fetch_from_db with persona filters' do
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

    let(:base_search) do
      {
        per_page: 20,
        page: 1,
        include_closed: true
      }
    end

    context 'with run_mode filter' do
      it 'returns only run_online listings when run_mode is run_online' do
        search = base_search.merge(run_mode: 'run_online')
        result = described_class.fetch_from_db(
          community_id: community.id,
          search: search,
          included_models: [],
          includes: nil
        )
        listing_ids = result.data[:listings].map { |l| l[:id] }
        expect(listing_ids).to include(run_online_listing.id)
        expect(listing_ids).not_to include(download_listing.id)
        expect(listing_ids).not_to include(no_persona_listing.id)
      end

      it 'returns only download listings when run_mode is download' do
        search = base_search.merge(run_mode: 'download')
        result = described_class.fetch_from_db(
          community_id: community.id,
          search: search,
          included_models: [],
          includes: nil
        )
        listing_ids = result.data[:listings].map { |l| l[:id] }
        expect(listing_ids).to include(download_listing.id)
        expect(listing_ids).not_to include(run_online_listing.id)
        expect(listing_ids).not_to include(no_persona_listing.id)
      end
    end

    context 'with has_persona filter' do
      it 'returns only persona listings when has_persona is true' do
        search = base_search.merge(has_persona: true)
        result = described_class.fetch_from_db(
          community_id: community.id,
          search: search,
          included_models: [],
          includes: nil
        )
        listing_ids = result.data[:listings].map { |l| l[:id] }
        expect(listing_ids).to include(run_online_listing.id)
        expect(listing_ids).to include(download_listing.id)
        expect(listing_ids).not_to include(no_persona_listing.id)
      end
    end

    context 'with ai_model_id filter' do
      let!(:ai_model) { FactoryBot.create(:ai_model, ai_provider: FactoryBot.create(:ai_provider)) }

      before do
        FactoryBot.create(:listing_ai_model, listing: run_online_listing, ai_model: ai_model)
      end

      it 'returns only listings with the specified AI model' do
        search = base_search.merge(ai_model_id: ai_model.id)
        result = described_class.fetch_from_db(
          community_id: community.id,
          search: search,
          included_models: [],
          includes: nil
        )
        listing_ids = result.data[:listings].map { |l| l[:id] }
        expect(listing_ids).to include(run_online_listing.id)
        expect(listing_ids).not_to include(download_listing.id)
        expect(listing_ids).not_to include(no_persona_listing.id)
      end
    end

    context 'without persona filters' do
      it 'returns all listings regardless of run_mode' do
        search = base_search
        result = described_class.fetch_from_db(
          community_id: community.id,
          search: search,
          included_models: [],
          includes: nil
        )
        listing_ids = result.data[:listings].map { |l| l[:id] }
        expect(listing_ids).to include(run_online_listing.id)
        expect(listing_ids).to include(download_listing.id)
        expect(listing_ids).to include(no_persona_listing.id)
      end
    end
  end
end
