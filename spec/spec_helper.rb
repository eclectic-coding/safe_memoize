# frozen_string_literal: true

require "simplecov"
require "simplecov_json_formatter"
SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter
  ])
  skip "/spec/"
  skip "/version.rb"
  cover "lib/**/*.rb"
end

# ractor_safe: true is built on Ractor, which Ruby flags as experimental; the
# warning is noise in the test output.
Warning[:experimental] = false

require "safe_memoize"
require "safe_memoize/stores/redis"
require "safe_memoize/stores/rails_cache"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
