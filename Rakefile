# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  # Run store specs first: Ruby Coverage counters for opt-in adapters
  # (redis, rails_cache) must be exercised before Ractor/concurrency tests
  # run, which can disrupt coverage tracking in certain Ruby 3.4 builds.
  store_specs = Dir["spec/stores/**/*_spec.rb"].sort
  other_specs = Dir["spec/**/*_spec.rb"].sort - store_specs
  t.rspec_opts = (store_specs + other_specs).join(" ")
  t.pattern = "non_existent_placeholder" # overridden by rspec_opts file args
end

require "standard/rake"

require "yard"
YARD::Rake::YardocTask.new(:doc) do |t|
  t.options = ["--fail-on-warning"]
end

task default: %i[spec standard]
