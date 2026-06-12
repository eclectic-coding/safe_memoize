# SafeMemoize Benchmark Results

Run with `bundle exec ruby benchmarks/benchmark.rb`.

**Environment:** Ruby 3.4.8 (arm64-darwin25, PRISM) · `benchmark-ips` 5 s measurement / 2 s warmup

---

## What is being measured

SafeMemoize is compared against two vanilla Ruby baselines:

| Label | Pattern | Correctness |
|---|---|---|
| `raw \|\|= (unsafe)` | `@v \|\|= compute` | Broken — re-runs if result is `nil` or `false` |
| `raw safe ivar` | `return @v if defined?(@v); @v = compute` | Correct |
| `safe_memoize` | `prepend SafeMemoize` + `memoize :method` | Correct |

The raw patterns are intentionally simple and carry none of SafeMemoize's feature overhead (thread safety, argument keying, TTL, hooks, metrics). The numbers below quantify exactly what that feature set costs.

---

## Results

### 1. Zero-arg cache HIT — steady-state throughput

A primed object called repeatedly. This is the hot path.

| Implementation | i/s | ns/call | vs fastest |
|---|---|---|---|
| `raw safe ivar` | 21.51 M | 46.5 | — |
| `raw \|\|= (unsafe)` | 16.69 M | 59.9 | 1.29× slower |
| `safe_memoize` | 296.8 K | 3,370 | **72×** slower |

**Takeaway:** SafeMemoize's hit path costs ~3.4 µs per call — the price of a hash lookup, mutex check, and key construction. For methods that are called millions of times per second in a tight loop, raw ivars win. For methods that do real work (DB queries, HTTP, serialization), this overhead is negligible.

---

### 2. Zero-arg cache MISS — first-call overhead

A fresh instance is created each iteration so every call is a miss.

| Implementation | i/s | µs/call | vs fastest |
|---|---|---|---|
| `raw safe ivar` | 8.47 M | 0.12 | — |
| `safe_memoize` | 189.6 K | 5.28 | **45×** slower |

**Takeaway:** The miss path allocates the cache hash, builds the key, and acquires the mutex — ~5 µs. Still fast in absolute terms; any method body doing more than a trivial computation will dominate.

---

### 3. With-argument cache HIT — keyed lookup

A primed object called with the same argument each iteration.

| Implementation | i/s | ns/call | vs fastest |
|---|---|---|---|
| `raw safe ivar` | 14.17 M | 70.6 | — |
| `safe_memoize` | 289.2 K | 3,460 | **49×** slower |

**Takeaway:** The argument hash lookup adds roughly the same overhead as the zero-arg case. Key construction (deep-freeze copy of args) dominates, not the hash lookup itself.

---

### 4. Fast path vs locked path (internal)

Both are `safe_memoize`. Adding `max_size:` enables LRU tracking, which holds the mutex for the full read/write cycle.

| Configuration | i/s | µs/call | vs fast path |
|---|---|---|---|
| No `max_size:` (fast path) | 287.7 K | 3.48 | — |
| `max_size: 100` (locked path) | 218.0 K | 4.59 | 1.32× slower |

**Takeaway:** LRU costs an extra ~1.1 µs per hit. Use it when eviction matters; skip it for unbounded caches.

---

### 5. Shared cache vs instance cache (internal)

Both are `safe_memoize`. `shared: true` stores results on the class rather than the instance.

| Configuration | i/s | µs/call | difference |
|---|---|---|---|
| Instance cache | 292.5 K | 3.42 | — |
| Shared cache | 275.3 K | 3.63 | within margin of error |

**Takeaway:** Class-level shared storage is essentially free compared to per-instance caching. The mutex contention at the class level does not measurably affect single-threaded throughput.

---

### 6. Concurrent throughput — 8 threads × 50,000 iterations

| Implementation | Total time | i/s |
|---|---|---|
| `raw safe ivar` | 0.033 s | 12.01 M |
| `safe_memoize` (instance cache) | 1.363 s | 293.4 K |
| `safe_memoize` (shared cache) | 1.393 s | 287.1 K |

**Takeaway:** Under real thread contention the raw ivar baseline has no locking at all — it is technically unsafe here. SafeMemoize's per-instance mutex serialises writes correctly at ~293 K i/s; the class-level shared mutex performs identically at ~287 K i/s.

---

## Summary

| Scenario | SafeMemoize overhead |
|---|---|
| Hot cache hit (zero-arg) | ~3.4 µs — 72× vs raw ivar |
| Hot cache hit (with args) | ~3.5 µs — 49× vs raw ivar |
| First call / cache miss | ~5.3 µs — 45× vs raw ivar |
| LRU enabled (`max_size:`) | +1.1 µs vs fast path |
| Shared vs instance cache | no measurable difference |
| Concurrent throughput | ~293 K i/s (thread-safe) |

SafeMemoize is slower than a raw instance variable in absolute terms, but the overhead is measured in **microseconds**, not milliseconds. Any method that does I/O, calls a database, hits an external API, or performs non-trivial computation will completely dominate the memoization overhead — and that is precisely the use case SafeMemoize is designed for.