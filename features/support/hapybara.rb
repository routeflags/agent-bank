Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new

  [
    "--headless",
    "--window-size=1280,900",
    "--disable-gpu",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-setuid-sandbox",
    "--disable-background-networking",
    "--disable-background-timer-throttling",
    "--disable-renderer-backgrounding",
    "--disable-features=site-per-process,TranslateUI",
    "--disable-breakpad",
    "--disable-sync",
    "--disable-translate",
    "--metrics-recording-only",
    "--no-first-run",
    "--safebrowsing-disable-auto-update",
    "--disable-default-apps",
    "--disable-backgrounding-occluded-windows",
    "--disable-component-extensions-with-background-pages"
  ].each { |arg| options.add_argument(arg) }

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options: options
  )
end

if false # rubocop:disable Lint/LiteralAsCondition
  require 'capybara/poltergeist'

  Capybara.register_driver :poltergeist do |app|
    Capybara::Poltergeist::Driver.new(app, js_errors: false)
  end
  Capybara.javascript_driver = :poltergeist
else
  # :selenium_chrome_headless
  Capybara.javascript_driver = :selenium_chrome_headless
end

Capybara.default_max_wait_time = 30
Capybara.ignore_hidden_elements = true
Capybara.default_selector = :css

# After do |scenario|
#   if scenario.failed?
#     begin
#       # Сохраняем скриншот
#       save_path = "tmp/screenshots/failure_#{Time.now.strftime('%Y%m%d-%H%M%S')}.png"
#       page.save_screenshot(save_path)
#       puts "\nСкриншот сохранен: #{save_path}"
#
#       # Предотвращаем закрытие браузера
#       page.instance_variable_set('@closed', false)
#       Capybara.current_session.instance_variable_set('@touched', false)
#
#       # Держим браузер открытым
#       sleep 1_000_000
#     rescue => e
#       puts "Ошибка при сохранении состояния браузера: #{e.message}"
#     end
#   end
# end
