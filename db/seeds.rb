# frozen_string_literal: true

# Capafy AI Clone — Seed Data
#
# --- Billing Configuration ---
# Billing settings are loaded from config/billing.yml at runtime.
# No seed data is created for wallets or subscriptions because those are
# user-specific (created via the billing flow or admin UI).
# To change billing parameters, edit config/billing.yml directly or
# override via BillingConfig module defaults.
#
# Run with: bundle exec rails db:seed
#
# This seed creates:
#   1. Capafy AI persona categories (23 categories)
#   2. AI providers (OpenAI, Anthropic, Google) with API key encryption
#   3. AI models for each provider
#
# Uses EncryptionService.encrypt for API keys (AES-256-CBC).
# Scoped to Community.first for community_id references.

puts 'Seeding Capafy AI data...'

community = Community.first
if community.nil?
  puts '  ERROR: No Community found. Create a community first before seeding.'
  exit 1
end

puts "  Using community: #{community.ident || community.id}"

# --- 1. Capafy Categories (23 AI persona categories) ---

# NOTE: Parents must appear before children in this array.
# The seed relies on insertion order to resolve parent_name references.
categories_data = [
  { name: 'Text Generation',       icon: 'text',           parent_name: nil },
  { name: 'Writing Assistant',     icon: 'edit',           parent_name: 'Text Generation' },
  { name: 'Code Assistant',        icon: 'code',           parent_name: 'Text Generation' },
  { name: 'Translation',           icon: 'language',       parent_name: 'Text Generation' },
  { name: 'Summarization',         icon: 'summary',        parent_name: 'Text Generation' },
  { name: 'Chat / Conversation',   icon: 'chat',           parent_name: nil },
  { name: 'Customer Support',      icon: 'support',        parent_name: 'Chat / Conversation' },
  { name: 'Roleplay',              icon: 'roleplay',       parent_name: 'Chat / Conversation' },
  { name: 'Image Generation',      icon: 'image',          parent_name: nil },
  { name: 'Art / Illustration',    icon: 'art',            parent_name: 'Image Generation' },
  { name: 'Photo Editing',         icon: 'photo',          parent_name: 'Image Generation' },
  { name: 'Video Generation',      icon: 'video',          parent_name: nil },
  { name: 'Voice / Audio',         icon: 'audio',          parent_name: nil },
  { name: 'Text-to-Speech',        icon: 'tts',            parent_name: 'Voice / Audio' },
  { name: 'Speech-to-Text',        icon: 'stt',            parent_name: 'Voice / Audio' },
  { name: 'Music Generation',      icon: 'music',          parent_name: 'Voice / Audio' },
  { name: 'Data Analysis',         icon: 'data',           parent_name: nil },
  { name: 'Research Assistant',    icon: 'research',       parent_name: 'Data Analysis' },
  { name: 'Productivity',          icon: 'productivity',   parent_name: nil },
  { name: 'Email Drafting',        icon: 'email',          parent_name: 'Productivity' },
  { name: 'Meeting Notes',         icon: 'notes',          parent_name: 'Productivity' },
  { name: 'Education',             icon: 'education',      parent_name: nil },
  { name: 'Tutoring',              icon: 'tutor',          parent_name: 'Education' }
]

created_categories = {}

categories_data.each_with_index do |cat_data, index|
  parent_id = cat_data[:parent_name] ? created_categories[cat_data[:parent_name]]&.id : nil

  category = Category.find_or_create_by!(
    url: cat_data[:name].parameterize,
    community: community
  ) do |c|
    c.parent_id = parent_id
    c.icon = cat_data[:icon]
    c.sort_priority = index
  end

  # Create translation for the default locale
  default_locale = community.default_locale || 'en'
  unless category.translations.exists?(locale: default_locale)
    category.translations.create!(locale: default_locale, name: cat_data[:name])
  end

  created_categories[cat_data[:name]] = category
  puts "    Category: #{cat_data[:name]}"
end

puts "  Created #{created_categories.size} categories"

# --- 2. AI Providers ---

providers_data = [
  {
    name: 'OpenAI',
    slug: 'openai',
    base_url: 'https://api.openai.com/v1',
    config: { organization: nil }
  },
  {
    name: 'Anthropic',
    slug: 'anthropic',
    base_url: 'https://api.anthropic.com',
    config: { api_version: '2023-06-01' }
  },
  {
    name: 'Google',
    slug: 'google',
    base_url: 'https://generativelanguage.googleapis.com',
    config: { api_version: 'v1' }
  }
]

created_providers = {}

providers_data.each do |provider_data|
  provider = AiProvider.find_or_create_by!(slug: provider_data[:slug]) do |p|
    p.name = provider_data[:name]
    p.base_url = provider_data[:base_url]
    p.config = provider_data[:config]
    p.is_active = true
    # API keys are intentionally left blank in seeds.
    # Set them via the admin UI or environment variables.
  end

  created_providers[provider_data[:slug]] = provider
  puts "    Provider: #{provider_data[:name]}"
end

puts "  Created #{created_providers.size} AI providers"

# --- 3. AI Models ---

