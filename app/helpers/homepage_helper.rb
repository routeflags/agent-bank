module HomepageHelper
  # カードに表示するカテゴリ名。表示名マップが無い場合（描画テスト等）は nil。
  # マップは呼び出し側（ビュー）のインスタンス変数から渡す。
  def persona_category_name(listing, category_names)
    return nil unless category_names && listing.respond_to?(:category_id) && listing.category_id

    category_names[listing.category_id]
  end
  # ── カテゴリビジュアルの単一の定義（Issue #117） ─────────────
  # 「色ブロック＋英字ラベル＋絵文字」の対応表はこの2定数だけに持つ。
  # 出品詳細（listings/show）は listing_category_visual の呼び出しで供給を
  # 受け、テンプレート側に色・英字・絵文字の定義を二重に持たない。
  # トップ（homepage 配下）も将来ここを参照する想定のため、新しい対応の
  # 追加はこの表への1行追加で行う。
  #
  # 色は装飾ブロック用の8色パレット。c0/c1 は Issue #117 指定の Gold
  # #dfb560・赤 #ec1029、c2 は既存トークン --accent-teal と同値。
  # UI クローム（CTA・選択状態・枠線の強調）自体は既存トークン
  # （--accent-gold #d4a853 / --accent-red #c41e3a）のまま変えない。
  CATEGORY_VISUAL_COLORS = %w[
    #dfb560 #ec1029 #59b3a2 #8e7cc3
    #5b9bd5 #7ac74f #e8833a #d66ba0
  ].freeze

  # アイコン名（Category#icon）→ 絵文字。未登録のアイコンは 🤖 に倒す。
  CATEGORY_VISUAL_EMOJI = {
    "text" => "📝", "edit" => "✍️", "code" => "💻", "language" => "🌐",
    "summary" => "📋", "chat" => "💬", "support" => "🎧", "roleplay" => "🎭",
    "image" => "🖼️", "art" => "🎨", "photo" => "📷", "video" => "🎬",
    "audio" => "🔊", "tts" => "🗣️", "stt" => "🎙️", "music" => "🎵",
    "data" => "📊", "research" => "🔍", "productivity" => "⚡",
    "email" => "✉️", "notes" => "📓", "education" => "🎓", "tutor" => "👩‍🏫",
    "item" => "📦", "favor" => "🤝", "rideshare" => "🚗", "housing" => "🏠",
    "tools" => "🛠️", "sports" => "⚽", "books" => "📚", "games" => "🎮",
    "furniture" => "🛋️", "outdoors" => "🏕️", "food" => "🍱",
    "electronics" => "🔌", "pets" => "🐾", "film" => "🎬", "clothes" => "👕",
    "garden" => "🌱", "travel" => "✈️", "other" => "🗂️"
  }.freeze

  CATEGORY_VISUAL_DEFAULT_EMOJI = "🤖".freeze
  CATEGORY_VISUAL_FALLBACK_LABEL = "PERSONA".freeze

  # カテゴリ名から引くフォールバック表（Category を持たない一覧 struct 用）。
  # 表示名だけで色・英字・絵文字を決めたい場面（トップのカード等）で使う。
  # 定義はここ1か所だけに持ち、テンプレート側に直書きしない。
  CATEGORY_VISUAL_NAME_KEYWORDS = [
    { match: "生成AI", word: "GENAI", emoji: "✧" },
    { match: "データ", word: "DATA", emoji: "▥" },
    { match: "開発", word: "DEV", emoji: "⌘" },
    { match: "マーケティング", word: "MARKETING", emoji: "➤" },
    { match: "デザイン", word: "DESIGN", emoji: "✎" },
    { match: "自動化", word: "AUTO", emoji: "⚙" },
    { match: "教育", word: "EDU", emoji: "◇" },
    { match: "学習", word: "EDU", emoji: "◇" },
    { match: "チャット", word: "CHAT", emoji: "💬" },
    { match: "会話", word: "CHAT", emoji: "💬" },
    { match: "リサーチ", word: "RESEARCH", emoji: "⌕" }
  ].freeze

  # 出品のカテゴリビジュアル（色・英字ラベル・絵文字・表示名）を返す。
  # サブカテゴリの出品でも上位カテゴリに寄せて、同じカテゴリの色を揃える。
  # 一覧の struct（ListingIndexViewUtils::ListingItem）は Category を持たない
  # ため、その場合はカテゴリ表示名から決める（同じ表を使う）。
  def listing_category_visual(listing, category_names = nil)
    category = listing.respond_to?(:category) ? listing.category : nil
    return category_visual(category) if category

    category_visual_from_name(persona_category_name(listing, category_names))
  end

  # カテゴリ表示名から色・英字ラベル・絵文字を決める。
  def category_visual_from_name(name)
    entry = CATEGORY_VISUAL_NAME_KEYWORDS.find { |e| name.to_s.include?(e[:match]) }
    index = name.present? ? name.to_s.each_byte.sum % CATEGORY_VISUAL_COLORS.size : 0
    {
      color: CATEGORY_VISUAL_COLORS[index],
      color_index: index,
      emoji: entry ? entry[:emoji] : CATEGORY_VISUAL_DEFAULT_EMOJI,
      english_label: entry ? entry[:word] : CATEGORY_VISUAL_FALLBACK_LABEL,
      name: name
    }
  end

  def category_visual(category)
    top = top_level_category(category)
    return fallback_visual if top.nil?

    index = visual_color_index(top)
    {
      color: CATEGORY_VISUAL_COLORS[index],
      color_index: index,
      emoji: CATEGORY_VISUAL_EMOJI.fetch(top.icon.to_s, CATEGORY_VISUAL_DEFAULT_EMOJI),
      english_label: visual_english_label(top),
      name: top.display_name(I18n.locale)
    }
  end

  def show_subcategory_list(category, current_category_id)
    category.id == current_category_id || category.children.any? do |child_category|
      child_category.id == current_category_id
    end
  end

  def with_first_listing_image(listing, &block)
    Maybe(listing)
      .listing_images
      .map { |images| images.first }[:medium].each { |url|
      block.call(url)
    }
  end

  def without_listing_image(listing, &block)
    if listing.listing_images.size == 0
      block.call
    end
  end

  def format_distance(distance)
    precision = (distance < 1) ? 1 : 2
    (distance < 0.1) ? "< #{number_with_delimiter(0.1, locale: locale)}" : number_with_precision(distance, precision: precision, significant: true, locale: locale)
  end

  private

  # カテゴリ階層をたどって上位カテゴリを返す。nil はそのまま返す。
  def top_level_category(category)
    current = category
    # 深さ制限つきで親をたどる（循環参照の保険）。
    10.times do
      parent = current&.parent
      break if parent.nil?

      current = parent
    end
    current
  end

  # 上位カテゴリの url から決定的にパレット位置を決める。
  # ID 依存にしないため、環境やシード順が違っても同じカテゴリは同じ色になる。
  def visual_color_index(top_category)
    key = top_category.url.to_s
    key = top_category.icon.to_s if key.empty?
    key.bytes.sum % CATEGORY_VISUAL_COLORS.size
  end

  # 英字ラベルは url スラッグ由来（常に ASCII）。空のときだけフォールバック。
  def visual_english_label(top_category)
    label = top_category.url.to_s.tr("-_", " ").split.join(" ").upcase
    label.empty? ? CATEGORY_VISUAL_FALLBACK_LABEL : label
  end

  def fallback_visual
    {
      color: CATEGORY_VISUAL_COLORS[0],
      color_index: 0,
      emoji: CATEGORY_VISUAL_DEFAULT_EMOJI,
      english_label: CATEGORY_VISUAL_FALLBACK_LABEL,
      name: ""
    }
  end
end