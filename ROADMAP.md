# SafeMemoize Roadmap

This document tracks the planned evolution of SafeMemoize from its current state (v0.7.0) through v1.0.0 and beyond. Items are grouped by release milestone; ordering within a milestone reflects priority, not a strict implementation sequence.

---

## Current state — v0.7.0

The gem ships with a comprehensive feature set:

- Thread-safe memoization (nil/false-safe, per-argument caching)
- TTL expiration with sliding-window (`ttl_refresh:`) support
- LRU cache size capping (`max_size:`)
- Conditional caching (`if:` / `unless:`)
- Full lifecycle hooks: `on_memo_hit`, `on_memo_miss`, `on_memo_store`, `on_memo_expire`, `on_memo_evict`
- Per-instance cache metrics (`cache_stats`, hit/miss rates, computation time)
- Cache warm-up, export, and restore (`warm_memo`, `dump_memo`, `load_memo`)
- Bulk preloading (`memo_preload`)
- Class-level shared cache (`shared: true`) with age/stale inspection
- Bulk memoization (`memoize_all`) including protected/private methods
- Custom cache keys at class level (`key:`) and instance level (`memoize_with_custom_key`)
- Rich introspection (`memoized?`, `memo_count`, `memo_keys`, `memo_values`, `memo_ttl_remaining`, `memo_age`, `memo_stale?`)
- `memo_touch` (extend TTL without recomputing) and `memo_refresh` (force recompute)
- Global configuration via `SafeMemoize.configure`
- Complete RBS type signatures
- 100 % line coverage

---

## v0.8.0 — Robustness & Developer Experience

*Goal: harden the existing API surface, improve failure modes, and make debugging easier.*

- [ ] **Descriptive argument errors** — raise `ArgumentError` with an actionable message when `memoize` is called on a method name that does not exist on the class at definition time
- [ ] **Key serialization safety** — deep-freeze argument keys stored in the cache to prevent subtle mutation bugs when callers modify objects they passed in
- [ ] **`memo_inspect`** — single-entry deep-inspection helper returning all metadata (value, hits, misses, TTL remaining, age, custom key, LRU position) for one cached call in one shot
- [ ] **Deprecation infrastructure** — add an internal `SafeMemoize.deprecate` helper so future breaking changes can be signalled clearly before they land
- [ ] **`memoize_all` option: `only:`** — symmetric counterpart to `except:` for explicitly listing the methods to memoize rather than excluding specific ones
- [ ] **Improved hook error isolation** — hook exceptions should not propagate to the caller; log or surface them through a configurable error handler (`SafeMemoize.configure { |c| c.on_hook_error = ... }`)

---

## v0.9.0 — Observability & Ecosystem Integration

*Goal: make SafeMemoize a first-class citizen in Rails/ActiveSupport stacks and in observability pipelines.*

- [ ] **ActiveSupport::Notifications integration** — emit `cache.hit`, `cache.miss`, `cache.evict`, and `cache.expire` events when ActiveSupport is available (opt-in via configuration)
- [ ] **StatsD adapter** — thin optional module (`SafeMemoize::Adapters::StatsD`) that routes lifecycle hooks to a StatsD client with sensible metric names and tags
- [ ] **OpenTelemetry spans** — optional adapter (`SafeMemoize::Adapters::OpenTelemetry`) wrapping computation time in a trace span for distributed tracing pipelines
- [ ] **Rails request-scope helper** — guide + optional mixin for resetting instance memos at the end of each request (controller concern, middleware, or Active Model pattern)
- [ ] **Formal benchmark suite** — `benchmarks/` directory with comparisons against `memery`, `memo_wise`, and raw `||=`, covering single-threaded throughput and contention under concurrent load
- [ ] **Concurrency stress tests** — dedicated spec suite hammering shared-cache paths and LRU eviction under high thread counts to surface race conditions

---

## v1.0.0 — Stable API

*Goal: declare a stable, semver-governed public API that downstream code can depend on with confidence.*

