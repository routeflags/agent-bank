require 'rubygems'
require File.expand_path('../../test/helper_modules', __dir__)
require 'rspec/expectations'
require 'cucumber/rails'
require 'email_spec/cucumber'
require './spec/support/webmock'
include TestHelpers # rubocop:disable Style/MixinUsage

# Disable Rails error handling
ActionController::Base.allow_rescue = false

# Initialize and configure Sphinx
#
# Runnability fixes:
# - SafeSphinxStop (shared with the rspec suite) suppresses the SystemExit
#   that autostop raises when searchd fails to stop, which otherwise
#   destroys the run summary.
# - Stop any leftover searchd before starting so a stale process (e.g.
#   from a previous run) does not make Riddle::Controller#start fail the
#   whole boot with Riddle::CommandFailedError.
require File.expand_path('../../spec/support/thinking_sphinx', __dir__)
begin
  ThinkingSphinx::Test.stop
rescue StandardError, SystemExit
  nil
end
ThinkingSphinx::Test.init
# searchd's stop is asynchronous: an immediately following start races the
# dying process for the port (Riddle::CommandFailedError kills the whole
# boot). Retry start a few times and never let Sphinx failures abort.
3.times do

    ThinkingSphinx::Test.start
    break
  rescue StandardError, SystemExit
    sleep 2

end
at_exit do

    ThinkingSphinx::Test.stop
rescue StandardError, SystemExit
    nil

end
ThinkingSphinx::Deltas.suspend!

# Load test data once before all tests
BeforeAll do
  DatabaseCleaner.clean_with(:truncation)
  load_default_test_data_to_db_before_suite
end

# Set default cleaning strategy
Before do
  DatabaseCleaner.strategy = :transaction
end

# Handle JavaScript tests
Before('@javascript') do
  # Reload test data if database is empty
  if Person.count == 0 || Community.count == 0
    DatabaseCleaner.clean_with(:truncation)
    load_default_test_data_to_db_before_suite
  end

  # Load test-specific data
  load_default_test_data_to_db_before_test

  # Use truncation for JS tests
  DatabaseCleaner.strategy = :truncation
  DatabaseCleaner.start
end

# Handle non-JavaScript tests
Before('not @javascript') do
  DatabaseCleaner.start
  load_default_test_data_to_db_before_test
end

# Clean up after each test
After do
  DatabaseCleaner.clean
  Capybara.reset_sessions!
end

Before('@no-transaction') do
  DatabaseCleaner.strategy = :deletion
  Cucumber::Rails::Database.javascript_strategy = :deletion
end

After('@no-transaction') do
  DatabaseCleaner.clean_with :deletion
  load_default_test_data_to_db_before_suite
  load_default_test_data_to_db_before_test
end

Before('@sphinx') do
  ThinkingSphinx::Deltas.resume!
end

After('@sphinx') do
  ThinkingSphinx::Deltas.suspend!
end