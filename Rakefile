# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "standard/rake"

require "yard"
YARD::Rake::YardocTask.new(:doc) do |t|
  t.options = ["--fail-on-warning"]
end

task default: %i[spec standard]
