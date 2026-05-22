# SafeMemoize

[![CI](https://github.com/eclectic-coding/safe_memoize/actions/workflows/ci.yml/badge.svg)](https://github.com/eclectic-coding/safe_memoize/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/safe_memoize)](https://rubygems.org/gems/safe_memoize)
[![Total Downloads](https://img.shields.io/gem/dt/safe_memoize)](https://rubygems.org/gems/safe_memoize)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.3-CC342D)](https://www.ruby-lang.org)
[![codecov](https://codecov.io/gh/eclectic-coding/safe_memoize/graph/badge.svg)](https://codecov.io/gh/eclectic-coding/safe_memoize)

Thread-safe memoization for Ruby that correctly handles `nil` and `false` values.

SafeMemoize is a production-ready, zero-dependency memoization library for Ruby. It wraps methods with a `prepend`-based cache that handles everything the standard `||=` idiom gets wrong: `nil` and `false` return values are cached correctly, per-argument result maps eliminate redundant computation for parameterized methods, and a per-instance `Mutex` with double-check locking makes the whole thing safe under concurrent load.

Beyond the basics, SafeMemoize ships with TTL expiration (including sliding window refresh via `ttl_refresh:`), LRU cache size capping, conditional caching via `if:`/`unless:` predicates, lifecycle hooks for cache hits, evictions, and expirations, per-instance metrics (hit rate, miss rate, average computation time), targeted and bulk cache invalidation, custom cache key generators, and rich introspection helpers (`memoized?`, `memo_count`, `memo_keys`, `memo_values`, `memo_ttl_remaining`). It preserves method visibility (public, protected, and private) and requires no runtime dependencies.

## The Problem

Ruby's common memoization pattern breaks with falsy values: 

```ruby
def user
  @user ||= find_user  # Re-runs find_user every time it returns nil!
end
```

SafeMemoize uses `Hash#key?` to distinguish "not yet cached" from "cached nil/false", so your methods are only computed once regardless of return value.

## How It Works

SafeMemoize uses Ruby's `prepend` mechanism. When you call `memoize :method_name`, it creates an anonymous module with a wrapper method and prepends it onto your class. The wrapper calls `super` to invoke the original method and stores the result in a per-instance hash. Thread safety is achieved with a per-instance `Mutex` using double-check locking.

## Features

- [Correctly memoizes `nil` and `false` return values](#nil-and-false-safety)
- [Caches per unique arguments (positional and keyword)](#with-arguments)
- [Thread-safe via double-check locking](#how-it-works)
- [Simple `prepend` + `memoize` API](#usage)
- [Preserves public, protected, and private method visibility](#works-with-private-methods)
- [Supports targeted cache invalidation by argument combination](#cache-reset)
- [Includes a `memoized?` helper for cache inspection](#cache-inspection)
- [Includes a `memo_count` helper for cache size stats](#cache-inspection)
- [Includes a `memo_keys` helper for inspecting cached signatures](#cache-inspection)
- [Includes a `memo_values` helper for inspecting cached signatures and values](#cache-inspection)
- [Optional TTL expiration support for cached entries](#ttl-expiration)
- [Sliding window TTL via `ttl_refresh: true`](#sliding-window-ttl)
- [Optional LRU cache size limit per method via `max_size:`](#lru-cache-size-limit)
- [Conditional caching via `if:` and `unless:` predicates](#conditional-caching)
- [Lifecycle hooks for hit, miss, eviction, and expiration events](#lifecycle-hooks)
- [Per-instance cache metrics (hit rate, miss rate, computation time)](#cache-metrics)
- [Cache warm-up, export, and restore (`warm_memo`, `dump_memo`, `load_memo`)](#cache-warm-up-and-persistence)
- [Class-level shared cache via `shared: true` with optional LRU](#shared-cache)
- [Bulk memoization via `memoize_all` (public, protected, and private)](#bulk-memoization)
- [Custom cache key generation per method](#custom-cache-keys)
- [TTL introspection via `memo_ttl_remaining`](#cache-inspection)
- [Deep single-entry inspection via `memo_inspect`](#cache-inspection)
- [`ArgumentError` at definition time when memoizing an undefined method](#basic-memoization)
- [Hook error isolation — hook exceptions never propagate to callers](#lifecycle-hooks)
- [Deprecation infrastructure for gem authors](#deprecation)
- [Optional `ActiveSupport::Notifications` integration for Rails observability](#activesupportnotifications)
- [Optional StatsD adapter for metrics pipelines](#statsd)
- [Optional OpenTelemetry adapter for distributed tracing](#opentelemetry)
- [Rails request-scope helpers for controllers and service objects](#rails-request-scope)
- [Batch cache warm-up via `memo_preload`](#cache-warm-up-and-persistence)
- [`on_memo_store` hook fires on every cache write](#lifecycle-hooks)
- [Global default TTL and max size via `SafeMemoize.configure`](#global-configuration)
- [`memo_touch` resets the expiry clock without recomputing](#ttl-expiration)
- [`memo_refresh` force-recomputes and re-caches in one call](#cache-inspection)
- [`memo_age` and `memo_stale?` for TTL introspection](#cache-inspection)
- [Class-level `key:` option for shared cache key generation](#custom-cache-keys)
- [`shared_memo_age` and `shared_memo_stale?` for shared cache TTL inspection](#shared-cache)
- [Pluggable external cache stores — Redis, Rails.cache, or any custom adapter](#pluggable-cache-stores)
- [Global default store via `Configuration#default_store`](#pluggable-cache-stores)

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

Calling `memoize` on a method name that does not exist raises `ArgumentError` immediately at class definition time rather than at the first runtime call.

[↑ Back to features](#features)

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

Argument arrays, hashes, and strings are deep-frozen into an independent copy when the cache key is built, so mutating arguments after a call cannot corrupt or miss a cached entry.

[↑ Back to features](#features)

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

[↑ Back to features](#features)

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

[↑ Back to features](#features)

### Cache reset

```ruby
obj = MyService.new
obj.reset_memo(:current_user)                    # Clears all cached entries for one method
obj.reset_memo(:find_user, 42)                  # Clears only the cached call for find_user(42)
obj.reset_memo(:search, "ruby", page: 2)       # Clears one positional/keyword combination
obj.reset_all_memos                             # Clears all memoized values
```

[↑ Back to features](#features)

### Lifecycle hooks

Register callbacks that fire when cached entries are evicted or expire.

**`on_memo_evict`** fires when an entry is removed via `reset_memo`, `reset_all_memos`, or LRU eviction:

```ruby
obj.on_memo_evict do |cache_key, record|
  Rails.logger.info("Evicted #{cache_key[0]}(#{cache_key[1].join(", ")}), was: #{record[:value].inspect}")
end
```

**`on_memo_miss`** fires on every cache miss (i.e. the first call or after invalidation):

```ruby
obj.on_memo_miss do |cache_key, record|
  Rails.logger.debug("Cache miss: #{cache_key[0]}(#{cache_key[1].join(", ")})")
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

**`on_memo_store`** fires whenever a value is written to the cache — on a miss, via `warm_memo`, or via `load_memo`:

```ruby
obj.on_memo_store do |cache_key, record|
  Rails.logger.debug("Stored #{cache_key[0]}: #{record[:value].inspect}")
end
```

Multiple hooks of the same type can be registered and all will fire. Remove them with `clear_memo_hooks`:

```ruby
obj.clear_memo_hooks(:on_miss)    # Clears miss hooks only
obj.clear_memo_hooks(:on_hit)     # Clears hit hooks only
obj.clear_memo_hooks(:on_evict)   # Clears evict hooks only
obj.clear_memo_hooks(:on_expire)  # Clears expire hooks only
obj.clear_memo_hooks              # Clears all hooks
```

Hooks are per-instance and do not affect other objects of the same class.

#### Hook error isolation

Exceptions raised inside a hook never propagate to the caller. By default a warning is emitted to stderr:

```
[SafeMemoize] Hook error in on_miss: undefined method `log' for nil
```

Configure a custom handler via `SafeMemoize.configure`:

```ruby
SafeMemoize.configure do |c|
  c.on_hook_error = ->(error, hook_type, cache_key) {
    MyErrorTracker.capture(error, context: { hook: hook_type, key: cache_key })
  }
end
```

Set `c.on_hook_error = :raise` to re-raise exceptions instead of swallowing them.

[↑ Back to features](#features)

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

Use `memo_touch` to reset the expiry clock on a cached entry without recomputing its value:

```ruby
obj.memo_touch(:current_quote)               # Resets TTL to the original duration
obj.memo_touch(:current_quote, ttl: 120)     # Resets TTL to a new duration
# => true on success, false if the entry is not cached or already expired
```

Use `memo_refresh` to force-recompute a cached entry immediately and store the new value:

```ruby
obj.memo_refresh(:current_quote)             # Recomputes and re-caches
obj.memo_refresh(:find, 42)                  # Recomputes for one argument combination
```

[↑ Back to features](#features)

### Sliding window TTL

Add `ttl_refresh: true` to reset the expiry clock on every cache hit, so the entry only expires after a full TTL of inactivity:

```ruby
class SessionService
  prepend SafeMemoize

  def user_data(user_id)
    fetch_from_db(user_id)
  end
  memoize :user_data, ttl: 300, ttl_refresh: true
end
```

Without `ttl_refresh:`, the entry expires 300 seconds after it was first cached. With it, the clock resets on every read — the entry is evicted only if the method goes 300 seconds without being called. `ttl_refresh: true` requires `ttl:` to be set and works with both per-instance and `shared: true` memoization.

[↑ Back to features](#features)

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

[↑ Back to features](#features)

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

[↑ Back to features](#features)

### Cache warm-up and persistence

#### Batch warm-up via `memo_preload`

Use `memo_preload` to warm multiple argument combinations in one call. It calls the memoized method for each argument set, caches all results, and returns them in input order:

```ruby
obj.memo_preload(:find, [1], [2], [3])
# => [<User id=1>, <User id=2>, <User id=3>]
```

Each element is a separate argument list passed to the method, so keyword arguments work too:

```ruby
obj.memo_preload(:search, ["ruby"], ["rails"], ["rspec"])
```

#### Warming individual entries

Use `warm_memo` to pre-populate a cache entry without calling the method. The block provides the value:

```ruby
obj.warm_memo(:current_user) { User.find(session[:user_id]) }
obj.warm_memo(:find, 42) { cached_user }
obj.warm_memo(:search, "ruby", page: 2) { cached_results }
```

Pass `ttl:` to give the warmed entry an expiry:

```ruby
obj.warm_memo(:current_quote, ttl: 60) { cached_quote }
```

Useful for seeding the cache from a persistent store on startup, or overriding a cached value in tests.

#### Exporting and restoring the cache

`dump_memo` exports all live cached entries as a plain hash keyed by `[method, args, kwargs]`:

```ruby
snapshot = obj.dump_memo              # All methods
snapshot = obj.dump_memo(:find)       # One method only
# => { [:find, [1], {}] => <User>, [:find, [2], {}] => <User>, ... }
```

`load_memo` restores entries from a snapshot — merging into the existing cache without evicting unrelated entries:

```ruby
obj.load_memo(snapshot)
```

Together they enable cross-request or cross-process cache persistence:

```ruby
# On shutdown — save to Redis
redis.set("cache:#{user_id}", Marshal.dump(obj.dump_memo))

# On boot — restore from Redis
raw = redis.get("cache:#{user_id}")
obj.load_memo(Marshal.load(raw)) if raw
```

Loaded entries have no TTL — they persist until explicitly reset. Expired entries are excluded from `dump_memo` output, so snapshots never contain stale data.

[↑ Back to features](#features)

### Shared cache

Pass `shared: true` to store results on the class instead of per-instance. All instances share one cache, so the method is computed only once regardless of how many objects exist.

```ruby
class ConfigService
  prepend SafeMemoize

  def database_url
    ENV.fetch("DATABASE_URL")
  end

  def feature_flags
    fetch_flags_from_api
  end

  memoize :database_url, shared: true
  memoize :feature_flags, shared: true, ttl: 300
end

ConfigService.new.database_url  # computes
ConfigService.new.database_url  # returns cached — no recomputation
```

Class-level invalidation and inspection:

```ruby
ConfigService.reset_shared_memo(:feature_flags)       # Clears all entries for one method
ConfigService.reset_shared_memo(:find, user_id)       # Clears one argument combination
ConfigService.reset_all_shared_memos                  # Clears all shared cached entries
ConfigService.shared_memoized?(:database_url)         # => true
ConfigService.shared_memoized?(:find, user_id)        # Checks one argument combination
ConfigService.shared_memo_count                       # Total shared cached entries
ConfigService.shared_memo_count(:find)                # Entries for one method
ConfigService.shared_memo_age(:feature_flags)         # => 42.1  (seconds since cached)
ConfigService.shared_memo_stale?(:feature_flags)      # => false (TTL not yet elapsed)
```

`shared: true` supports `ttl:`, `ttl_refresh:`, `if:`, `unless:`, and `max_size:` options.

Pass `max_size:` to cap how many entries are kept across all instances. Eviction is LRU, tracked at the class level:

```ruby
memoize :find, shared: true, max_size: 500
```

Hooks (`on_memo_hit`, `on_memo_miss`, `on_memo_expire`, `on_memo_evict`) fire on the calling instance as usual.

[↑ Back to features](#features)

### Bulk memoization

Use `memoize_all` to memoize every public method defined on the class in one call:

```ruby
class ConfigService
  prepend SafeMemoize

  def database_url
    ENV.fetch("DATABASE_URL")
  end

  def redis_url
    ENV.fetch("REDIS_URL")
  end

  def feature_flags
    fetch_flags_from_api
  end

  memoize_all
end
```

All options accepted by `memoize` can be passed as shared options:

```ruby
memoize_all ttl: 60
memoize_all max_size: 100
memoize_all if: ->(result) { !result.nil? }
```

Use `except:` to skip specific methods:

```ruby
memoize_all except: [:version, :name]
```

Use `only:` to explicitly list the methods to memoize and skip all others:

```ruby
memoize_all only: [:database_url, :redis_url]
```

`only:` and `except:` are mutually exclusive — passing both raises `ArgumentError`.

By default only public methods defined directly on the class are memoized. Use `include_protected:` or `include_private:` to opt those visibilities in:

```ruby
memoize_all include_protected: true
memoize_all include_private: true
memoize_all include_protected: true, include_private: true
```

Inherited methods are never affected regardless of visibility.

[↑ Back to features](#features)

### Custom cache keys

By default the cache key is derived from the method name and all arguments. Use the `key:` option on `memoize` to set a class-level key generator that applies to every instance:

```ruby
class ReportService
  prepend SafeMemoize

  def generate(user_id, options)
    build_report(user_id, options)
  end
  memoize :generate, key: ->(user_id, _options) { user_id }
end

# All instances share the same key logic — calls with the same user_id share one cache entry
svc = ReportService.new
svc.generate(42, {format: :pdf})  # computes and caches under key 42
svc.generate(42, {format: :csv})  # cache hit — same key
```

For per-instance key overrides, use `memoize_with_custom_key` on an instance (takes priority over the class-level `key:` option):

```ruby
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

[↑ Back to features](#features)

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

obj.memo_ttl_remaining(:current_quote)           # => 47.231 (seconds until expiry)
obj.memo_ttl_remaining(:current_user)            # => nil    (no TTL set)
obj.memo_ttl_remaining(:find, 42)                # => 0      (not cached or already expired)

obj.memo_age(:current_quote)                     # => 12.8   (seconds since cached; nil if not cached)
obj.memo_stale?(:current_quote)                  # => false  (cached but TTL not yet elapsed)
obj.memo_stale?(:current_user)                   # => false  (no TTL — never stale)
```

`memo_inspect` returns all metadata for one cached entry in a single mutex-held read:

```ruby
obj.memo_inspect(:find, 42)
# => {
#      cached: true,
#      value: <result>,
#      hits: 5,
#      misses: 1,
#      ttl_remaining: 47.2,
#      age: 12.8,
#      custom_key: nil,
#      lru_position: 1
#    }
```

Returns `nil` when the entry is not cached.

[↑ Back to features](#features)

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

obj.cache_stats_for(:find)        # Stats scoped to one method
obj.cache_hit_rate                # => 84.0  (percentage)
obj.cache_miss_rate               # => 16.0  (percentage)
obj.cache_metrics_reset           # Clears all collected metrics
obj.cache_metrics_reset(:find)    # Clears metrics for one method only
```

Metrics are per-instance and reset independently from the cache itself — clearing metrics does not evict cached values.

[↑ Back to features](#features)

### Global configuration

Use `SafeMemoize.configure` to set defaults that apply to all subsequently memoized methods. Per-call options always take precedence over global defaults.

```ruby
SafeMemoize.configure do |c|
  c.default_ttl      = 300   # All memoized methods expire after 5 minutes unless overridden
  c.default_max_size = 100   # All memoized methods cap at 100 entries unless overridden
end
```

Both settings apply at definition time — methods already memoized before `configure` is called are not affected. Reset all defaults back to `nil` with:

```ruby
SafeMemoize.reset_configuration!
```

The configure block also accepts `on_hook_error`, `on_deprecation`, `active_support_notifications`, `statsd_client`, and `default_store` (covered in [Hook error isolation](#hook-error-isolation), [Deprecation](#deprecation), [ActiveSupport::Notifications](#activesupportnotifications), [StatsD](#statsd), and [Pluggable cache stores](#pluggable-cache-stores)).

[↑ Back to features](#features)

### ActiveSupport::Notifications

Enable opt-in integration with `ActiveSupport::Notifications` for Rails and other ActiveSupport-based stacks:

```ruby
SafeMemoize.configure do |c|
  c.active_support_notifications = true
end
```

Once enabled, SafeMemoize emits the following events through the standard notification pipeline:

| Event | Fires when |
|---|---|
| `cache_hit.safe_memoize` | A cached value is returned |
| `cache_miss.safe_memoize` | The method is called and no cached value exists |
| `cache_store.safe_memoize` | A value is written to the cache (miss, `warm_memo`, or `load_memo`) |
| `cache_evict.safe_memoize` | An entry is removed via `reset_memo`, `reset_all_memos`, or LRU eviction |
| `cache_expire.safe_memoize` | An expired TTL entry is pruned |

Each event payload includes:

```ruby
{
  method: :method_name,   # Symbol
  key:    cache_key,      # Array — the full cache key
  class:  "ClassName"     # String — the host class name
}
```

Subscribe to all SafeMemoize events via the standard ActiveSupport pattern:

```ruby
ActiveSupport::Notifications.subscribe(/\.safe_memoize$/) do |event|
  Rails.logger.debug("[cache] #{event.name} #{event.payload[:class]}##{event.payload[:method]}")
end
```

The integration is a no-op when ActiveSupport is not loaded — there is no overhead for non-Rails projects. `active_support_notifications` defaults to `false`.

[↑ Back to features](#features)

### StatsD

Route cache lifecycle events to any StatsD-compatible client via `SafeMemoize::Adapters::StatsD`. Assign the client once in your initializer:

```ruby
SafeMemoize.configure do |c|
  c.statsd_client = Datadog::Statsd.new("localhost", 8125)
end
```

SafeMemoize then calls `client.increment(metric, tags: [...])` on every cache event:

| Metric | Fires when |
|---|---|
| `safe_memoize.hit` | A cached value is returned |
| `safe_memoize.miss` | The method is called and no cached value exists |
| `safe_memoize.store` | A value is written to the cache (miss, `warm_memo`, or `load_memo`) |
| `safe_memoize.evict` | An entry is removed via `reset_memo`, `reset_all_memos`, or LRU eviction |
| `safe_memoize.expire` | An expired TTL entry is pruned |

Each call includes two tags: `method:method_name` and `class:ClassName`. The client must respond to `increment(metric, tags: [...])` — the interface used by `dogstatsd-ruby`, `statsd-instrument`, and most modern StatsD clients.

If the client raises, the error is rescued and a warning is emitted to stderr rather than propagated to the caller. `statsd_client` defaults to `nil` (disabled).

[↑ Back to features](#features)

### OpenTelemetry

`SafeMemoize::Adapters::OpenTelemetry` wraps the computation on each cache miss in an OpenTelemetry span, making memoized call costs visible in distributed traces. Assign a tracer once in your initializer:

```ruby
SafeMemoize.configure do |c|
  c.opentelemetry_tracer = OpenTelemetry.tracer_provider.tracer(
    "safe_memoize",
    SafeMemoize::VERSION
  )
end
```

SafeMemoize then wraps every cache miss (the actual method call, not cache hits) in a span named `"safe_memoize.compute"` with the following attributes:

| Attribute | Value |
|---|---|
| `safe_memoize.method` | Name of the memoized method |
| `safe_memoize.class` | Name of the host class |
| `safe_memoize.cache_hit` | Always `false` — only misses are traced |

Cache hits produce no spans, so tracing overhead is zero for cached calls. The adapter is compatible with any tracer that responds to `in_span(name, attributes:, &block)` — the interface provided by `opentelemetry-sdk`, `opentelemetry-api`, and no-op tracers alike. If `opentelemetry_tracer` is `nil` (the default), the adapter is completely bypassed.

[↑ Back to features](#features)

### Rails request-scope

SafeMemoize ships optional Rails integration as a separate require (zero overhead in non-Rails apps):

```ruby
require "safe_memoize/rails"
```

#### Controller concern

Include `SafeMemoize::Rails::RequestScoped` in any Rails controller that also `prepend SafeMemoize`. It automatically registers `after_action :reset_all_memos` so every instance memo is cleared at the end of each request — preventing state from leaking between requests when the controller object is reused:

```ruby
class ApplicationController < ActionController::Base
  prepend SafeMemoize
  include SafeMemoize::Rails::RequestScoped

  memoize :current_user
end
```

#### Service objects and non-controller classes

In plain classes (service objects, Active Model objects), include `RequestScoped` to gain `reset_request_memos` and call it manually at the appropriate point:

```ruby
class ReportService
  prepend SafeMemoize
  include SafeMemoize::Rails::RequestScoped

  def summary(id)
    # ...
  end
  memoize :summary
end

svc = ReportService.new
svc.summary(1)
svc.reset_request_memos  # clears all instance memos
```

#### Middleware for tracked instances

For service objects that should be reset automatically at request boundaries, use the Rack middleware together with `SafeMemoize::Rails.track`:

```ruby
# config/application.rb
config.middleware.use SafeMemoize::Rails::Middleware
```

```ruby
class ReportService
  prepend SafeMemoize

  def initialize
    SafeMemoize::Rails.track(self)  # register for auto-reset
  end

  def summary(id)
    # ...
  end
  memoize :summary
end
```

`SafeMemoize::Rails::Middleware` calls `reset_all_memos` on every tracked instance in the current thread at the end of the request, even if the app raises. Tracking is thread-local, so concurrent requests never interfere. The tracked list is cleared automatically after each reset.

[↑ Back to features](#features)

### Pluggable cache stores

By default, memoized results live in a per-instance hash — fast, but private to each object. Pass `store:` to route reads and writes through any external backend, enabling cross-process and distributed memoization.

#### Built-in: `Stores::Memory`

`Stores::Memory` is the built-in in-process store. It is used automatically by the `store:` default and is the reference implementation for custom adapters. You can pass your own instance to share a cache across multiple classes or to set a TTL on the shared store:

```ruby
SHARED_STORE = SafeMemoize::Stores::Memory.new

class UserService
  prepend SafeMemoize
  def find(id) = User.find(id)
  memoize :find, store: SHARED_STORE, ttl: 60
end

class PostService
  prepend SafeMemoize
  def author(post) = User.find(post.user_id)
  memoize :author, store: SHARED_STORE
end
```

The store is shared across all instances of a class, so the method is computed only once per unique argument set regardless of how many objects exist.

#### Redis adapter

Requires a Redis-compatible client (the `redis` gem or any drop-in replacement):

```ruby
require "safe_memoize/stores/redis"
require "redis"

REDIS_STORE = SafeMemoize::Stores::Redis.new(::Redis.new)

class PricingService
  prepend SafeMemoize
  def quote(sku) = api_fetch(sku)
  memoize :quote, store: REDIS_STORE, ttl: 300
end
```

Values and keys are serialized with `Marshal` (Base64-encoded via `Array#pack("m0")`). TTL is forwarded to Redis as `PX` (milliseconds) for sub-second precision. `clear` uses `SCAN` so it never blocks the Redis event loop. All keys are namespace-scoped (default: `"safe_memoize"`) so multiple stores or applications can share one Redis instance:

```ruby
REDIS_STORE = SafeMemoize::Stores::Redis.new(::Redis.new, namespace: "myapp:memo")
```

#### Rails.cache adapter

Wraps any `ActiveSupport::Cache::Store`, including `Rails.cache`:

```ruby
require "safe_memoize/stores/rails_cache"

RAILS_STORE = SafeMemoize::Stores::RailsCache.new(Rails.cache)

class CatalogService
  prepend SafeMemoize
  def fetch(slug) = Catalog.find_by!(slug: slug)
  memoize :fetch, store: RAILS_STORE, ttl: 600
end
```

Cached `nil` and `false` values are distinguished from a cache miss via a sentinel envelope, so falsy results are preserved correctly. TTL is forwarded as `expires_in:` for native store expiry. `clear` uses `delete_matched` scoped to the namespace.

#### Custom adapters

Subclass `SafeMemoize::Stores::Base` and implement the six-method contract:

```ruby
class MyStore < SafeMemoize::Stores::Base
  def read(key)         = ...  # return MISS if absent
  def write(key, value, expires_in: nil) = ...
  def delete(key)       = ...
  def clear             = ...
  def keys              = ...  # Array of stored keys
end
```

Use `SafeMemoize::Stores::Base::MISS` (a frozen sentinel object) as the return value from `read` when the key is absent — this distinguishes a cache miss from a cached `nil` or `false`.

#### Global default store

Set a default store for all compatible `memoize` calls without specifying `store:` on each one:

```ruby
SafeMemoize.configure do |c|
  c.default_store = SafeMemoize::Stores::Redis.new(::Redis.new)
end
```

A per-method `store:` option always takes precedence. Methods using `max_size:` or `shared:` silently bypass the global default (LRU and shared-mode use their own storage). An invalid value raises `ArgumentError` at `memoize` time. Reset with `SafeMemoize.reset_configuration!`.

#### Compatibility

The `store:` option composes with `ttl:`, `ttl_refresh:`, `if:`, `unless:`, lifecycle hooks, and cache metrics. It is incompatible with `max_size:` (use the store adapter's own eviction) and `shared:` (raise `ArgumentError` if combined).

[↑ Back to features](#features)

### Deprecation

SafeMemoize ships a structured deprecation helper for gem authors who build on top of it:

```ruby
SafeMemoize.deprecate(
  "MyGem::OldHelper",
  message: "Use MyGem::NewHelper instead",
  horizon: "2.0.0"
)
# => [SafeMemoize] DEPRECATED: MyGem::OldHelper — Use MyGem::NewHelper instead (removal horizon: 2.0.0)
```

The warning is emitted to stderr by default. Configure a custom handler via `SafeMemoize.configure`:

```ruby
SafeMemoize.configure do |c|
  c.on_deprecation = ->(msg) { Rails.logger.warn(msg) }
end
```

To raise on deprecation warnings in test environments:

```ruby
SafeMemoize.configure do |c|
  c.on_deprecation = ->(msg) { raise msg }
end
```

[↑ Back to features](#features)

## Ractor compatibility

SafeMemoize is **not Ractor-compatible** in its current form. Passing a class that uses `memoize` into a `Ractor.new` block raises `RuntimeError: defined with an un-shareable Proc in a different Ractor`. There are two root causes:

1. **Non-shareable closures.** `ClassMethods#memoize` builds anonymous modules using `define_method` with blocks that close over local variables (`ttl`, `max_size`, `condition`, `shared_mutex`, …). Ruby marks those Procs as non-Ractor-shareable, so the host class cannot be sent to a Ractor.

2. **Mutable module-level state.** `SafeMemoize.configuration` reads `@configuration` from the `SafeMemoize` module — a mutable ivar on a shared constant — which raises `Ractor::IsolationError` from a non-main Ractor. This affects every memoized call because hooks and adapters always read the configuration.

**Workaround:** Use Ruby Threads instead of Ractors — SafeMemoize is fully thread-safe via double-check locking and per-instance Mutexes. If you need true parallelism with Ractors, perform computation inside the Ractor without memoization and send frozen results back via `Ractor#send`.

Ractor support is tracked in the v1.0.0 roadmap. The fix would require replacing closed-over variables with frozen shareable bindings and making `Configuration` a frozen value object, which is a significant redesign.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests. You can also run `bin/console` for an interactive prompt.

To run the benchmark suite: `bundle exec ruby benchmarks/benchmark.rb`.

To generate API documentation locally: `bundle exec rake doc`. Output is written to `doc/` (gitignored). The online reference is published automatically to [RubyDoc.info](https://rubydoc.info/gems/safe_memoize) on every release. Install `memery` and `memo_wise` first if you want comparison columns against those gems.

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

## Public API and versioning guarantee

From **v1.0.0** onwards SafeMemoize follows [Semantic Versioning](https://semver.org/). The table below declares every constant, method, and option key that forms the public contract. If you only call items listed here, you are guaranteed that:

- **Patch** releases (1.x.**y**) contain bug fixes only — no behaviour changes.
- **Minor** releases (1.**x**.0) add new features in a backwards-compatible way.
- **Major** releases (**x**.0.0) may break the items below; a migration guide will be published for every such release.

Anything **not** listed here — internal modules, private methods, `@__safe_memo_*__` ivars, the structure of the cache hash itself — is subject to change without notice in any release, including patch releases.

### Top-level module

| Symbol | Kind | Notes |
|---|---|---|
| `SafeMemoize::VERSION` | constant | Semver string, always present |
| `SafeMemoize::Error` | class | Base error class (`< StandardError`) for rescuing any SafeMemoize-raised exception |
| `SafeMemoize.configure { \|c\| … }` | module method | Yields `Configuration`; sets global defaults |
| `SafeMemoize.configuration` | module method | Returns the current `Configuration` |
| `SafeMemoize.reset_configuration!` | module method | Restores all configuration to defaults |
| `SafeMemoize.deprecate(subject, message:, horizon:)` | module method | Emits a structured deprecation warning |

### `memoize` DSL (class method, added by `prepend SafeMemoize`)

| Option key | Type | Default | Notes |
|---|---|---|---|
| `ttl:` | `Numeric \| nil` | `nil` | Seconds until entry expires |
| `ttl_refresh:` | `Boolean` | `false` | Sliding window — resets clock on every hit |
| `max_size:` | `Integer \| nil` | `nil` | LRU entry limit per method |
| `if:` | `Symbol \| Proc \| nil` | `nil` | Store only when truthy |
| `unless:` | `Symbol \| Proc \| nil` | `nil` | Store only when falsy |
| `shared:` | `Boolean` | `false` | Class-level shared cache |
| `key:` | `Proc \| nil` | `nil` | Class-level custom key generator |
| `store:` | `Stores::Base \| nil` | `nil` | External cache store adapter; incompatible with `max_size:` and `shared:` |

### `memoize_all` options (class method)

All `memoize` option keys above, plus:

| Option key | Type | Default |
|---|---|---|
| `except:` | `Array<Symbol>` | `[]` |
| `only:` | `Array<Symbol>` | `[]` |
| `include_protected:` | `Boolean` | `false` |
| `include_private:` | `Boolean` | `false` |

### Instance methods (public)

**Inspection**

| Method | Returns |
|---|---|
| `memoized?(method_name, *args, **kwargs)` | `Boolean` |
| `memo_count(method_name = nil)` | `Integer` |
| `memo_keys(method_name = nil)` | `Array` |
| `memo_values(method_name = nil)` | `Array` |
| `memo_inspect(method_name, *args, **kwargs)` | `Hash \| nil` |
| `memo_ttl_remaining(method_name, *args, **kwargs)` | `Numeric \| nil` |
| `memo_age(method_name, *args, **kwargs)` | `Numeric \| nil` |
| `memo_stale?(method_name, *args, **kwargs)` | `Boolean` |

**Invalidation and mutation**

| Method | Returns |
|---|---|
| `reset_memo(method_name, *args, **kwargs)` | `nil` |
| `reset_all_memos` | `nil` |
| `memo_touch(method_name, *args, ttl: nil, **kwargs)` | `Boolean` |
| `memo_refresh(method_name, *args, **kwargs)` | cached value |

**Warm-up and persistence**

| Method | Returns |
|---|---|
| `warm_memo(method_name, *args, ttl: nil, **kwargs)` | cached value |
| `memo_preload(method_name, *arg_sets)` | `Array` |
| `dump_memo(method_name = nil)` | `Hash` |
| `load_memo(snapshot)` | `nil` |

**Lifecycle hooks**

| Method | Fires when |
|---|---|
| `on_memo_hit { \|key\| … }` | cache hit |
| `on_memo_miss { \|key\| … }` | cache miss |
| `on_memo_store { \|key, value\| … }` | value written |
| `on_memo_expire { \|key\| … }` | TTL expires |
| `on_memo_evict { \|key\| … }` | LRU eviction |
| `clear_memo_hooks(hook_type = nil)` | — |

**Metrics**

| Method | Returns |
|---|---|
| `cache_stats` | `Hash` |
| `cache_stats_for(method_name)` | `Hash` |
| `cache_hit_rate` | `Float` |
| `cache_miss_rate` | `Float` |
| `cache_metrics_reset(method_name = nil)` | `nil` |

**Custom keys**

| Method | Notes |
|---|---|
| `memoize_with_custom_key(method_name) { \|*args, **kwargs\| … }` | Instance-level key generator |
| `clear_custom_keys(method_name = nil)` | Remove one or all key generators |

### Shared-cache class methods (added when any method uses `shared: true`)

| Method | Returns |
|---|---|
| `reset_shared_memo(method_name, *args, **kwargs)` | `nil` |
| `reset_all_shared_memos` | `nil` |
| `shared_memoized?(method_name, *args, **kwargs)` | `Boolean` |
| `shared_memo_count(method_name = nil)` | `Integer` |
| `shared_memo_age(method_name, *args, **kwargs)` | `Numeric \| nil` |
| `shared_memo_stale?(method_name, *args, **kwargs)` | `Boolean` |

### `SafeMemoize::Configuration` attributes

| Attribute | Type | Default |
|---|---|---|
| `default_ttl` | `Numeric \| nil` | `nil` |
| `default_max_size` | `Integer \| nil` | `nil` |
| `on_deprecation` | `Proc \| nil` | `nil` (writes to stderr) |
| `on_hook_error` | `Proc \| nil` | `nil` (warns to stderr) |
| `active_support_notifications` | `Boolean` | `false` |
| `statsd_client` | `Object \| nil` | `nil` |
| `opentelemetry_tracer` | `Object \| nil` | `nil` |
| `default_store` | `Stores::Base \| nil` | `nil` |

### Store adapter classes (v1.1.0+)

| Class | Require | Notes |
|---|---|---|
| `SafeMemoize::Stores::Base` | auto | Abstract base — subclass to build custom adapters; exposes `MISS` sentinel |
| `SafeMemoize::Stores::Memory` | auto | Built-in in-process store; reference implementation |
| `SafeMemoize::Stores::Redis` | `"safe_memoize/stores/redis"` | Redis-backed adapter; Marshal serialization; `PX` TTL |
| `SafeMemoize::Stores::RailsCache` | `"safe_memoize/stores/rails_cache"` | `ActiveSupport::Cache::Store` wrapper |

### Opt-in extensions (not guaranteed until their owning milestone ships)

The following are available now but reside under `require "safe_memoize/rails"` and are not covered by the semver guarantee until the v1.x milestone that owns them is declared stable:

- `SafeMemoize::Rails` module (`track`, `reset_tracked!`)
- `SafeMemoize::Rails::RequestScoped` concern
- `SafeMemoize::Rails::Middleware` Rack middleware
- `SafeMemoize::Adapters::StatsD`
- `SafeMemoize::Adapters::OpenTelemetry`

## Ruby version support

### Supported versions

SafeMemoize requires **Ruby ≥ 3.3**. Every non-EOL Ruby version in the table below is actively tested in CI and receives bug-fix backports for critical issues.

| Ruby | Status | EOL |
|---|---|---|
| 3.3 | Supported | Mar 2027 |
| 3.4 | Supported | Mar 2028 |
| 4.0 | Supported | ~ Dec 2028 |

EOL dates follow the [Ruby maintenance schedule](https://www.ruby-lang.org/en/downloads/branches/).

### Policy

- **Dropping an EOL version is a minor-version change**, not a major one — it will appear in the CHANGELOG under `### Removed` and the gemspec `required_ruby_version` will be updated accordingly.
- SafeMemoize targets the **current stable release plus the two previous non-EOL minors** at any given time. When Ruby releases a new version in December, CI gains a new column; when a version reaches EOL the next minor release removes it.
- **No patch release will ever raise the minimum Ruby version.** Only `x.y.0` minor releases may do so.
- Prerelease Rubies (dev / preview builds) are not officially supported but breakage is investigated on a best-effort basis.

### History

| Dropped in | Ruby version removed |
|---|---|
| v0.5.0 | Ruby 3.2 (reached EOL) |

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the planned path to v1.0.0 and beyond, including upcoming features, API stability goals, and the versioning policy.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eclectic-coding/safe_memoize.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
