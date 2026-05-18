## [Unreleased]

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
