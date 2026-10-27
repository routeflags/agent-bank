# frozen_string_literal: true

# 「出力の長さ」設定が実際の回答長に効いているかを実 API で測る（Issue #102）。
#
# 同一ペルソナ・同一プロンプトで output_length だけを変えて呼び、文字数・
# トークン数・finish_reason を比較する。外部 API を叩いて課金が発生するので、
# 明示的に実行したときだけ走る。
#
#   LISTING_ID=23 bin/rails runner script/measure_output_length.rb
#   LISTING_ID=23 LENGTHS=short,standard,long PROMPT="..." bin/rails runner script/measure_output_length.rb
#
# セッションは保存しない（DB に履歴を残さない）。
listing_id = Integer(ENV.fetch("LISTING_ID", "23"))
lengths = (ENV["LENGTHS"] || "short,long").split(",").map(&:strip)
prompt = ENV["PROMPT"] || "AIペルソナとして、あなたが得意なことと、それをどう活かせるかを説明してください。"
max_tokens = Integer(ENV.fetch("MAX_TOKENS", "4000"))

listing = Listing.find(listing_id)
puts "listing=##{listing.id} #{listing.title} (#{listing.price_cents}円 / 100万トークン)"
puts "prompt=#{prompt}"
puts "max_tokens=#{max_tokens}"

results = lengths.map do |length|
  session = ChatSession.new(listing: listing)
  messages = Ai::ChatCompletionsBuilder.new(session, { "output_length" => length, "tone" => "polite" }).build
  messages << { role: "user", content: prompt }

  adapter = Ai::ProviderFactory.for(listing)
  started = Time.now
  usage = adapter.stream(messages, max_tokens: max_tokens) { |_chunk| }
  elapsed = Time.now - started

  {
    length: length,
    system_chars: messages.first[:content].to_s.length,
    chars: adapter.accumulated_content.to_s.length,
    output_tokens: usage.output_tokens,
    input_tokens: usage.input_tokens,
    finish: adapter.last_finish_reason,
    sec: elapsed,
    content: adapter.accumulated_content.to_s
  }
end

puts ""
puts format("%-9s %-7s %-7s %-8s %-6s %s", "length", "system", "chars", "out_tok", "sec", "finish")
results.each do |r|
  puts format("%-9s %-7d %-7d %-8d %-6.1f %s", r[:length], r[:system_chars], r[:chars], r[:output_tokens], r[:sec], r[:finish])
end
results.each do |r|
  puts "\n--- #{r[:length]} (#{r[:chars]}字 / #{r[:output_tokens]}トークン) ---"
  puts r[:content].empty? ? "(空)" : r[:content]
end
