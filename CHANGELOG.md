# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
from v1.0.0 onwards. Prior 0.x releases may include breaking changes between minor versions.

## [Unreleased]

### Added

- `fiber_local: true` option on `memoize` — stores results in `Fiber[:__safe_memoize__]` rather than instance variables, giving each fiber its own isolated cache that is automatically discarded when the fiber terminates; no `Mutex` is acquired because fibers are cooperative; a per-fiber ownership sentinel ensures inherited storage from parent fibers is replaced with a fresh isolated store on first write; supports all standard options (`ttl:`, `ttl_refresh:`, `max_size:`, `if:`, `unless:`, `key:`); incompatible with `shared:` and `store:` (raises `ArgumentError`)
- `#fiber_local_memoized?(method_name, *args, **kwargs)` — returns `true` if the given call is currently cached in the current fiber's store
- `#reset_fiber_memo(method_name, *args, **kwargs)` — clears one or all fiber-local cached entries for a method in the current fiber
- `#reset_all_fiber_memos` — clears all fiber-local cached entries for this instance in the current fiber

### Fixed

- Codecov reporting accuracy — switched SimpleCov output from `.resultset.json` (internal format, misread by Codecov as ~85%) to `coverage/coverage.json` via `simplecov_json_formatter`; CI now uploads the correct file
- CI coverage ordering — `bundle exec rspec` ran files alphabetically, causing `ractor_spec.rb` to execute before `spec/stores/`, disrupting Ruby's Coverage counters and dropping reported coverage to ~96%; CI now uses `bundle exec rake spec`, which enforces the store-first ordering already documented in the Rakefile

## [1.1.0] - 2026-05-22

### Added

- `SafeMemoize::Stores::Base` — abstract adapter base class defining the cache store contract: `read(key)`, `write(key, value, expires_in: nil)`, `delete(key)`, `clear`, `keys`, and `exist?(key)`; a frozen `MISS` sentinel on `Base` distinguishes cache misses from cached `nil` or `false` values; `exist?` has a default implementation that delegates to `read`
- `SafeMemoize::Stores::Memory` — built-in in-process store that wraps a plain `Hash` behind a `Mutex`; supports per-entry TTL via `expires_in:` with lazy expiry on read; serves as both the default store and the reference implementation for custom adapters
- `Configuration#default_store` — set via `SafeMemoize.configure { |c| c.default_store = MyStore.new }` to route every `memoize` call that has no explicit `store:` through the given adapter; methods using `max_size:` or `shared:` are incompatible and fall back silently to the per-instance hash; an invalid value raises `ArgumentError` at `memoize` time; cleared by `reset_configuration!`
- `SafeMemoize::Stores::RailsCache` — opt-in adapter (`require "safe_memoize/stores/rails_cache"`) wrapping any `ActiveSupport::Cache::Store` (including `Rails.cache`); values are wrapped in a sentinel envelope so cached `nil`/`false` are distinguished from a cache miss; TTL forwarded as `expires_in:` for native store expiry; `clear` uses `delete_matched` scoped to the namespace; `keys` returns `[]` (AS::Cache has no enumeration API)
- `SafeMemoize::Stores::Redis` — opt-in adapter (`require "safe_memoize/stores/redis"`) backed by any Redis-compatible client responding to `#get`, `#set`, `#del`, and `#scan_each`; values and keys are serialized with Marshal + `pack("m0")`; TTL is forwarded as `PX` (milliseconds, rounded up) for sub-second precision; `clear` uses `SCAN` to avoid blocking; all entries are namespaced (default: `"safe_memoize"`) so multiple stores or applications can share one Redis instance
- `store:` option on `memoize` — accepts any `Stores::Base` subclass instance; routes all reads and writes through the adapter's `read`/`write` interface; the store is shared across all instances of the class; `ttl:` is forwarded as `expires_in:` to `write`, `ttl_refresh:` re-writes on every hit, and `if:`/`unless:` conditional storage is enforced at the SafeMemoize layer; raises `ArgumentError` if combined with `max_size:` (LRU belongs in the adapter) or `shared:`

