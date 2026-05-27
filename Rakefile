# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  # Ordering ensures accurate coverage tracking in Ruby 3.4:
  # 1. Store specs first: opt-in adapter lines must be hit before Ractor tests
  #    can disrupt Ruby's Coverage counters.
  # 2. Ractor specs last: Ractor-based tests spin up background Ractors whose
  #    internal threads can cause later coverage samples to be missed if they
  #    interleave with SimpleCov's collection phase.
  store_specs = Dir["spec/stores/**/*_spec.rb"].sort
  ractor_specs = Dir["spec/ractor*_spec.rb"].sort
  other_specs = Dir["spec/**/*_spec.rb"].sort - store_specs - ractor_specs
  t.rspec_opts = (store_specs + other_specs + ractor_specs).join(" ")
  t.pattern = "non_existent_placeholder" # overridden by rspec_opts file args
end

require "standard/rake"

require "yard"
YARD::Rake::YardocTask.new(:doc) do |t|
  t.options = ["--fail-on-warning"]
end

task default: %i[spec standard]
