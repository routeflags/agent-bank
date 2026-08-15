module ListingIndexService::Search::Converters
  module_function

  def listing_hash(l, includes, meta={})
    base = {
      id: l.id,
      title: l.title,
      description: l.description,
      updated_at: l.updated_at,
      created_at: l.created_at,
      # category_id が nil の listing が存在する場合に備え、デフォルト値 0 を設定。
      # EntityUtils::EntityBuilder が必須値として検証するため、nil のまま放置すると 500 エラーになる。
      category_id: l.category_id || 0,
      comment_count: l.comments_count,
      price: l.price,
      unit_tr_key: l.unit_tr_key,
      unit_type: l.unit_type,
      quantity: l.quantity,
      shape_name_tr_key: l.shape_name_tr_key,
      listing_shape_id: l.listing_shape_id
    }

    # Include persona card when the listing has a default_run_mode set,
    # indicating it is an AI Persona listing.
    if l.respond_to?(:default_run_mode) && l.default_run_mode.present?
      base[:persona_card] = l.persona_card
    end

    base.merge(meta)
        .merge(location_hash(l, includes))
        .merge(author_hash(l, includes))
        .merge(listing_images_hash(l, includes))
  end

  def location_hash(l, includes)
    if includes.include?(:location)
      m_location = Maybe(l.location)
      {
        latitude: m_location.latitude.or_else(nil),
        longitude: m_location.longitude.or_else(nil),
        address: m_location.address.or_else(nil)
      }
    else
      {}
    end
  end

  def author_hash(l, includes)
      if includes.include?(:num_of_reviews) || includes.include?(:author)
        {
          author: {
            id: l.author_id,
            username: l.author.username,
            first_name: l.author.given_name,
            last_name: l.author.family_name,
            display_name: l.author.display_name,
            avatar: {
              thumb: l.author.image.present? ? l.author.image.url(:thumb) : nil
            },
            is_deleted: l.author.deleted?,
            is_banned: l.author.banned?
          }.merge(num_of_reviews_hash(l, includes))
        }
      else
        {}
      end
  end

  def num_of_reviews_hash(l, includes)
    if includes.include?(:num_of_reviews)
      {num_of_reviews: l.author.received_testimonials.size}
    else
      {}
    end

  end

  def listing_images_hash(l, includes)
      if includes.include?(:listing_images)
        {
          listing_images: Maybe(l.listing_images.first)
            .select { |li| li.image_ready? } # Filter images that are not processed
            .map { |li|
              [{
                thumb: li.image.url(:thumb),
                small_3x2: li.image.url(:small_3x2),
                medium: li.image.url(:medium)
              }]
            }.or_else([])
        }
      else
        {}
      end
  end
end

