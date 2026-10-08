# frozen_string_literal: true

# Selects which client-side JS/CSS bundles a page loads.
#
# Views call `provide_react_app :chat_panel` etc. BEFORE the layout head
# renders (view bodies render before the layout, and layout-level provides
# must be placed above `= render 'layouts/head'`).
#
# - No apps provided  -> legacy full bundles (webpack_bundles.js /
#   app-bundle.css): zero regression for unconverted pages.
# - Apps provided     -> vendor + common + per-app bundles emitted by the
#   split webpack entries (see client/webpack.client.base.config.js).
module ClientAssetsHelper
  def provide_react_app(name)
    # content_for concatenates blocks, so store each app as a
    # comma-terminated value and split on read.
    content_for(:react_apps) { "#{name}," }
  end

  def react_apps
    content_for(:react_apps).to_s.split(",").map(&:strip).reject(&:empty?)
  end

  def react_bundle_css_tags
    return stylesheet_link_tag('app-bundle') if react_apps.empty?

    # All component CSS (including chat panel styles) is extracted into
    # sections-bundle.css by the webpack sections cacheGroup.
    stylesheet_link_tag('sections-bundle')
  end

  def react_bundle_js_tags
    if react_apps.empty?
      javascript_include_tag('webpack_bundles')
    else
      javascript_include_tag(
        'vendor-bundle', 'common-bundle', 'sections-bundle',
        *react_apps.map { |app| "#{app}-bundle" }
      )
    end
  end
end
