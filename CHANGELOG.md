## [Unreleased]

- Raise `ArgumentError` at definition time when `memoize` is called on a method name that does not exist on the class — previously the error only surfaced at runtime when `super` had nothing to call

## [0.7.0] - 2026-05-18

- Add `memo_preload` to batch-warm multiple cache entries in one call
  - `obj.memo_preload(:find, [1], [2], [3])` calls the memoized method for each arg set and caches all results
  - Returns an array of results in the same order as the input arg sets
  - Computes each entry only once — subsequent calls return from cache
- Add `on_memo_store` hook that fires whenever a value is written to the cache
  - Fires on every cache miss (fast path and LRU path)
  - Also fires when entries are written via `warm_memo` or `load_memo`
  - Does not fire on cache hits or when a conditional `:if`/`:unless` prevents storing
  - Fires on the calling instance for `shared: true` misses
  - Completes the full lifecycle hook set: `on_store`, `on_hit`, `on_miss`, `on_expire`, `on_evict`
- Add per-method `cache_metrics_reset(:method)` to clear stats for a single method without wiping the rest
  - `cache_metrics_reset` (no args) still clears all metrics as before
- Add `SafeMemoize.configure` for global default options
  - `SafeMemoize.configure { |c| c.default_ttl = 60 }` applies a TTL to all subsequently memoized methods
  - `SafeMemoize.configure { |c| c.default_max_size = 100 }` sets a global LRU size limit
  - Per-call options (`ttl:`, `max_size:`) override the global defaults
  - `SafeMemoize.reset_configuration!` restores defaults to `nil`
- Add `memo_touch` to reset the expiry clock on a cached entry without recomputing
  - `memo_touch(:method, *args)` extends the entry's TTL from now using the original TTL window
  - `memo_touch(:method, *args, ttl: 30)` sets a new TTL explicitly
  - Returns `true` on success, `false` if the entry is not cached or already expired
- Add `shared_memo_age` class method to inspect how long ago a shared entry was cached
- Add `shared_memo_stale?` class method to check whether a shared entry's TTL has elapsed
- Update RBS type signatures for all new methods and the `Configuration` class
- Add `key:` option to `memoize` for class-level cache key generation
  - `memoize :method, key: ->(a, b) { a }` defines a key generator at the class level — calls whose key block returns the same value share one cache entry
  - Instance-level `memoize_with_custom_key` still takes priority over `key:`
  - Composes with all existing options (`ttl:`, `max_size:`, `shared:`, `if:`, etc.)
  - Raises `ArgumentError` if `key:` is not callable
- Add `shared:` support to `memoize_all` (was already functional via `**options` passthrough; now tested and documented)
- Add `memo_refresh` to force-recompute a cached entry and store the new value in one call
- Add `memo_age` to return how many seconds ago an entry was cached (`nil` if not cached or expired)
- Add `memo_stale?` to check whether a cached entry exists but its TTL has elapsed

## [0.6.3] - 2026-05-18

- Upgrade `softprops/action-gh-release` from v2 to v3 to resolve Node.js 20 deprecation warning in release workflow

## [0.6.2] - 2026-05-18

- Achieve 100% line coverage across all lib files
  - Add SimpleCov filter to exclude `/spec` from coverage reporting
  - Add tests for `memo_ttl` in `CacheRecordMethods` covering nil, valid numeric, negative, and non-numeric inputs
  - Add tests for private `memo_cache_read` in `CacheStoreMethods` covering nil cache, live hit, and expired entry
  - Add tests for `memo_keys` / `memo_values` with custom-key entries, covering the `custom_key:` projection branch in `InspectionMethods`
  - Add missing error-case tests for `ReleaseTooling.update_version_file` (no VERSION constant) and `finalize_changelog` (no Unreleased heading)

## [0.6.1] - 2026-05-17

- Fix `memo_keys` and `memo_values` showing `args: custom_key, kwargs: nil` for methods using `memoize_with_custom_key` — now surfaces as `custom_key:`
- Refactor `cache_stats` / `cache_stats_for` to share aggregation logic via private helpers

## [0.6.0] - 2026-05-17