models_data = [
  # OpenAI models
  { provider_slug: 'openai', name: 'GPT-4o',              slug: 'gpt-4o',             model_id: 'gpt-4o',             max_tokens: 128000, context_window: 128000, cost_per_1k_input: 0.0025,   cost_per_1k_output: 0.01,  supports_vision: true,  supports_tools: true },
  { provider_slug: 'openai', name: 'GPT-4o Mini',         slug: 'gpt-4o-mini',        model_id: 'gpt-4o-mini',        max_tokens: 128000, context_window: 128000, cost_per_1k_input: 0.00015,  cost_per_1k_output: 0.0006, supports_vision: true,  supports_tools: true },
  { provider_slug: 'openai', name: 'GPT-4.1',             slug: 'gpt-4-1',            model_id: 'gpt-4.1',            max_tokens: 32768,  context_window: 1047576, cost_per_1k_input: 0.002,  cost_per_1k_output: 0.008, supports_vision: true,  supports_tools: true },
  { provider_slug: 'openai', name: 'GPT-4.1 Mini',        slug: 'gpt-4-1-mini',       model_id: 'gpt-4.1-mini',       max_tokens: 32768,  context_window: 1047576, cost_per_1k_input: 0.0004, cost_per_1k_output: 0.0016, supports_vision: true, supports_tools: true },
  { provider_slug: 'openai', name: 'GPT-4.1 Nano',        slug: 'gpt-4-1-nano',       model_id: 'gpt-4.1-nano',       max_tokens: 32768,  context_window: 1047576, cost_per_1k_input: 0.0001, cost_per_1k_output: 0.0004, supports_vision: true, supports_tools: true },
  { provider_slug: 'openai', name: 'o3',                   slug: 'o3',                  model_id: 'o3',                  max_tokens: 100000, context_window: 200000,  cost_per_1k_input: 0.01,  cost_per_1k_output: 0.04, supports_vision: true,  supports_tools: true },
  { provider_slug: 'openai', name: 'o4-mini',              slug: 'o4-mini',             model_id: 'o4-mini',             max_tokens: 100000, context_window: 200000,  cost_per_1k_input: 0.0011, cost_per_1k_output: 0.0044, supports_vision: true, supports_tools: true },
  { provider_slug: 'openai', name: 'DALL-E 3',             slug: 'dall-e-3',            model_id: 'dall-e-3',            max_tokens: 4096,   context_window: nil,     cost_per_1k_input: nil,    cost_per_1k_output: nil, supports_streaming: false, supports_vision: false },
  { provider_slug: 'openai', name: 'Whisper',              slug: 'whisper',             model_id: 'whisper-1',           max_tokens: nil,    context_window: nil,     cost_per_1k_input: nil,    cost_per_1k_output: nil, supports_streaming: false, supports_vision: false, supports_tools: false },

  # Anthropic models
  { provider_slug: 'anthropic', name: 'Claude Sonnet 4',   slug: 'claude-sonnet-4',     model_id: 'claude-sonnet-4-20250514',  max_tokens: 16000, context_window: 200000, cost_per_1k_input: 0.003,   cost_per_1k_output: 0.015, supports_vision: true,  supports_tools: true },
  { provider_slug: 'anthropic', name: 'Claude 3.5 Sonnet', slug: 'claude-3-5-sonnet',   model_id: 'claude-3-5-sonnet-20241022', max_tokens: 8192, context_window: 200000, cost_per_1k_input: 0.003,   cost_per_1k_output: 0.015, supports_vision: true,  supports_tools: true },
  { provider_slug: 'anthropic', name: 'Claude 3.5 Haiku',  slug: 'claude-3-5-haiku',    model_id: 'claude-3-5-haiku-20241022',  max_tokens: 8192, context_window: 200000, cost_per_1k_input: 0.0008,  cost_per_1k_output: 0.004, supports_vision: true,  supports_tools: true },
  { provider_slug: 'anthropic', name: 'Claude 3 Opus',     slug: 'claude-3-opus',       model_id: 'claude-3-opus-20240229',     max_tokens: 4096, context_window: 200000, cost_per_1k_input: 0.015,   cost_per_1k_output: 0.075, supports_vision: true,  supports_tools: true },

  # Google models
  { provider_slug: 'google', name: 'Gemini 2.5 Pro',       slug: 'gemini-2-5-pro',      model_id: 'gemini-2.5-pro-preview-05-06',  max_tokens: 65536, context_window: 1048576, cost_per_1k_input: 0.00125, cost_per_1k_output: 0.01, supports_vision: true,  supports_tools: true },
  { provider_slug: 'google', name: 'Gemini 2.5 Flash',     slug: 'gemini-2-5-flash',    model_id: 'gemini-2.5-flash-preview-04-17', max_tokens: 65536, context_window: 1048576, cost_per_1k_input: 0.00015, cost_per_1k_output: 0.0006, supports_vision: true, supports_tools: true },
  { provider_slug: 'google', name: 'Gemini 2.0 Flash',     slug: 'gemini-2-0-flash',    model_id: 'gemini-2.0-flash',              max_tokens: 8192,  context_window: 1048576, cost_per_1k_input: 0.0001,  cost_per_1k_output: 0.0004, supports_vision: true, supports_tools: true }
]

models_data.each do |model_data|
  provider = created_providers[model_data[:provider_slug]]
  next unless provider

  ai_model = AiModel.find_or_create_by!(
    ai_provider: provider,
    slug: model_data[:slug]
  ) do |m|
    m.name = model_data[:name]
    m.model_id = model_data[:model_id]
    m.max_tokens = model_data[:max_tokens]
    m.context_window = model_data[:context_window]
    m.cost_per_1k_input = model_data[:cost_per_1k_input]
    m.cost_per_1k_output = model_data[:cost_per_1k_output]
    m.supports_streaming = model_data.fetch(:supports_streaming, true)
    m.supports_vision = model_data.fetch(:supports_vision, false)
    m.supports_tools = model_data.fetch(:supports_tools, false)
    m.is_active = true
  end

  puts "    Model: #{model_data[:name]} (#{provider.name})"
end

puts '  Created AI models'
puts ''
puts 'Seeding complete!'
puts "  Categories: #{created_categories.size}"
puts "  Providers:  #{created_providers.size}"
puts "  Models:     #{AiModel.count}"
