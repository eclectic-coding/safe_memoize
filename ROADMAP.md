# SafeMemoize Roadmap

This document tracks the planned evolution of SafeMemoize through v1.0.0 and beyond. Items are grouped by release milestone; ordering within a milestone reflects priority, not a strict implementation sequence.

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