# SafeMemoize

Thread-safe memoization for Ruby that correctly handles `nil` and `false` values.

## The Problem

Ruby's common memoization pattern breaks with falsy values:

```ruby
def user
  @user ||= find_user  # Re-runs find_user every time it returns nil!
end
```

SafeMemoize uses `Hash#key?` to distinguish "not yet cached" from "cached nil/false", so your methods are only computed once regardless of return value.

## Features

- Correctly memoizes `nil` and `false` return values
- Caches per unique arguments (positional and keyword)
- Thread-safe via double-check locking
- Zero runtime dependencies
- Simple `prepend` + `memoize` API
- Preserves public, protected, and private method visibility
- Supports targeted cache invalidation by argument combination
- Includes a `memoized?` helper for cache inspection
- Includes a `memo_count` helper for cache size stats
- Includes a `memo_keys` helper for inspecting cached signatures
- Includes a `memo_values` helper for inspecting cached signatures and values
- Block arguments bypass cache (blocks aren't comparable)

## Installation

Add to your Gemfile:

```ruby
gem "safe_memoize"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install safe_memoize
```

## Usage

### Basic memoization

```ruby
class UserService
  prepend SafeMemoize

  def current_user
    # This expensive lookup runs only once
    User.find_by(session_id: session_id)
  end
  memoize :current_user
end
```

### With arguments

Results are cached per unique argument combination:

```ruby
class Calculator
  prepend SafeMemoize

  def compute(x, y)
    sleep(2)
    x + y
  end
  memoize :compute
end

calc = Calculator.new
calc.compute(1, 2)  # computes and caches
calc.compute(1, 2)  # returns cached result
calc.compute(3, 4)  # computes and caches (different args)
```

### Nil and false safety

```ruby
class Config
  prepend SafeMemoize

  def enabled?
    # Only called once, even though it returns false
    ENV["FEATURE_FLAG"] == "true"
  end
  memoize :enabled?
end
```

### Works with private methods

```ruby
class TokenProvider
  prepend SafeMemoize

  def bearer_token
    token
  end

  private

  def token
    fetch_token_from_service
  end
  memoize :token
end
```

### Cache reset

```ruby
obj = MyService.new
obj.reset_memo(:current_user)                    # Clears all cached entries for one method
obj.reset_memo(:find_user, 42)                  # Clears only the cached call for find_user(42)
obj.reset_memo(:search, "ruby", page: 2)       # Clears one positional/keyword combination
obj.reset_all_memos                             # Clears all memoized values
```

### Cache inspection

```ruby
obj = MyService.new

obj.memoized?(:current_user)              # => false
obj.current_user
obj.memoized?(:current_user)              # => true

obj.memoized?(:search, "ruby", page: 2)  # Checks one cached argument combination
obj.memo_count                            # Total cached entries for this instance
obj.memo_count(:search)                   # Cached entries for one method
obj.memo_keys                             # All cached signatures with method, args, kwargs
obj.memo_keys(:search)                    # Cached signatures for one method
obj.memo_values                           # Cached signatures and values for all methods
obj.memo_values(:search)                  # Cached signatures and values for one method
```

## How It Works

SafeMemoize uses Ruby's `prepend` mechanism. When you call `memoize :method_name`, it creates an anonymous module with a wrapper method and prepends it onto your class. The wrapper calls `super` to invoke the original method and stores the result in a per-instance hash. Thread safety is achieved with a per-instance `Mutex` using double-check locking.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests. You can also run `bin/console` for an interactive prompt.

GitHub Actions also runs the full `bundle exec rake` suite automatically for pull requests, manual workflow runs, and pushes to `main` via `.github/workflows/ci.yml`.

## Releasing

Releases are automated in two parts:

1. Run `bin/release VERSION` locally to:
   - update `lib/safe_memoize/version.rb`
   - convert the current `## [Unreleased]` section in `CHANGELOG.md` into a dated release entry
   - create the release commit and annotated tag
2. Push the branch and tag to GitHub. The workflow in `.github/workflows/release.yml` will:
   - run the test and lint suite
   - build the gem
   - push it to RubyGems when that version is not already published
   - create a GitHub release using the matching section from `CHANGELOG.md`

One-time setup:

- add a `RUBYGEMS_API_KEY` repository secret in GitHub

Typical release flow:

```bash
bundle exec rake
bin/release 0.1.1
git push origin HEAD
git push origin v0.1.1
```

To preview the changelog/version update without changing anything, use:

```bash
bin/release 0.1.1 --dry-run
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eclectic-coding/safe_memoize.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