### Changed

- Test suite achieves 100% line coverage — `spec_helper` now requires opt-in store adapters (`Stores::Redis`, `Stores::RailsCache`) after `SimpleCov.start` so Coverage tracks them; `Rakefile` runs `spec/stores/` before other specs to prevent Ruby 3.4 Coverage counter disruption from Ractor/concurrency tests; `version.rb` excluded from coverage reporting
- `store:` type guard in `ClassMethods#memoize` collapsed to an inline guard clause so Ruby's Coverage module counts the raise correctly
- Hook-error isolation tests (`concurrency_spec`, `hooks_spec`) now configure `on_hook_error = ->(*) {}` to silence expected stderr warnings rather than leaking them into test output; StatsD error-resilience test asserts on the emitted warning with `expect { }.to output(...).to_stderr`

## [1.0.0] - 2026-05-22 

### Added

- Ractor compatibility audit — `spec/ractor_spec.rb` documents the specific failure modes (non-shareable closures in `define_method` blocks, `Ractor::IsolationError` on `SafeMemoize.configuration`); README section explains the limitation and the Thread-based workaround
- Semantic versioning guarantee — README `## Public API and versioning guarantee` section enumerates every public constant, method, option key, and `Configuration` attribute covered by semver from v1.0.0 onwards; opt-in extensions (`SafeMemoize::Rails`, `SafeMemoize::Adapters::*`) are explicitly called out as not yet covered until their owning milestone ships
- Full API reference — YARD documentation added to all public methods, classes, and modules; `SafeMemoize::Adapters::StatsD` and `SafeMemoize::Adapters::OpenTelemetry` fully documented with usage examples; internal modules marked `@api private`; `.yardopts` and `rake doc` task added; `gem "yard"` added as a development dependency
- Deprecation sweep — pre-v1.0.0 API consistency audit: `memoized?`, `memo_ttl_remaining`, `memo_touch`, `memo_age`, `memo_stale?` now use `compute_cache_key` instead of `safe_memo_cache_key` so they correctly resolve entries stored with a custom key (instance-level `memoize_with_custom_key` or class-level `key:`); `memo_matcher_for` (used by `reset_memo` and `memo_refresh`) receives the same fix; `SafeMemoize::Error` added to the public API guarantee table and to RBS + Sorbet signatures; RBS and `.rbi` `warm_memo` block annotation corrected back to mandatory (was incorrectly marked optional in v0.9.0 signatures)
- Ruby version policy — README `## Ruby version support` section formalises the supported version window (Ruby ≥ 3.3; current stable plus two previous non-EOL minors), the cadence for dropping EOL versions (minor release only, never a patch), and a history table of dropped versions; CI matrix documents covered versions with their EOL dates
- Complete RBS + Sorbet signatures — `sig/safe_memoize.rbs` corrected: `SafeMemoize::Adapters::StatsD` added; `memo_count`, `memo_keys`, `memo_values` fixed from rest-arg to proper optional single arg; `clear_memo_hooks` and `clear_custom_keys` optional-arg annotations corrected; `warm_memo` block marked optional; new `rbi/safe_memoize.rbi` ships Sorbet stubs covering the full public API, all `Configuration` attributes, adapters, and opt-in Rails helpers
- Upgrade guide — `UPGRADING.md` documents every breaking change introduced across the 0.x series, with before/after code examples and migration steps for each; covers Ruby 3.2 removal, TTL clock change, `memo_keys`/`memo_values` shape change, `memoize` definition-time raise, argument mutation fix, hook exception isolation, and the two custom-key introspection fixes landing in v1.0.0

## [0.9.0] - 2026-05-22

### Added

