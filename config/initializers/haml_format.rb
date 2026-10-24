# frozen_string_literal: true

# Render void elements (<img>, <input>, <meta>...) in HTML5 style
# (omitted end tag) instead of XHTML self-closing style (<img/>).
# Required for html-validate `void-style` rule compliance.
Haml::Template.options[:format] = :html5