- [ ] **Semantic versioning guarantee** — document which constants, methods, and option keys are public API; breaking changes require a major bump henceforth
- [ ] **Complete RBS + Sorbet signatures** — cover all public methods including overloads for optional keyword arguments; publish `.rbi` stubs as a companion package if demand warrants
- [ ] **Full API reference** — generated documentation hosted on RubyDoc or a dedicated docs site; all public methods documented with parameter types, return values, and usage examples
- [ ] **Ractor compatibility audit** — investigate and either support Ractor-compatible operation (Mutex replacement, shared-cache storage) or document the limitation clearly
- [ ] **Ruby version policy** — formalise the supported Ruby version window and cadence for dropping EOL versions
- [ ] **Deprecation sweep** — resolve or formally deprecate any unstable internal APIs before the stable release
- [ ] **Upgrade guide** — document all breaking changes from 0.x and provide a migration path for users of deprecated behaviour

---

## v1.1.0 — Pluggable Cache Stores

*Goal: allow the in-process hash cache to be swapped for an external store, enabling cross-process and distributed memoization.*

- [ ] **Cache store adapter interface** — define a minimal `#read`, `#write`, `#delete`, `#clear`, and `#keys` contract that external backends must implement
- [ ] **`store:` option on `memoize`** — accept any store adapter object; defaults to the existing in-process hash store
- [ ] **Redis adapter** — reference implementation (`SafeMemoize::Stores::Redis`) with TTL, LRU-like expiry, and serialization handled transparently
- [ ] **Rails.cache adapter** — thin wrapper around `ActiveSupport::Cache::Store` for projects already using a configured Rails cache
- [ ] **`SafeMemoize.configure { |c| c.default_store = ... }`** — global default store so every memoized method uses it without per-call configuration

---

## v1.2.0 — Async & Fiber-Safe Memoization

*Goal: first-class support for Fiber-based concurrency frameworks (Async, Falcon, Rails async controllers).*

- [ ] **Fiber-local memoization mode** — `memoize :method, fiber_local: true` stores results in `Fiber[:safe_memoize_cache]` rather than instance variables, giving each fiber its own isolated cache automatically reset when the fiber terminates
- [ ] **Ractor-compatible shared cache** — revisit `shared: true` using `Ractor::TVar` or shareable frozen objects so class-level caches work across Ractors
- [ ] **concurrent-ruby integration** — optional adapter using `Concurrent::Map` and `Concurrent::ReentrantReadWriteLock` as a drop-in replacement for `Mutex` where higher read-concurrency is desirable

---

## v2.0.0 — Next Generation (Long Horizon)

*Goal: incorporate real-world usage feedback, clean up accumulated API surface, and open a path for advanced extension.*

- [ ] **Plugin / extension architecture** — a formal `SafeMemoize::Extension` API so third-party gems can add new options, hooks, or store adapters without monkey-patching
- [ ] **DSL refinements** — evaluate alternative syntax proposals (`memoize_method`, block form, annotation approach) based on community feedback; introduce the preferred form with a migration path from the current API
- [ ] **Cross-instance cache sharing** — beyond the class-level `shared: true`, support explicitly named shared caches that span unrelated classes
- [ ] **Cache namespacing** — allow a namespace prefix on all keys for multi-tenant or versioned deployments (especially useful with external stores)
- [ ] **Automatic cache busting** — optional integration with ActiveRecord's `updated_at` timestamp so object mutations automatically invalidate their own cached entries

---

## Versioning policy

SafeMemoize follows [Semantic Versioning](https://semver.org/) from v1.0.0 onwards:

- **Patch** (1.x.**y**) — bug fixes; no API changes
- **Minor** (1.**x**.0) — additive features; backward-compatible
- **Major** (**x**.0.0) — breaking changes; migration guide published

0.x releases may include breaking changes between minor versions.

---

## Contributing

Ideas, bug reports, and pull requests are welcome. Open an issue at <https://github.com/eclectic-coding/safe_memoize/issues> to discuss a feature before building it. If you are picking up a roadmap item, mention the milestone in your PR so it can be tracked against this document.