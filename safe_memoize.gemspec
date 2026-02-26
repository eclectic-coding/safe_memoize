# frozen_string_literal: true

require_relative 'lib/safe_memoize/version'

Gem::Specification.new do |spec|
  spec.name = 'safe_memoize'
  spec.version = SafeMemoize::VERSION
  spec.authors = ['Chuck Smith']
  spec.email = ['eclectic-coding@users.noreply.github.com']

  spec.summary = 'Thread-safe memoization that correctly handles nil and false values'
  spec.description = 'A prepend-based memoization module for Ruby that safely caches nil and false return values, supports method arguments, and provides thread safety via double-check locking.'
  spec.homepage = 'https://github.com/eclectic-coding/safe_memoize'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/eclectic-coding/safe_memoize'
  spec.metadata['changelog_uri'] = 'https://github.com/eclectic-coding/safe_memoize/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .standard.yml])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
