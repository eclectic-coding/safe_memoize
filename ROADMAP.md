# SafeMemoize Roadmap

This document tracks the planned evolution of SafeMemoize through v1.0.0 and beyond. Items are grouped by release milestone; ordering within a milestone reflects priority, not a strict implementation sequence.

---

## v1.5.0 — Cache Invalidation

*Goal: group-level cache invalidation so related methods can be busted in one operation.*

| Feature | Description | Status |
|---|---|---|
| Memoization groups | `memoize :find, group: :database` then `reset_memo_group(:database)` to invalidate all methods tagged with the same group at once; groups can span multiple methods on the same class | Planned |

---

## v1.6.0 — Resilience

*Goal: make external-store memoization resilient to infrastructure failures.*

| Feature | Description | Status |
|---|---|---|
| Circuit breaker for external stores | When a `store:` adapter raises on `read` or `write`, automatically fall back to the per-instance in-process hash rather than propagating the exception; configurable error threshold and recovery probe interval | Planned |

---

## v1.7.0 — Advanced Store Features

*Goal: multi-process performance patterns for high-traffic deployments.*

| Feature | Description | Status |
|---|---|---|
| Multi-level (L1/L2) caching | `store: [memory_store, redis_store]` — check in-process first, fall back to the remote store on miss, and promote to L1 on read; each level can have independent TTL and eviction settings | Planned |
| Stampede protection | Probabilistic early expiry (XFetch algorithm) for external stores; recomputes slightly before a TTL expires to prevent multiple processes hitting a cold miss simultaneously | Planned |

---

## v2.0.0 — Next Generation (Long Horizon)

*Goal: incorporate real-world usage feedback, clean up accumulated API surface, and open a path for advanced extension.*

| Feature | Description | Status |
|---|---|---|
| DSL refinements | Evaluate alternative syntax proposals (`memoize_method`, block form, annotation approach) based on community feedback; introduce the preferred form with a migration path from the current API | Planned |

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