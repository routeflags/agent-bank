#
# This module contains helper methods for dealing with the two
# icon sets we use: ss-pika and font-awesome
#

require_relative '../../app/view_utils/icon_map'

module IconHelper

  ICON_PACK = APP_CONFIG.icon_pack || "font-awesome"

  # html_options は <i> に付ける属性（シンボルの `_` は `-` に変換される）。
  # 例: icon_tag('cross', [], :"aria-hidden" => "true")
  #     => <i class="icon-cross" aria-hidden="true"></i>
  def icon_tag(icon_name, additional_classes=[], html_options={})
    icon_class_tag(icon_class(icon_name), additional_classes, html_options)
  end

  def icon_class(icon_name)
    icon = ICON_MAP[ICON_PACK][icon_name]
    if icon.nil?
      icon = (ICON_PACK == "font-awesome" ? "icon-circle-blank" : "ss-record")
    end
    icon
  end

  def self.icon_specified?(icon_name)
    ICON_MAP[ICON_PACK][icon_name].present?
  end

  def pick_icons(icon_pack, icons)
    ICON_MAP[icon_pack].slice(*icons)
  end

  def icon_class_tag(icon_class, additional_classes = [], html_options = {})
    classes_string = [icon_class].concat(additional_classes).join(" ")
    attributes = html_options.map { |name, value| " #{html_attribute_name(name)}=\"#{ERB::Util.html_escape(value)}\"" }.join
    "<i class=\"#{classes_string}\"#{attributes}></i>".html_safe
  end

  def icon_map_tag(icon_map, icon_name, additional_classes = [])
    icon_class_tag(icon_map[icon_name], additional_classes)
  end

  private

  # `aria_hidden` のようなシンボルを HTML の属性名（aria-hidden）に直す
  def html_attribute_name(name)
    ERB::Util.html_escape(name.to_s.tr("_", "-"))
  end

end
