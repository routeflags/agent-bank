module HomepageHelper
  # 楽市楽問 — ペルソナカードの見た目（Issue #111）
  # visual の背景色（--tone）・英字（visual-word）・絵文字はカテゴリの固定表。
  # デザイン正本（rakuichi-rakumon.html）の tone を日本語カテゴリに割り当てたもの。
  # 「リサーチ」は正本のカテゴリに存在するため追加（tone は正本の研究アイテムと同系）。
  # 表に無いカテゴリは既定（末尾）を使う。★・レビュー件数は #106 保留のため持たない。
  PERSONA_CARD_STYLES = [
    { match: "生成AI", tone: "#851b31", word: "GENAI", emoji: "✧" },
    { match: "データ分析", tone: "#176e5c", word: "DATA", emoji: "▥" },
    { match: "開発", tone: "#22579c", word: "DEV", emoji: "⌘" },
    { match: "マーケティング", tone: "#a06b13", word: "MARKETING", emoji: "➤" },
    { match: "デザイン", tone: "#aa267f", word: "DESIGN", emoji: "✎" },
    { match: "自動化", tone: "#6b4a12", word: "AUTO", emoji: "⚙" },
    { match: "教育", tone: "#467631", word: "EDU", emoji: "◇" },
    { match: "学習", tone: "#467631", word: "EDU", emoji: "◇" },
    { match: "チャット", tone: "#3c5894", word: "CHAT", emoji: "💬" },
    { match: "会話", tone: "#3c5894", word: "CHAT", emoji: "💬" },
    { match: "リサーチ", tone: "#3c5894", word: "RESEARCH", emoji: "⌕" }
  ].freeze
  PERSONA_CARD_DEFAULT_STYLE = { tone: "#3a3a44", word: "AI", emoji: "🤖" }.freeze

  # カードに表示するカテゴリ名。表示名マップが無い場合（描画テスト等）は nil。
  # マップは呼び出し側（ビュー）のインスタンス変数から渡す。
  def persona_category_name(listing, category_names)
    return nil unless category_names && listing.respond_to?(:category_id) && listing.category_id

    category_names[listing.category_id]
  end

  # カテゴリ名から固定表を引く。見つからなければ既定を返す。
  def persona_card_style(category_name)
    PERSONA_CARD_STYLES.find { |entry| category_name.to_s.include?(entry[:match]) } || PERSONA_CARD_DEFAULT_STYLE
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
end