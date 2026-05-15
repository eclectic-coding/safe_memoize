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
- Optional TTL expiration support for cached entries
- Optional LRU cache size limit per method via `max_size:`
- Conditional caching via `if:` and `unless:` predicates
- Lifecycle hooks for hit, eviction, and expiration events
- Per-instance cache metrics (hit rate, miss rate, computation time)
- Custom cache key generation per method
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

### Lifecycle hooks

Register callbacks that fire when cached entries are evicted or expire.

**`on_memo_evict`** fires when an entry is removed via `reset_memo`, `reset_all_memos`, or LRU eviction:

```ruby
obj.on_memo_evict do |cache_key, record|
  Rails.logger.info("Evicted #{cache_key[0]}(#{cache_key[1].join(", ")}), was: #{record[:value].inspect}")
end
```

**`on_memo_hit`** fires on every cache hit:

```ruby
obj.on_memo_hit do |cache_key, record|
  StatsD.increment("cache.hit", tags: ["method:#{cache_key[0]}"])
end
```

**`on_memo_expire`** fires when a TTL entry is detected as expired (on the next call or during inspection):

```ruby
obj.on_memo_expire do |cache_key, record|
  Rails.logger.debug("TTL expired: #{cache_key[0]}")
end
```

Multiple hooks of the same type can be registered and all will fire. Remove them with `clear_memo_hooks`:

```ruby
obj.clear_memo_hooks(:on_evict)   # Clears evict hooks only
obj.clear_memo_hooks(:on_expire)  # Clears expire hooks only
obj.clear_memo_hooks              # Clears all hooks
```

Hooks are per-instance and do not affect other objects of the same class.

### TTL expiration

```ruby
class QuoteService
  prepend SafeMemoize

  def current_quote
    fetch_quote_from_api
  end
  memoize :current_quote, ttl: 60
end
```

With a TTL, cached values expire automatically after the given number of seconds. The next call recomputes and refreshes the cache.

### LRU cache size limit

Pass `max_size:` to cap how many entries a method can hold. When the limit is reached the least-recently-used entry is evicted to make room:

```ruby
class ProductService
  prepend SafeMemoize

  def find(id)
    Product.find(id)
  end
  memoize :find, max_size: 100
end
```

Cache hits count as recent access, so a frequently-read entry will never be the one evicted:

```ruby
svc = ProductService.new
svc.find(1)   # miss — cached
svc.find(2)   # miss — cached
svc.find(1)   # hit  — promotes 1 to most-recently-used; 2 is now LRU
svc.find(3)   # miss — evicts 2 (LRU), caches 3
```

`max_size:` combines with `ttl:` — LRU eviction applies within the TTL window, and entries also expire normally when the TTL elapses:

```ruby
memoize :find, max_size: 50, ttl: 300
```

The `on_evict` hook fires for LRU-evicted entries the same way it does for manual `reset_memo` calls.

### Conditional caching

Use `if:` to cache a result only when the predicate returns truthy, or `unless:` to skip caching when it returns truthy. Calls that don't satisfy the condition recompute every time until they do.

```ruby
class UserService
  prepend SafeMemoize

  # Don't cache nil — retries on every call until a user is found
  def find(id)
    User.find_by(id: id)
  end
  memoize :find, if: ->(result) { !result.nil? }
end
```

```ruby
class DataService
  prepend SafeMemoize

  # Don't cache error responses
  def fetch(key)
    api_client.get(key)
  end
  memoize :fetch, unless: ->(result) { result.is_a?(ErrorResponse) }
end
```

Both options accept any callable and compose with `ttl:` and `max_size:`:

```ruby
memoize :find, if: ->(result) { !result.nil? }, ttl: 60, max_size: 500
```

### Custom cache keys

By default the cache key is derived from the method name and all arguments. Use `memoize_with_custom_key` on an instance to control exactly what makes two calls equivalent:

```ruby
class ReportService
  prepend SafeMemoize

  def generate(user_id, options)
    build_report(user_id, options)
  end
  memoize :generate
end

svc = ReportService.new

# Cache only by user_id — ignore the options hash entirely
svc.memoize_with_custom_key(:generate) { |user_id, _options| user_id }

svc.generate(42, {format: :pdf})  # computes and caches
svc.generate(42, {format: :csv})  # cache hit — same user_id, options ignored
```

The block can return any comparable value — a scalar, array, or hash:

```ruby
svc.memoize_with_custom_key(:generate) do |user_id, options|
  {user: user_id, locale: options[:locale]}
end
```

Custom key generators are per-instance and can be cleared at any time:

```ruby
svc.clear_custom_keys(:generate)  # Remove generator for one method
svc.clear_custom_keys             # Remove all custom key generators
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

### Cache metrics

Each instance tracks hits, misses, and computation time automatically.

```ruby
obj.cache_stats
# => {
#      total_hits: 42,
#      total_misses: 8,
#      hit_rate: 84.0,
#      miss_rate: 16.0,
#      average_computation_time: 0.012345,
#      entries: [
#        { method: :find, args: [1], hits: 10, misses: 1,
#          hit_rate: 90.91, computation_time: 0.005 },
#        ...
#      ]
#    }

obj.cache_stats_for(:find)   # Stats scoped to one method
obj.cache_hit_rate           # => 84.0  (percentage)
obj.cache_miss_rate          # => 16.0  (percentage)
obj.cache_metrics_reset      # Clears all collected metrics
```

Metrics are per-instance and reset independently from the cache itself — clearing metrics does not evict cached values.

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
