# frozen_string_literal: true

require "spec_helper"

# Issue #21: レガシーページと React ページが参照するバンドル名の契約。
#
# webpack の分割ビルドは app-bundle.css を生成しない（CSS はすべて
# sections-bundle.css に集約される）ため、参照側は生成されるものだけを
# 要求しなければならない。アセットの実ファイル有無に依存しないよう、
# タグヘルパーに渡すバンドル名で検証する。
RSpec.describe ClientAssetsHelper, type: :helper do
  describe "#react_bundle_css_tags" do
    it "requests only sections-bundle when no React app is provided" do
      allow(helper).to receive(:react_apps).and_return([])

      expect(helper).to receive(:stylesheet_link_tag).with("sections-bundle")
      helper.react_bundle_css_tags
    end

    it "requests only sections-bundle when React apps are provided" do
      allow(helper).to receive(:react_apps).and_return(["chat_panel"])

      expect(helper).to receive(:stylesheet_link_tag).with("sections-bundle")
      helper.react_bundle_css_tags
    end
  end

  describe "#react_bundle_js_tags" do
    it "loads the legacy full bundle when no React app is provided" do
      allow(helper).to receive(:react_apps).and_return([])

      expect(helper).to receive(:javascript_include_tag).with("webpack_bundles")
      helper.react_bundle_js_tags
    end

    it "loads vendor/common/sections and each per-app bundle" do
      allow(helper).to receive(:react_apps).and_return(%w[chat_panel topbar])

      expect(helper).to receive(:javascript_include_tag).with(
        "vendor-bundle", "common-bundle", "sections-bundle",
        "chat_panel-bundle", "topbar-bundle", "lodash_restore"
      )
      helper.react_bundle_js_tags
    end

    it "loads vendor_dates for date-heavy apps" do
      allow(helper).to receive(:react_apps).and_return(["search_page"])

      expect(helper).to receive(:javascript_include_tag).with(
        "vendor-bundle", "common-bundle", "sections-bundle",
        "vendor_dates-bundle", "search_page-bundle", "lodash_restore"
      )
      helper.react_bundle_js_tags
    end
  end
end
