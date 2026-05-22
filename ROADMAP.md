# SafeMemoize Roadmap

This document tracks the planned evolution of SafeMemoize through v1.0.0 and beyond. Items are grouped by release milestone; ordering within a milestone reflects priority, not a strict implementation sequence.

---

## v1.0.0 — Stable API

*Goal: declare a stable, semver-governed public API that downstream code can depend on with confidence.*

| Feature | Description | Status |
|---|---|---|
| Semantic versioning guarantee | Document which constants, methods, and option keys are public API; breaking changes require a major bump henceforth | Shipped |
| Complete RBS + Sorbet signatures | Cover all public methods including overloads for optional keyword arguments; publish `.rbi` stubs as a companion package if demand warrants | Shipped |
| Full API reference | Generated documentation hosted on RubyDoc or a dedicated docs site; all public methods documented with parameter types, return values, and usage examples | Planned |
| Ractor compatibility audit | Investigate and either support Ractor-compatible operation (Mutex replacement, shared-cache storage) or document the limitation clearly | Shipped |
| Ruby version policy | Formalise the supported Ruby version window and cadence for dropping EOL versions | Shipped |
| Deprecation sweep | Resolve or formally deprecate any unstable internal APIs before the stable release | Planned |
| Upgrade guide | Document all breaking changes from 0.x and provide a migration path for users of deprecated behaviour | Planned |

---

## v1.1.0 — Pluggable Cache Stores

*Goal: allow the in-process hash cache to be swapped for an external store, enabling cross-process and distributed memoization.*

| Feature | Description | Status |
|---|---|---|
| Cache store adapter interface | Define a minimal read/write/delete/clear/keys contract that external backends must implement | Planned |
| `store:` option on `memoize` | Accept any store adapter object; defaults to the existing in-process hash store | Planned |
| Redis adapter | Reference implementation (`SafeMemoize::Stores::Redis`) with TTL, LRU-like expiry, and serialization handled transparently | Planned |
| Rails.cache adapter | Thin wrapper around `ActiveSupport::Cache::Store` for projects already using a configured Rails cache | Planned |
| Global default store | Set via `SafeMemoize.configure` — applies a default store to every memoized method without per-call configuration | Planned |

---

## v1.2.0 — Async & Fiber-Safe Memoization

*Goal: first-class support for Fiber-based concurrency frameworks (Async, Falcon, Rails async controllers).*

| Feature | Description | Status |
|---|---|---|
| Fiber-local memoization mode | `memoize :method, fiber_local: true` stores results in `Fiber[:safe_memoize_cache]` rather than instance variables, giving each fiber its own isolated cache automatically reset when the fiber terminates | Planned |
| Ractor-compatible shared cache | Revisit `shared: true` using `Ractor::TVar` or shareable frozen objects so class-level caches work across Ractors | Planned |
| concurrent-ruby integration | Optional adapter using `Concurrent::Map` and `Concurrent::ReentrantReadWriteLock` as a drop-in replacement for `Mutex` where higher read-concurrency is desirable | Planned |

---

## v2.0.0 — Next Generation (Long Horizon)

*Goal: incorporate real-world usage feedback, clean up accumulated API surface, and open a path for advanced extension.*

| Feature | Description | Status |
|---|---|---|
| Plugin / extension architecture | A formal `SafeMemoize::Extension` API so third-party gems can add new options, hooks, or store adapters without monkey-patching | Planned |
| DSL refinements | Evaluate alternative syntax proposals (`memoize_method`, block form, annotation approach) based on community feedback; introduce the preferred form with a migration path from the current API | Planned |
| Cross-instance cache sharing | Beyond the class-level `shared: true`, support explicitly named shared caches that span unrelated classes | Planned |
| Cache namespacing | Allow a namespace prefix on all keys for multi-tenant or versioned deployments (especially useful with external stores) | Planned |
| Automatic cache busting | Optional integration with ActiveRecord's `updated_at` timestamp so object mutations automatically invalidate their own cached entries | Planned |

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