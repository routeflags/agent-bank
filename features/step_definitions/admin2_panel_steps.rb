# frozen_string_literal: true

# Steps for admin2 panel features (display settings, listing/user fields).
# These back the previously undefined steps triaged in docs/cucumber-triage.md.

def admin2_test_community
  Community.find_by!(ident: 'test')
end

def admin2_field_named(name)
  (admin2_test_community.custom_fields + admin2_test_community.person_custom_fields)
    .find { |f| f.name('en') == name }
end

def admin2_visible_modal
  find('.modal.show', visible: true)
end

Given(/^community "(.+)" has default browse view "(.+)"$/) do |_community, view|
  admin2_test_community.update!(default_browse_view: view)
end

Given(/^community "(.+)" has name display type "(.+)"$/) do |_community, type|
  admin2_test_community.update!(name_display_type: type)
end

Then(/^community "(.+)" should have default browse view "(.+)"$/) do |_community, view|
  expect(admin2_test_community.reload.default_browse_view).to eq(view)
end

Then(/^community "(.+)" should have name display type "(.+)"$/) do |_community, type|
  expect(admin2_test_community.reload.name_display_type).to eq(type)
end

Then(/^the community should show category in listing list$/) do
  expect(admin2_test_community.reload.show_category_in_listing_list).to eq(true)
end

Then(/^the community should not show category in listing list$/) do
  expect(admin2_test_community.reload.show_category_in_listing_list).to eq(false)
end

Then(/^the community should show listing publishing date$/) do
  expect(admin2_test_community.reload.show_listing_publishing_date).to eq(true)
end

Then(/^the community should not show listing publishing date$/) do
  expect(admin2_test_community.reload.show_listing_publishing_date).to eq(false)
end

# --- Custom field data setup ---

Given(/^there is a custom field "(.+)" in community "(.+)" for category "(.+)"$/) do |name, _community, category_name|
  community = admin2_test_community
  category = community.categories.find { |c| c.display_name('en') == category_name }
  raise "No category #{category_name}" if category.nil?

  field = TextField.new(entity_type: :for_listing, required: false)
  field.community = community
  field.names = [CustomFieldName.new(locale: 'en', value: name)]
  field.categories = [category]
  field.save!
end

Given(/^there is a custom dropdown field "(.+)" in community "(.*)" with options:$/) do |name, _community, table|
  community = admin2_test_community
  field = DropdownField.new(entity_type: :for_listing, required: false)
  field.community = community
  field.names = [CustomFieldName.new(locale: 'en', value: name)]
  field.categories = [community.categories.first]
  table.hashes.each_with_index do |row, index|
    option = CustomFieldOption.new(sort_priority: index + 1)
    option.titles = [CustomFieldOptionTitle.new(locale: 'en', value: row['en'])]
    field.options << option
  end
  field.save!
end

Given(/^there is a custom user dropdown field "(.+)" in community "(.*)" with options:$/) do |name, _community, table|
  community = admin2_test_community
  field = DropdownField.new(entity_type: :for_person, required: false)
  field.community = community
  field.names = [CustomFieldName.new(locale: 'en', value: name)]
  table.hashes.each_with_index do |row, index|
    option = CustomFieldOption.new(sort_priority: index + 1)
    option.titles = [CustomFieldOptionTitle.new(locale: 'en', value: row['en'])]
    field.options << option
  end
  field.save!
end

# --- Listing/user field form interactions ---

When(/^I toggle category "(.+)"$/) do |category_name|
  within('#categories-container') do
    find('label', text: /\A#{Regexp.escape(category_name)}\z/).click
  end
end

When(/^I set numeric field min value to (\d+)$/) do |value|
  fill_in 'custom_field[min]', with: value
end

When(/^I set numeric field max value to (\d+)$/) do |value|
  fill_in 'custom_field[max]', with: value
end

When(/^I change custom field "(.*)" name to "(.*)"$/) do |name, new_name|
  field = admin2_field_named(name)
  find("#edit_custom_field_#{field.id}").click
  modal = admin2_visible_modal
  within(modal) do
    # The remote popup fills asynchronously; wait until it shows THIS
    # field's data before editing (guards against stale modal content).
    expect(page).to have_field('custom_field[name_attributes][en]', with: name)
    fill_in 'custom_field[name_attributes][en]', with: new_name
    click_button 'Save changes'
  end
end

When(/^I change custom field "(.+)" categories$/) do |name|
  @changed_field_name = name
  find("#edit_custom_field_#{admin2_field_named(name).id}").click
  modal = admin2_visible_modal
  within(modal) do
    expect(page).to have_field('custom_field[name_attributes][en]', with: name)
    # Select all leaf categories (async JS), wait until all are checked.
    find('.select-all-checkbox').click
    all('.with-select-all', visible: :all).each { |cb| expect(cb).to be_checked }
    click_button 'Save changes'
  end
end

Then(/^correct categories should be stored$/) do
  field = admin2_field_named(@changed_field_name)
  leaf_count = admin2_test_community.leaf_categories.size
  expect(field.categories.size).to eq(leaf_count)
end

When(/^I try to remove all categories$/) do
  find("#edit_custom_field_#{admin2_field_named('House type').id}").click
  modal = admin2_visible_modal
  within(modal) do
    expect(page).to have_field('custom_field[name_attributes][en]', with: 'House type')
    find('.unselect-all-checkbox').click
    all('.with-select-all', visible: :all).each { |cb| expect(cb).not_to be_checked }
    click_button 'Save changes'
  end
end

When(/^I remove listing field "(.+)"$/) do |name|
  field = admin2_field_named(name)
  find("[data-id='#{field.id}'] .custom-fields-action-remove").click
  modal = admin2_visible_modal
  within(modal) do
    find('button', text: /^Delete the listing field/).click
  end
end

When(/^I remove user field "(.+)"$/) do |name|
  field = admin2_field_named(name)
  find("[data-id='#{field.id}'] .custom-fields-action-remove").click
  modal = admin2_visible_modal
  within(modal) do
    find('button', text: /^Delete the user field/).click
  end
end

Then(/^I should see that I do not have any listing fields$/) do
  expect(page).to have_no_css('.custom-field-list-row')
end

Then(/^I should see that I do not have any user fields$/) do
  expect(page).to have_no_css('.custom-field-list-row')
end
