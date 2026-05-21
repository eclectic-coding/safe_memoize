# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
from v1.0.0 onwards. Prior 0.x releases may include breaking changes between minor versions.

## [Unreleased]

### Added

- Raise `ArgumentError` at definition time when `memoize` is called on a method that does not exist on the class — previously the error only surfaced at runtime when `super` had nothing to call
- Key serialization safety: argument arrays, hashes, and strings are deep-frozen into an independent copy when the cache key is built, so callers that mutate their arguments after a call can no longer corrupt or miss the cached entry
- `memo_inspect` — single-entry deep-inspection helper returning all metadata for one cached call in one mutex-held read: `cached`, `value`, `hits`, `misses`, `ttl_remaining`, `age`, `custom_key`, and `lru_position`; returns `nil` when the entry is not cached

## [0.7.0] - 2026-05-18

### Added

- `memo_preload` to batch-warm multiple cache entries in one call — `obj.memo_preload(:find, [1], [2], [3])` calls the memoized method for each arg set, caches all results, and returns them in input order
- `on_memo_store` hook that fires whenever a value is written to the cache (miss, `warm_memo`, or `load_memo`); completes the full lifecycle hook set alongside `on_hit`, `on_miss`, `on_expire`, and `on_evict`
- `SafeMemoize.configure` for global default options — `default_ttl` and `default_max_size` apply to all subsequently memoized methods; per-call options override the global defaults
- `SafeMemoize.reset_configuration!` to restore all global defaults to `nil`
- `memo_touch` to reset the expiry clock on a cached entry without recomputing — accepts an optional `ttl:` override; returns `true` on success, `false` if the entry is not cached or already expired
- `shared_memo_age` class method to inspect how long ago a shared entry was cached
- `shared_memo_stale?` class method to check whether a shared entry's TTL has elapsed
- `key:` option on `memoize` for class-level cache key generation — calls whose key block returns the same value share one cache entry; instance-level `memoize_with_custom_key` still takes priority
- `memo_refresh` to force-recompute a cached entry and store the new value in one call
- `memo_age` to return how many seconds ago an entry was cached (`nil` if not cached or expired)
- `memo_stale?` to check whether a cached entry exists but its TTL has elapsed

### Changed

- `cache_metrics_reset` now accepts an optional method name to clear stats for a single method only; calling without arguments still clears all metrics
- `shared:` support in `memoize_all` is now tested and documented (was already functional via `**options` passthrough)
- RBS type signatures updated for all new methods and the `Configuration` class

## [0.6.3] - 2026-05-18

### Changed

- Upgrade `softprops/action-gh-release` from v2 to v3 to resolve Node.js 20 deprecation warning in release workflow

## [0.6.2] - 2026-05-18

### Added

- 100% line coverage across all lib files — added tests for edge cases in `CacheRecordMethods`, `CacheStoreMethods`, `InspectionMethods`, and `ReleaseTooling`; added SimpleCov filter to exclude `/spec` from coverage reporting

## [0.6.1] - 2026-05-17

### Changed

- Refactored `cache_stats` / `cache_stats_for` to share aggregation logic via private helpers

### Fixed

- `memo_keys` and `memo_values` showed `args: custom_key, kwargs: nil` for methods using `memoize_with_custom_key` — now correctly surfaces as `custom_key:`

## [0.6.0] - 2026-05-17

### Added   

- `ttl:` option on `warm_memo` so warmed entries can be given an expiry
- `max_size:` support for `shared: true` memoization (class-level LRU eviction)
- `ttl_refresh: true` option on `memoize` for sliding window TTL — resets the expiry clock on every cache hit so the entry only expires after a full TTL of inactivity
- `include_protected:` and `include_private:` options on `memoize_all`
- `memo_ttl_remaining` for TTL introspection — returns seconds until expiry, `nil` for no TTL, `0` for uncached or expired

### Fixed

- TTL clock started at `memoize` definition time instead of at first method call
- Metrics key silently dropped kwargs, causing methods that differ only in kwargs to share a metrics bucket
- Stale LRU references remained in the order list after expired entries were pruned

## [0.5.0] - 2026-05-17

### Removed

- Support for Ruby 3.2 (EOL); minimum required version is now Ruby 3.3

## [0.4.0] - 2026-05-17

### Added

- `warm_memo`, `dump_memo`, and `load_memo` for cache warm-up and persistence — pre-populate entries without calling the method, export live entries as a plain hash, and restore from a snapshot
- `shared: true` option on `memoize` to store results on the class instead of per-instance — includes `reset_shared_memo`, `reset_all_shared_memos`, `shared_memoized?`, and `shared_memo_count`; supports `ttl:`, `if:`, and `unless:`
- `memoize_all` to memoize every public method defined on the class in one call — accepts all `memoize` options plus `except:` to skip specific methods
- `on_memo_miss` hook that fires on every cache miss, completing the full lifecycle hook set

## [0.3.0] - 2026-05-15

### Added

- `on_memo_hit` hook that fires on every cache hit
- Conditional memoization via `if:` and `unless:` predicates on `memoize` — uncached calls recompute on every invocation until the condition is satisfied; composes with `ttl:`, `max_size:`, and hooks
- LRU cache size limit via `max_size:` on `memoize` — evicts the least-recently-used entry when the limit is reached; cache hits promote entries; fires `on_evict`; thread-safe

## [0.2.0] - 2026-05-14

### Added

- Optional TTL expiration for memoized entries
- `on_memo_expire` and `on_memo_evict` lifecycle hooks; `clear_memo_hooks` to remove registered hooks
- Cache metrics: `cache_stats`, `cache_stats_for`, `cache_hit_rate`, `cache_miss_rate`, and `cache_metrics_reset`
- Custom cache key generation via `memoize_with_custom_key` and `clear_custom_keys`

## [0.1.2] - 2026-05-13

### Added

- Method visibility preservation (public, protected, private) for memoized methods
- Targeted `reset_memo` — clear one cached argument combination or all entries for a method
- `memoized?` helper to check whether a specific call is cached
- `memo_count`, `memo_keys`, and `memo_values` helpers for cache introspection

## [0.1.1] - 2026-05-13

### Added

- Automated release tooling (`bin/release`) and GitHub Actions workflow for RubyGems publishing and GitHub releases

## [0.1.0] - 2026-02-26

### Added

- Initial release

[Unreleased]: https://github.com/eclectic-coding/safe_memoize/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/eclectic-coding/safe_memoize/compare/v0.6.3...v0.7.0
[0.6.3]: https://github.com/eclectic-coding/safe_memoize/compare/v0.6.2...v0.6.3
[0.6.2]: https://github.com/eclectic-coding/safe_memoize/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/eclectic-coding/safe_memoize/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/eclectic-coding/safe_memoize/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/eclectic-coding/safe_memoize/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/eclectic-coding/safe_memoize/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/eclectic-coding/safe_memoize/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/eclectic-coding/safe_memoize/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/eclectic-coding/safe_memoize/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/eclectic-coding/safe_memoize/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/eclectic-coding/safe_memoize/releases/tag/v0.1.0