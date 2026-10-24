# frozen_string_literal: true

# Selects which client-side JS/CSS bundles a page loads.
#
# Views call `provide_react_app :chat_panel` etc. BEFORE the layout head
# renders (view bodies render before the layout, and layout-level provides
# must be placed above `= render 'layouts/head'`).
#
# - No apps provided  -> legacy full bundle (webpack_bundles.js) +
#   sections-bundle.css: zero regression for unconverted pages.
# - Apps provided     -> vendor + common + per-app bundles emitted by the
#   split webpack entries (see client/webpack.client.base.config.js).
#
# CSS: all client CSS is extracted into sections-bundle.css by the webpack
# `sections` cacheGroup, so the split build does not emit app-bundle.css.
# Never reference app-bundle.css here (Issue #21).
module ClientAssetsHelper
  # Apps whose entry graph imports moment/react-dates/axios/react-form —
  # these pages also load the vendor_dates chunk.
  VENDOR_DATES_APPS = %w[availability onboarding search_page].freeze

  def provide_react_app(name)
    # content_for concatenates blocks, so store each app as a
    # comma-terminated value and split on read.
    content_for(:react_apps) { "#{name}," }
  end

  def react_apps
    content_for(:react_apps).to_s.split(",").map(&:strip).reject(&:empty?)
  end

  def react_bundle_css_tags
    # All component CSS is extracted into sections-bundle.css by the webpack
    # sections cacheGroup — regardless of whether a React app is provided.
    stylesheet_link_tag('sections-bundle')
  end

  def react_bundle_js_tags
    if react_apps.empty?
      javascript_include_tag('webpack_bundles')
    else
      tags = ['vendor-bundle', 'common-bundle', 'sections-bundle']
      tags << 'vendor_dates-bundle' if (react_apps & VENDOR_DATES_APPS).any?
      tags.concat(react_apps.map { |app| "#{app}-bundle" })
      # Restore the lodash2 global after the bundles (see lodash_restore.js).
      tags << 'lodash_restore'
      javascript_include_tag(*tags)
    end
  end
end
