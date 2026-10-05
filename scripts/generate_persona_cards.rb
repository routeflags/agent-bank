# frozen_string_literal: true

# Generates branded persona card images (designs/design.md §8-2 ギャップ対応)
# and attaches them to the seeded AI persona listings.
#
# Palette per designs/design.md §2:
#   gold #D4A843 / dark gold #B8922E / light gold #F5E6B8
#   background #0D0D0D / card #1A1A1A / border #2A2A2A / sub text #999999
#
# Run: bundle exec rails runner scripts/generate_persona_cards.rb
#
# Output PNGs land in tmp/persona_cards/ (source), Paperclip stores the
# processed styles under public/system/listing_images (gitignored).

FONT = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
OUT_DIR = Rails.root.join("tmp/persona_cards").freeze

PERSONAS = [
  { listing_id: 14, name: "さくら",     glyph: "さ", category: "文章・ライティング" },
  { listing_id: 15, name: "コード太郎", glyph: "コ", category: "開発・コード生成" },
  { listing_id: 16, name: "みずたま",   glyph: "み", category: "日英翻訳" },
  { listing_id: 17, name: "はなこ",     glyph: "は", category: "カスタマーサポート" },
  { listing_id: 18, name: "ゆき",       glyph: "ゆ", category: "ロールプレイ会話" },
  { listing_id: 19, name: "けんじ",     glyph: "け", category: "データ分析" }
].freeze

def generate_card(persona)
  path = OUT_DIR.join("#{persona[:listing_id]}.png").to_s

  # 1200x800 (3:2) — Paperclip center-crops to all styles
  system(
    "magick", "-size", "1200x800", "gradient:#0D0D0D-#151515",
    "-font", FONT,
    # gold frame
    "-fill", "none", "-stroke", "#D4A843", "-strokewidth", "8",
    "-draw", "rectangle 18,18 1182,782",
    "-stroke", "#2A2A2A", "-strokewidth", "2",
    "-draw", "rectangle 38,38 1162,762",
    # emblem circle
    "-stroke", "#D4A843", "-strokewidth", "6",
    "-draw", "circle 600,290 600,150",
    # glyph inside emblem
    "-fill", "#F5E6B8", "-pointsize", "170",
    "-gravity", "Center", "-annotate", "+0-112", persona[:glyph],
    # persona name
    "-fill", "#FFFFFF", "-pointsize", "76",
    "-gravity", "Center", "-annotate", "+0+150", persona[:name],
    # category caption
    "-fill", "#999999", "-pointsize", "40",
    "-gravity", "Center", "-annotate", "+0+255", persona[:category],
    path
  ) or raise "ImageMagick failed for #{persona[:name]}"

  path
end

FileUtils.mkdir_p(OUT_DIR)

PERSONAS.each do |persona|
  listing = Listing.find_by(id: persona[:listing_id])
  if listing.nil?
    puts "SKIP listing #{persona[:listing_id]} (not found)"
    next
  end

  if listing.listing_images.exists?
    puts "SKIP listing #{persona[:listing_id]} (image already attached)"
    next
  end

  png = generate_card(persona)
  image = ListingImage.new(listing: listing)
  image.image = File.open(png)
  image.save!

  # Direct attachments bypass ListingImagesController, which normally sets
  # image_downloaded = true. Without it, image_ready? stays false and the
  # search converters filter the image out of cards.
  image.update_columns(image_downloaded: true, width: 1536, height: 1024)

  puts "OK listing #{persona[:listing_id]} (#{persona[:name]}): " \
       "small_3x2=#{image.image.url(:small_3x2)} ready=#{image.reload.image_ready?}"
end

puts "Done. #{ListingImage.count} listing images total."