- Fix TTL clock starting at `memoize` definition time instead of first method call
- Fix metrics key silently dropping kwargs, causing methods that differ only in kwargs to share a metrics bucket
- Fix stale LRU references remaining after expired entries are pruned
- Add `ttl:` option to `warm_memo` so warmed entries can be given an expiry
- Add `max_size:` support for `shared: true` memoization (class-level LRU eviction)
- Add `ttl_refresh: true` option on `memoize` for sliding window TTL — resets expiry on every cache hit
- Add `include_protected:` and `include_private:` options to `memoize_all`
- Add `memo_ttl_remaining` for TTL introspection — returns seconds until expiry, `nil` for no TTL, `0` for uncached/expired

## [0.5.0] - 2026-05-17

- Drop support for Ruby 3.2 (EOL); minimum required version is now Ruby 3.3 

## [0.4.0] - 2026-05-17

- Add `warm_memo`, `dump_memo`, and `load_memo` for cache warm-up and persistence
  - `warm_memo(:method, *args, **kwargs) { value }` — pre-populates a cache entry via block without calling the method
  - `dump_memo` / `dump_memo(:method)` — exports live cached entries as a plain `{[method, args, kwargs] => value}` hash
  - `load_memo(snapshot)` — merges a snapshot into the cache; loaded entries have no TTL
  - Expired entries are excluded from `dump_memo` output
- Add `shared: true` option on `memoize` to store results on the class instead of per-instance
  - All instances share one cache; the method is computed only once regardless of how many objects exist
  - Class-level invalidation: `reset_shared_memo`, `reset_all_shared_memos`
  - Class-level inspection: `shared_memoized?`, `shared_memo_count`
    - Supports `ttl:`, `if:`, and `unless:` options
  - Instance hooks (`on_memo_hit`, `on_memo_miss`, `on_memo_expire`) fire on the calling instance
- Add `memoize_all` to memoize every public method defined on the class in one call
  - Accepts all options supported by `memoize` (`ttl:`, `max_size:`, `if:`, `unless:`)
  - `except:` option to skip specific methods by name
  - Only affects public methods defined directly on the class
- Add `on_memo_miss` hook that fires on every cache miss, completing the full lifecycle hook set alongside `on_memo_hit`, `on_memo_evict`, and `on_memo_expire`

## [0.3.0] - 2026-05-15

- Add `on_memo_hit` hook that fires on every cache hit, completing the lifecycle API alongside `on_memo_expire` and `on_memo_evict`
- Add conditional memoization via `if:` and `unless:` options on `memoize`
  - `if: ->(result) { ... }` — only caches when the lambda returns truthy
  - `unless: ->(result) { ... }` — skips caching when the lambda returns truthy
  - Uncached calls recompute on every invocation until the condition is met
    - Compatible with `ttl:`, `max_size:`, hooks, and all inspection APIs 
- Add LRU cache size limit via `max_size:` option on `memoize`
  - Evicts the least-recently-used entry per method when the limit is reached
  - Cache hits promote entries to most-recently-used, preventing premature eviction
  - Fires the existing `on_evict` hook for LRU-evicted entries
  - Self-healing: stale LRU references left by `reset_memo` are pruned automatically
  - Compatible with `ttl:` option and all existing inspection/reset APIs
  - Thread-safe under concurrent access

## [0.2.0] - 2026-05-14

- Add optional TTL expiration support for memoized entries
- Add cache invalidation/expiration hooks for custom handlers
  - `on_memo_expire` hook fires when TTL entries expire
  - `on_memo_evict` hook fires when manually resetting cache entries
  - `clear_memo_hooks` to remove registered hooks
- Add cache statistics and monitoring capabilities
  - `cache_stats` for comprehensive cache metrics
  - `cache_stats_for(method_name)` for per-method statistics
  - `cache_hit_rate` and `cache_miss_rate` for performance analysis
  - `cache_metrics_reset` to clear collected metrics
- Add manual cache key generation support
  - `memoize_with_custom_key` to define custom cache key logic
  - `clear_custom_keys` to remove custom key generators
  - Support for complex and computed keys based on arguments

## [0.1.2] - 2026-05-13

- Preserve public, protected, and private visibility for memoized methods
- Allow reset_memo to clear one cached argument combination or all entries for a method
- Add a memoized? helper for checking whether a method call is already cached
- Add a memo_count helper for inspecting cache size per instance or method
- Add a memo_keys helper for inspecting cached argument signatures
- Add a memo_values helper for inspecting cached signatures and their values

## [0.1.1] - 2026-05-13

- Add automated release tooling plus a GitHub Actions workflow for RubyGems publishing and GitHub releases

## [0.1.0] - 2026-02-26

- Initial release