- `ActiveSupport::Notifications` integration — opt-in via `SafeMemoize.configure { |c| c.active_support_notifications = true }`; emits `cache_hit.safe_memoize`, `cache_miss.safe_memoize`, `cache_evict.safe_memoize`, `cache_expire.safe_memoize`, and `cache_store.safe_memoize` events; each payload includes `:method`, `:key`, and `:class`; zero overhead when ActiveSupport is not loaded
- `SafeMemoize::Adapters::StatsD` — thin optional adapter that routes lifecycle events to any StatsD client via `SafeMemoize.configure { |c| c.statsd_client = my_client }`; emits `safe_memoize.hit`, `safe_memoize.miss`, `safe_memoize.evict`, `safe_memoize.expire`, and `safe_memoize.store` with `method:` and `class:` tags; client errors are rescued and warned rather than raised
- Formal benchmark suite (`benchmarks/benchmark.rb`) — six scenarios covering zero-arg cache hit/miss, with-argument hit, fast vs locked path, shared vs instance cache, and concurrent throughput under 8-thread contention; optional comparisons against `memery` and `memo_wise`; run with `bundle exec ruby benchmarks/benchmark.rb`
- Concurrency stress test suite (`spec/concurrency_spec.rb`) — 18 barrier-synchronized examples hammering the fast path, locked path, and shared cache under 30 concurrent threads; covers exactly-once computation, LRU size invariant, hook count integrity, metric accuracy, TTL pruning, and deadlock detection (10-second timeout per run)
- `SafeMemoize::Adapters::OpenTelemetry` — optional adapter that wraps each cache-miss computation in an OpenTelemetry span; configure via `SafeMemoize.configure { |c| c.opentelemetry_tracer = OpenTelemetry.tracer_provider.tracer("safe_memoize") }`; span name is `"safe_memoize.compute"` with attributes `safe_memoize.method`, `safe_memoize.class`, and `safe_memoize.cache_hit`; falls back to untraced execution when the tracer is absent or does not respond to `in_span`
- `SafeMemoize::Rails` — opt-in request-scope helpers (`require "safe_memoize/rails"`): `SafeMemoize::Rails::RequestScoped` concern auto-registers `after_action :reset_all_memos` in controllers and exposes `reset_request_memos` elsewhere; `SafeMemoize::Rails::Middleware` Rack middleware resets all thread-tracked instances (`SafeMemoize::Rails.track(self)`) at the end of each request even on error

## [0.8.0] - 2026-05-21

### Added

- Raise `ArgumentError` at definition time when `memoize` is called on a method that does not exist on the class — previously the error only surfaced at runtime when `super` had nothing to call
- Key serialization safety: argument arrays, hashes, and strings are deep-frozen into an independent copy when the cache key is built, so callers that mutate their arguments after a call can no longer corrupt or miss the cached entry
- `memo_inspect` — single-entry deep-inspection helper returning all metadata for one cached call in one mutex-held read: `cached`, `value`, `hits`, `misses`, `ttl_remaining`, `age`, `custom_key`, and `lru_position`; returns `nil` when the entry is not cached
- Deprecation infrastructure: `SafeMemoize.deprecate(subject, message:, horizon:)` emits a structured `[SafeMemoize]` warning to stderr by default; configurable via `SafeMemoize.configure { |c| c.on_deprecation = ->(msg) { ... } }` to raise, log, or collect warnings
- `memoize_all only:` — symmetric counterpart to `except:`; explicitly lists the methods to memoize and skips all others; raises `ArgumentError` when both `only:` and `except:` are given
- Hook error isolation: exceptions raised inside lifecycle hooks no longer propagate to the caller; by default a `[SafeMemoize] Hook error in <type>: <message>` warning is emitted to stderr; configurable via `SafeMemoize.configure { |c| c.on_hook_error = ->(error, hook_type, cache_key) { ... } }` to raise, log, or silence

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