Given /^the (\w+) indexes are processed$/ do |model|
  ThinkingSphinx::Test.index "#{model.underscore}_core", "#{model.underscore}_delta"
  wait_until_index_finished()
end

# Raku homepage hero search (the legacy #search-button form is gone).
When(/^I fill in the search box with "(.*)"$/) do |value|
  within('.raku-hero__search') do
    fill_in 'q', with: value
  end
end

When(/^I press the hero search button$/) do
  find('.raku-hero__search-btn').click
end
