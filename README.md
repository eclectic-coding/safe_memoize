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
- [`SafeMemoize::Adapters::ConcurrentRuby` — optional `concurrent-ruby` store with parallel-read locking](#concurrent-ruby-adapter)
- [Class-level `.safe_memoize_store=` — set a per-class default store without touching global config](#class-level-default-store-safe_memoize_store)
- [Fiber-local memoization via `fiber_local: true` — isolated per-fiber cache, no mutex, works with Async/Falcon](#fiber-local-memoization)
- [Ractor-safe shared cache via `ractor_safe: true` — supervisor Ractor replaces the Mutex; worker Ractors can call the memoized method directly](#ractor-safe-shared-cache)
- [Cache namespacing — per-method `namespace:`, class-level `.safe_memoize_namespace=`, and global `Configuration#namespace` for multi-tenant and versioned deployments](#cache-namespacing)
- [Named shared caches via `shared_cache: "name"` — cross-class cache sharing backed by a globally-registered store](#named-shared-caches)
- [Automatic cache busting via `cache_bust:` — version-token-based invalidation; works with ActiveRecord `updated_at` and any comparable value](#automatic-cache-busting)
- [Plugin / extension architecture — `SafeMemoize::Extension` DSL for adding custom `memoize` options and global lifecycle handlers without monkey-patching](#plugin--extension-architecture)
- [Per-class default options via `safe_memoize_options` — set TTL, max size, copy-on-read, and other defaults for every `memoize` call on the class without repeating them](#per-class-default-options-safe_memoize_options)
- [Copy-on-read via `copy_on_read: true` — returns a `dup`/`deep_dup` on every cache read to protect shared cached state from caller mutation](#copy-on-read)
- [Cache invalidation groups via `group:` — tag related methods with a group name and bust them all with a single `reset_memo_group` call](#cache-invalidation-groups)

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

### Cache invalidation groups

Tag related methods with `group:` and bust them all at once with a single `reset_memo_group` call:

```ruby
class RepoService
  prepend SafeMemoize

  def find_user(id) = db.query("SELECT * FROM users WHERE id=?", id)
  def find_post(id) = db.query("SELECT * FROM posts WHERE id=?", id)
  def site_config    = db.query("SELECT * FROM config LIMIT 1")

  memoize :find_user,  group: :database
  memoize :find_post,  group: :database
  memoize :site_config                    # no group — unaffected by group reset
end

svc = RepoService.new
svc.find_user(1)
svc.find_post(42)
svc.site_config

svc.reset_memo_group(:database)          # invalidates find_user and find_post only
svc.memoized?(:site_config)              # => true — unaffected
```

For `shared: true` methods, use the class method:

```ruby
class CatalogService
  prepend SafeMemoize

  def products = fetch_all_products
  def categories = fetch_all_categories

  memoize :products,   shared: true, group: :catalog
  memoize :categories, shared: true, group: :catalog
end

CatalogService.reset_shared_memo_group(:catalog)    # clears shared cache for both methods
```

#### Introspection

```ruby
svc.memo_groups                              # => [:database]  — all groups on the class
svc.memo_group_methods(:database)            # => [:find_user, :find_post]
CatalogService.safe_memo_groups              # => [:catalog]
CatalogService.safe_memo_group_methods(:catalog)  # => [:products, :categories]
```

#### Class-wide group default

Use `safe_memoize_options` to assign all subsequently memoized methods to the same group:

```ruby
class ApiClient
  prepend SafeMemoize
  safe_memoize_options group: :api

  def users  = http.get("/users")
  def orders = http.get("/orders")

  memoize :users               # group: :api
  memoize :orders              # group: :api
  memoize :health, group: nil  # override — no group
end
```

A method belongs to at most one group at a time; re-memoizing with a different `group:` moves it.

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

### Fiber-local memoization

Pass `fiber_local: true` to store results in `Fiber[:__safe_memoize__]` rather than instance variables. Each fiber gets its own isolated cache that is automatically discarded when the fiber terminates — no explicit cleanup required.

This is the right choice for Fiber-based concurrency frameworks like [Async](https://github.com/socketry/async), [Falcon](https://github.com/socketry/falcon), and Rails async controllers, where multiple fibers share the same object instance and must not see each other's cached values.

```ruby
class ApiClient
  prepend SafeMemoize

  def fetch(path)
    http_get(path)
  end

  memoize :fetch, fiber_local: true
end

client = ApiClient.new

Fiber.new { client.fetch("/a") }.resume  # computes in this fiber
Fiber.new { client.fetch("/a") }.resume  # computes again — isolated cache
```

`fiber_local: true` works with all standard options: `ttl:`, `ttl_refresh:`, `max_size:`, `if:`, `unless:`, and `key:`. It is incompatible with `shared:` and `store:` (both raise `ArgumentError`).

No `Mutex` is acquired because fibers within a single thread are cooperative — only one fiber executes at a time.

**Fiber isolation guarantee**: Ruby's `Fiber.new` inherits the parent fiber's local storage by default. SafeMemoize detects inherited stores via an ownership sentinel and replaces them with a fresh, isolated store on first write, so child fibers never see the parent's cached entries.

Instance-level inspection and reset for fiber-local entries use dedicated methods:

```ruby
obj.fiber_local_memoized?(:fetch, "/a")  # true / false for the current fiber
obj.reset_fiber_memo(:fetch)             # clear all entries for :fetch in current fiber
obj.reset_fiber_memo(:fetch, "/a")       # clear one specific entry
obj.reset_all_fiber_memos                # clear all fiber-local entries for this instance
```

Lifecycle hooks and cache metrics work the same as for regular memoization. The existing `memoized?`, `reset_memo`, and `memo_count` methods operate on the instance-variable cache; use the `fiber_local_*` / `reset_fiber_*` API for fiber-local entries.

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

### Plugin / extension architecture

`SafeMemoize::Extension` lets third-party gems add custom `memoize` options and global lifecycle handlers without monkey-patching SafeMemoize internals.

```ruby
module MyExtension
  extend SafeMemoize::Extension

  # Declare a custom memoize option.
  # The processor block runs at memoize definition time and returns
  # a Hash of standard memoize options to inject.
  handles_option :active_record_bust do |_value, _method_name, _options|
    { cache_bust: -> { send(:updated_at) } }
  end

  # Register a global lifecycle handler (fires for every memoized method).
  on_cache_event :miss do |klass, method_name, _cache_key, _record|
    Rails.logger.debug "cache miss: #{klass}##{method_name}"
  end
end

SafeMemoize.register_extension(:active_record_bust, MyExtension)
```

Once registered, the custom option is accepted by `memoize`:

```ruby
class OrderDecorator
  prepend SafeMemoize

  def initialize(order) = (@order = order)

  def summary = expensive_compute(@order)
  memoize :summary, active_record_bust: true
  # ↑ MyExtension injects cache_bust: -> { updated_at } automatically
end
```

#### `handles_option` processor return values

The processor block must return a Hash of **standard** `memoize` option keys to inject. Any standard option is supported:

```ruby
handles_option :short_lived  do |ttl, _, _| { ttl: ttl }        end
handles_option :versioned    do |ns,  _, _| { namespace: ns }    end
handles_option :via_redis    do |store, _, _| { store: store }   end
handles_option :bust_on      do |fn,  _, _| { cache_bust: fn }   end
```

#### `on_cache_event` handler signature

```ruby
on_cache_event :on_hit, :on_miss do |klass, method_name, cache_key, record|
  # klass       — the class whose instance triggered the event
  # method_name — bare Symbol (namespace stripped)
  # cache_key   — full cache key Array
  # record      — { value:, expires_at:, cached_at: } or nil
end
```

Valid event types: `:on_hit`, `:on_miss`, `:on_store`, `:on_expire`, `:on_evict`.

#### Registry API

```ruby
SafeMemoize.register_extension(:name, MyExtension)
SafeMemoize.unregister_extension(:name)
SafeMemoize.extensions               # { name: MyExtension, … }
SafeMemoize.reset_extensions!        # clear registry (test teardown)
SafeMemoize.extension_for_option(:active_record_bust)  # → MyExtension
```

#### Duck-type compatibility

An extension does not need to `extend SafeMemoize::Extension`. Any object responding to `handled_options`, `process_memoize_option`, and `dispatch_cache_event` is accepted.

#### Constraints

- Unknown `memoize` keywords raise `ArgumentError` unless a registered extension claims them — typos are still caught.
- `on_cache_event` handlers run on the main Ractor only; they are silently skipped from worker Ractors.

[↑ Back to features](#features)

### Automatic cache busting

`cache_bust:` ties a method's cache lifetime to a version token derived from instance state. When the token changes, the old cache key no longer matches — the method is recomputed automatically, with no explicit `reset_memo` required.

```ruby
class OrderDecorator
  prepend SafeMemoize

  def initialize(order)
    @order = order
  end

  def summary = expensive_compute(@order)
  memoize :summary, cache_bust: -> { @order.updated_at }
  # Saving @order advances updated_at → next call is a cache miss → fresh result
end
```

#### Token forms

```ruby
# Proc/lambda — instance_exec gives full access to self, ivars, and methods
memoize :report, cache_bust: -> { @record.updated_at }

# Symbol — calls the named instance method
memoize :data,   cache_bust: :cache_version

# Compound token — any comparable value works, including arrays
memoize :stats,  cache_bust: -> { [@version, tenant_id] }
```

#### How it works

The token is incorporated into the cache key alongside the normal arguments. When the token changes, the old key simply produces no match — there is no deletion. Stale entries accumulate silently until:
- They expire via `ttl:`, or
- They are evicted by the store adapter's own eviction policy, or
- You call `reset_memo(:method_name)` or `reset_all_memos` explicitly.

For unbounded caches, pair with `ttl:` or a `max_size:`-capable store to limit memory growth:

```ruby
memoize :summary, cache_bust: -> { @order.updated_at }, ttl: 3600
```

#### Introspection

All introspection methods work with the **current** token:

```ruby
obj.memoized?(:summary)       # true only if the current token's entry is live
obj.memo_count(:summary)      # counts ALL live versions (current + stale)
obj.reset_memo(:summary)      # clears ALL versions
```

#### Constraints

- Incompatible with `key:` — both define the cache key shape; raises `ArgumentError` at `memoize` time.
- Composes with `namespace:`, `ttl:`, `if:`, `unless:`, and `shared_cache:`.

[↑ Back to features](#features)

### Named shared caches

`shared_cache: "name"` routes all cache reads and writes through a globally-registered store, letting unrelated classes share the same cached data without any object-level coordination.

```ruby
class OrderService
  prepend SafeMemoize

  def find(id) = Order.find(id)
  memoize :find, shared_cache: "orders"
end

class OrderPresenter
  prepend SafeMemoize

  def find(id) = Order.find(id)          # same method signature
  memoize :find, shared_cache: "orders"  # same backing store
end

# After OrderService.new.find(42) computes the value, OrderPresenter.new.find(42)
# returns the cached result — the method body is not called a second time.
```

#### Registry API

```ruby
SafeMemoize.shared_cache("orders")                           # get or auto-create a Memory store
SafeMemoize.register_shared_cache("orders", my_redis_store)  # use a custom adapter
SafeMemoize.clear_shared_cache("orders")                     # evict all entries
SafeMemoize.drop_shared_cache("orders")                      # remove from registry
SafeMemoize.shared_caches                                    # { "orders" => #<Memory>, … }
SafeMemoize.reset_shared_caches!                             # wipe registry (test teardown)
```

#### Custom adapter

Register a Redis-backed (or any `Stores::Base`) store **before** any class that references the name is loaded — the store is captured at `memoize` definition time:

```ruby
# config/initializers/safe_memoize.rb
require "safe_memoize/stores/redis"

SafeMemoize.register_shared_cache(
  "orders",
  SafeMemoize::Stores::Redis.new(Redis.new, namespace: "myapp:orders")
)
```

#### Key scoping and namespace composition

By default two classes sharing the same cache name and method name share the same key:

```ruby
# OrderService#find(42) and OrderPresenter#find(42) → same key [:find, [42], {}]
```

Add `namespace:` when you want class-scoped entries within the same store:

```ruby
memoize :find, shared_cache: "orders", namespace: "service"    # [:"service:find", [42], {}]
memoize :find, shared_cache: "orders", namespace: "presenter"  # [:"presenter:find", [42], {}]
```

#### Constraints

- Incompatible with `shared:`, `store:`, `fiber_local:`, `ractor_safe:`, and `max_size:` (use the store adapter's own eviction policy).
- `register_shared_cache` must be called before the class that uses the name is defined.
- Test suites should call `SafeMemoize.reset_shared_caches!` in an `after` hook to prevent state leaking between examples.

[↑ Back to features](#features)

### Cache namespacing

Namespacing adds a string prefix to every cache key, scoping entries to a logical partition. It is transparent to the rest of the API — introspection methods always accept and return bare method names regardless of the active namespace.

Namespacing is particularly useful for:

- **Versioned deployments** — change the namespace to instantly invalidate all in-flight cached values without flushing the whole store.
- **Multi-tenant applications** — scope keys per tenant so different tenants' data cannot collide, even when sharing the same in-process hash or external store.

#### Per-method namespace

Pass `namespace:` to a single `memoize` call:

```ruby
class ApiClient
  prepend SafeMemoize

  def fetch(id) = http_get(id)
  memoize :fetch, namespace: "v2"  # keys: [:"v2:fetch", [id], {}]
end
```

#### Class-level namespace

Set `.safe_memoize_namespace=` to apply a namespace to every `memoize` call on the class that doesn't specify its own:

```ruby
class OrderService
  prepend SafeMemoize
  self.safe_memoize_namespace = "orders"

  def find(id) = Order.find(id)
  memoize :find                       # keys: [:"orders:find", ...]

  def stats = compute_stats
  memoize :stats, namespace: "v2"     # per-method wins → [:"v2:stats", ...]
end
```

#### Global namespace

Set via `SafeMemoize.configure` to apply a namespace to every memoized method in the process that has no per-method or class-level namespace:

```ruby
SafeMemoize.configure do |c|
  c.namespace = "v1.2.3"   # bump this string on each deploy to bust all cached values
end
```

#### Resolution priority

`namespace:` option on `memoize` > `.safe_memoize_namespace` on the class > `SafeMemoize.configuration.namespace`

#### Constraints

- Namespace strings must be non-empty and must not contain `:`.
- Namespacing works with all memoize paths (standard, `store:`, `fiber_local:`, `shared:`, `ractor_safe:`).
- Adding or changing a namespace changes the cache keys, so existing entries become unreachable (they expire naturally or can be cleared by `reset_all_memos`).

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

The configure block also accepts `on_hook_error`, `on_deprecation`, `active_support_notifications`, `statsd_client`, `default_store`, and `namespace` (covered in [Hook error isolation](#hook-error-isolation), [Deprecation](#deprecation), [ActiveSupport::Notifications](#activesupportnotifications), [StatsD](#statsd), [Pluggable cache stores](#pluggable-cache-stores), and [Cache namespacing](#cache-namespacing)).

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

#### concurrent-ruby adapter

`SafeMemoize::Adapters::ConcurrentRuby` replaces the default `Mutex`-backed store with `Concurrent::Map` and `Concurrent::ReentrantReadWriteLock` from the [`concurrent-ruby`](https://github.com/ruby-concurrency/concurrent-ruby) gem. Multiple readers proceed in parallel; writers still get exclusive access. For read-heavy hot paths this can meaningfully reduce lock contention.

`concurrent-ruby` is a **soft dependency** — it is not required at runtime unless you instantiate the adapter. Add it to your own `Gemfile`:

```ruby
gem "concurrent-ruby"
```

Opt in per class:

```ruby
class HotService
  prepend SafeMemoize
  self.safe_memoize_store = SafeMemoize::Adapters::ConcurrentRuby.new

  def expensive(id) = db.find(id)
  memoize :expensive
end
```

Or set it globally:

```ruby
SafeMemoize.configure do |c|
  c.default_store = SafeMemoize::Adapters::ConcurrentRuby.new
end
```

A `LoadError` with an actionable message is raised at instantiation if `concurrent-ruby` is not installed. The adapter is incompatible with `max_size:` and `shared:` (same constraints as all external stores).

#### Class-level default store (`safe_memoize_store=`)

Set a default store for every `memoize` call on a single class without touching the global configuration:

```ruby
class ReportService
  prepend SafeMemoize
  self.safe_memoize_store = SafeMemoize::Adapters::ConcurrentRuby.new

  def summary = compute_summary   # routed through ConcurrentRuby
  memoize :summary
end
```

The resolution order is: per-method `store:` → class-level `.safe_memoize_store` → global `SafeMemoize.configuration.default_store`. Assign `nil` to clear. An invalid value (not a `Stores::Base` instance) raises `ArgumentError`.

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

## Per-class default options (`safe_memoize_options`)

`safe_memoize_options` sets option defaults for every `memoize` call on the class, eliminating repetition when many methods share the same TTL, LRU cap, or other option. Per-call options still take precedence; class defaults take precedence over global `SafeMemoize.configure` defaults.

```ruby
class ApiClient
  prepend SafeMemoize
  safe_memoize_options ttl: 60, max_size: 200, copy_on_read: true

  def fetch(id) = http.get(id)
  memoize :fetch                     # uses ttl: 60, max_size: 200, copy_on_read: true

  def list = http.get("/all")
  memoize :list, ttl: 300            # uses max_size: 200, copy_on_read: true; ttl: 300 overrides
end
```

Accepted options are the same as `memoize` minus the mode-switch options (`shared:`, `fiber_local:`, `ractor_safe:`, `shared_cache:`), which must be specified per call because they change the entire execution path:

```ruby
safe_memoize_options(
  ttl:          60,
  max_size:     100,
  ttl_refresh:  true,
  copy_on_read: true,
  namespace:    "v2",
  if:           ->(v) { v.present? },
  cache_bust:   :updated_at
)
```

Call with no arguments to clear all class-level defaults:

```ruby
MyClass.safe_memoize_options   # clears — subsequent memoize calls use global config or per-call options only
```

[↑ Back to features](#features)

## Copy-on-read

Pass `copy_on_read: true` to `memoize` to return a `dup` (or `deep_dup` when available, e.g. ActiveRecord objects) of the stored value on every cache read. This prevents callers from mutating the shared cached object:

```ruby
class ConfigService
  prepend SafeMemoize

  def settings = {host: "localhost", port: 8080}
  memoize :settings, copy_on_read: true
end

svc = ConfigService.new
result = svc.settings
result[:host] = "mutated"   # only affects the caller's copy

svc.settings[:host]         # => "localhost" — cache is unaffected
```

`nil` and frozen values are returned as-is (no dup attempted). `copy_on_read:` works across all cache paths: per-instance hash, LRU (`max_size:`), class-level shared (`shared: true`), fiber-local (`fiber_local: true`), and external stores. It is incompatible with `ractor_safe: true` (ractor-safe values are always frozen; rely on that guarantee instead).

Set it as a class-wide default with `safe_memoize_options`:

```ruby
class ReportService
  prepend SafeMemoize
  safe_memoize_options copy_on_read: true

  def summary = build_summary
  memoize :summary

  def details = build_details
  memoize :details
end
```

[↑ Back to features](#features)

## Ractor-safe shared cache

Pass `ractor_safe: true` (together with `shared: true`) to replace the `Mutex`-backed class-level shared cache with a supervisor `Ractor` that owns the mutable cache hash. All reads and writes are serialised through message passing, so the cache is safe to use from multiple Ractors.

```ruby
class PriceService
  prepend SafeMemoize

  def fetch_price(item_id)
    external_api.get("/prices/#{item_id}")
  end

  memoize :fetch_price, shared: true, ractor_safe: true, ttl: 300
end

# Main Ractor — multiple threads share one cache entry
20.times.map { Thread.new { PriceService.new.fetch_price(42) } }.map(&:value)

# Worker Ractors also read from and write to the same supervisor cache
result = Ractor.new(PriceService) { |s| s.new.fetch_price(42) }.take
```

### How it works

- A **supervisor `Ractor`** is created once per class the first time a `ractor_safe: true` method is memoized. It owns a plain Ruby `Hash` and responds to `:fetch`, `:store`, `:delete_all`, `:delete_one`, `:clear`, `:memoized`, and `:count` messages.
- The memoize **wrapper Proc** is frozen via `Ractor.make_shareable` before being registered with `define_method`, so the class can be passed directly into `Ractor.new` blocks.
- Cached values are deep-frozen via `Ractor.make_shareable`. Values that cannot be made shareable (e.g. a `Mutex`) raise `ArgumentError`.
- **Thread safety** inside the main Ractor (multiple threads) is handled by per-call tags (`Thread.current.object_id`) combined with `Ractor.receive_if`, so concurrent threads never consume each other's replies.
- `ttl:` is supported. Expired entries are skipped by the supervisor's `:fetch` handler.

### Constraints

`ractor_safe: true` is intentionally limited. The following options are incompatible and raise `ArgumentError` at `memoize` time:

| Option | Reason |
|---|---|
| `if:` / `unless:` | Conditional Procs are non-Ractor-shareable |
| `max_size:` | LRU order tracking requires a non-shareable Ruby `Hash` |
| `ttl_refresh:` | Requires re-examining the record on every hit |
| `key:` | Custom key Procs are non-Ractor-shareable |
| `store:` | External adapters are incompatible with the supervisor model |

### Class-level API

```ruby
PriceService.ractor_memoized?(:fetch_price, 42)     # → true / false
PriceService.ractor_memo_count                       # → total live entries
PriceService.ractor_memo_count(:fetch_price)         # → entries for one method
PriceService.reset_ractor_memo(:fetch_price, 42)     # → clear one entry
PriceService.reset_ractor_memo(:fetch_price)         # → clear all entries for method
PriceService.reset_all_ractor_memos                  # → clear entire shared cache
```

[↑ Back to features](#features)

## Ractor compatibility

Regular `memoize` (without `ractor_safe: true`) is **not Ractor-compatible**. Passing a class that uses `memoize` into a `Ractor.new` block raises `RuntimeError: defined with an un-shareable Proc in a different Ractor`. There are two root causes:

1. **Non-shareable closures.** `ClassMethods#memoize` builds anonymous modules using `define_method` with blocks that close over local variables (`ttl`, `max_size`, `condition`, `shared_mutex`, …). Ruby marks those Procs as non-Ractor-shareable, so the host class cannot be sent to a Ractor.

2. **Mutable module-level state.** `SafeMemoize.configuration` reads `@configuration` from the `SafeMemoize` module — a mutable ivar on a shared constant — which raises `Ractor::IsolationError` from a non-main Ractor.

**Workaround for shared caches:** use `memoize :method, shared: true, ractor_safe: true` (see [Ractor-safe shared cache](#ractor-safe-shared-cache) above).

**Workaround for per-instance caches:** Use Ruby Threads instead of Ractors — SafeMemoize is fully thread-safe via double-check locking and per-instance Mutexes. If you need true parallelism with Ractors, perform computation inside the Ractor without memoization and send frozen results back via `Ractor#send`.

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
| `SafeMemoize.shared_cache(name)` | module method | Returns named store, auto-creating a `Memory` store if absent |
| `SafeMemoize.register_shared_cache(name, store)` | module method | Registers a custom `Stores::Base` under a name |
| `SafeMemoize.clear_shared_cache(name)` | module method | Evicts all entries from the named store |
| `SafeMemoize.drop_shared_cache(name)` | module method | Removes the named store from the registry |
| `SafeMemoize.shared_caches` | module method | Returns a snapshot of the registry |
| `SafeMemoize.reset_shared_caches!` | module method | Clears the entire registry (test teardown) |
| `SafeMemoize.register_extension(name, ext)` | module method | Registers a plugin extension |
| `SafeMemoize.unregister_extension(name)` | module method | Removes an extension |
| `SafeMemoize.extensions` | module method | Returns snapshot of extension registry |
| `SafeMemoize.reset_extensions!` | module method | Clears all extensions (test teardown) |
| `SafeMemoize.extension_for_option(name)` | module method | Returns the extension handling the named option |

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
| `fiber_local:` | `Boolean` | `false` | Fiber-local cache; each fiber gets an isolated store; incompatible with `shared:` and `store:` |
| `ractor_safe:` | `Boolean` | `false` | Supervisor-Ractor shared cache; replaces the `Mutex`; worker Ractors can call the method; requires `shared: true`; cached values are deep-frozen; incompatible with `if:`, `unless:`, `max_size:`, `ttl_refresh:`, `key:`, and `store:` |
| `namespace:` | `String \| nil` | `nil` | Namespace prefix prepended to the cache key's first element; must not contain `:`; takes precedence over the class-level and global namespace |
| `shared_cache:` | `String \| nil` | `nil` | Name of a globally-registered shared store; incompatible with `shared:`, `store:`, `fiber_local:`, `ractor_safe:`, and `max_size:` |
| `cache_bust:` | `Proc \| Symbol \| nil` | `nil` | Version-token callable; invoked on the instance at each lookup; token is folded into the key; incompatible with `key:` |
| `copy_on_read:` | `Boolean` | `false` | Return a `dup`/`deep_dup` of the cached value on every read; protects shared state from caller mutation; nil and frozen values pass through; incompatible with `ractor_safe:` |
| `group:` | `Symbol \| String \| nil` | `nil` | Assigns the method to a named invalidation group; call `reset_memo_group` / `reset_shared_memo_group` to bust all methods in the group at once; a method belongs to at most one group |
| *(extension options)* | any | — | Unknown kwargs are validated against registered extensions; raise `ArgumentError` if unclaimed |

### `memoize_all` options (class method)

All `memoize` option keys above, plus:

| Option key | Type | Default |
|---|---|---|
| `except:` | `Array<Symbol>` | `[]` |
| `only:` | `Array<Symbol>` | `[]` |
| `include_protected:` | `Boolean` | `false` |
| `include_private:` | `Boolean` | `false` |

### `safe_memoize_options` (class method)

| Option key | Type | Default | Notes |
|---|---|---|---|
| any `memoize` key except mode-switches | — | — | Accepts `ttl:`, `max_size:`, `ttl_refresh:`, `if:`, `unless:`, `key:`, `cache_bust:`, `copy_on_read:`, `namespace:`, `store:`, `group:`; raises `ArgumentError` for `shared:`, `fiber_local:`, `ractor_safe:`, `shared_cache:` |

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
| `reset_memo_group(group_name)` | `nil` |
| `reset_all_memos` | `nil` |
| `memo_touch(method_name, *args, ttl: nil, **kwargs)` | `Boolean` |
| `memo_refresh(method_name, *args, **kwargs)` | cached value |

**Group introspection**

| Method | Returns |
|---|---|
| `memo_groups` | `Array<Symbol>` — all group names on the class |
| `memo_group_methods(group_name)` | `Array<Symbol>` — methods in the group |

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

**Fiber-local cache (when any method uses `fiber_local: true`)**

| Method | Returns |
|---|---|
| `fiber_local_memoized?(method_name, *args, **kwargs)` | `Boolean` — cached in the current fiber? |
| `reset_fiber_memo(method_name, *args, **kwargs)` | `nil` — clear one or all entries in current fiber |
| `reset_all_fiber_memos` | `nil` — clear all fiber-local entries for this instance |

### Shared-cache class methods (added when any method uses `shared: true`)

| Method | Returns |
|---|---|
| `reset_shared_memo(method_name, *args, **kwargs)` | `nil` |
| `reset_all_shared_memos` | `nil` |
| `reset_shared_memo_group(group_name)` | `nil` |
| `shared_memoized?(method_name, *args, **kwargs)` | `Boolean` |
| `shared_memo_count(method_name = nil)` | `Integer` |
| `shared_memo_age(method_name, *args, **kwargs)` | `Numeric \| nil` |
| `shared_memo_stale?(method_name, *args, **kwargs)` | `Boolean` |

### Group class methods (available on any class that uses `group:`)

| Method | Returns |
|---|---|
| `safe_memo_groups` | `Array<Symbol>` — all group names on the class |
| `safe_memo_group_methods(group_name)` | `Array<Symbol>` — methods belonging to the group |

**Ractor-safe shared cache (added when any method uses `ractor_safe: true`)**

| Method | Returns |
|---|---|
| `reset_ractor_memo(method_name, *args, **kwargs)` | `nil` — clear one or all entries |
| `reset_all_ractor_memos` | `nil` — clear the entire Ractor-safe shared cache |
| `ractor_memoized?(method_name, *args, **kwargs)` | `Boolean` — live entry exists? |
| `ractor_memo_count(method_name = nil)` | `Integer` — live entry count |

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
| `namespace` | `String \| nil` | `nil` |

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
