# frozen_string_literal: true

# Steps for custom fields on the new-listing form and for the setup of
# listing custom fields (text/numeric/date/checkbox/dropdown). Backs the
# previously undefined steps in features/listings (see docs/cucumber-triage.md).

def listing_field_community(ident)
  Community.find_by!(ident: ident)
end

def listing_field_category(community, name)
  community.categories.find { |c| c.display_name('en') == name }
end

def listing_custom_field_named(name)
  community = listing_field_community('test')
  (community.custom_fields + community.person_custom_fields).find { |f| f.name('en') == name }
end

def build_listing_custom_field(klass, community, category_name, name)
  field = klass.new(entity_type: :for_listing, required: true)
  field.community = community
  field.names = [CustomFieldName.new(locale: 'en', value: name)]
  field.categories = [listing_field_category(community, category_name)]
  field
end

# --- Data setup (Given) ---

Given(/^there is a custom dropdown field "(.+)" in community "(.+)" in category "(.+)" with options:$/) do |name, ident, category_name, table|
  community = listing_field_community(ident)
  field = build_listing_custom_field(DropdownField, community, category_name, name)
  table.hashes.each_with_index do |row, index|
    option = CustomFieldOption.new(sort_priority: index + 1)
    titles = [CustomFieldOptionTitle.new(locale: 'en', value: row['en'])]
    titles << CustomFieldOptionTitle.new(locale: 'fi', value: row['fi']) if row['fi'].present?
    option.titles = titles
    field.options << option
  end
  field.save!
end

Given(/^there is a custom text field "(.+)" in community "(.+)" in category "(.+)"$/) do |name, ident, category_name|
  build_listing_custom_field(TextField, listing_field_community(ident), category_name, name).save!
end

Given(/^there is a custom numeric field "(.+)" in that community in category "(.+)" with min value (\d+) and with max value (\d+)$/) do |name, category_name, min, max|
  field = build_listing_custom_field(NumericField, listing_field_community('test'), category_name, name)
  field.min = min.to_f
  field.max = max.to_f
  field.save!
end

Given(/^there is a custom date field "(.+)" in that community in category "(.+)"$/) do |name, category_name|
  build_listing_custom_field(DateField, listing_field_community('test'), category_name, name).save!
end

# (checkbox field setup is already covered by listing_steps.rb)

Given(/^there is a numeric field "(.+)" in community "(.+)" for category "(.+)" with min value "(.+)" and max value "(.+)"$/) do |name, ident, category_name, min, max|
  field = build_listing_custom_field(NumericField, listing_field_community(ident), category_name, name)
  field.min = min.to_f
  field.max = max.to_f
  field.save!
end

When(/^custom field "(.+)" is not required$/) do |name|
  listing_custom_field_named(name).update!(required: false)
end

# --- New-listing form interactions (When) ---

When(/^I select "(.+)" from dropdown "(.+)"$/) do |option_text, field_name|
  field = listing_custom_field_named(field_name)
  select option_text, from: "custom_fields_#{field.id}"
end

When(/^I fill in text field "(.+)" with "(.+)"$/) do |field_name, value|
  field = listing_custom_field_named(field_name)
  fill_in "custom_fields_#{field.id}", with: value
end

When(/^I fill in custom numeric field "(.+)" with "(.+)"$/) do |field_name, value|
  field = listing_custom_field_named(field_name)
  fill_in "custom_fields_#{field.id}", with: value
end

When(/^I fill select custom date "(.+)" with day="(\d+)", month="(.+)" and year="(\d+)"$/) do |field_name, day, month, year|
  field = listing_custom_field_named(field_name)
  base = "custom_fields_#{field.id}"
  selects = all("select[id^='#{base}']", visible: true)
  day_select = selects.find { |el| el[:id].to_s.end_with?('3i') }
  month_select = selects.find { |el| el[:id].to_s.end_with?('2i') }
  year_select = selects.find { |el| el[:id].to_s.end_with?('1i') }
  day_select.select(day)
  month_select.select(month)
  year_select.select(year)
end
