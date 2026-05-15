## [Unreleased]

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
    - `cache_hit_rate` and `cache_miss_rate` for performance analysisdocument doclint 
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
