# frozen_string_literal: true

# Thin wrapper that loads the project's spec_helper.
# This allows specs written with `require 'rails_helper'` to work
# alongside the existing `require 'spec_helper'` convention.
require 'spec_helper'
