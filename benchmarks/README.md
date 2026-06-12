# SafeMemoize Benchmarks

Measures throughput for cache hits, cache misses, argument-keyed lookups, and concurrent access. Optional comparison against `memery` and `memo_wise`.

## Running

```bash
bundle exec ruby benchmarks/benchmark.rb
```

### With comparison gems

```bash
gem install memery memo_wise
bundle exec ruby benchmarks/benchmark.rb
```

## Sections

| # | Scenario | What it measures |
|---|---|---|
| 1 | Zero-arg cache hit | Steady-state throughput on a primed cache |
| 2 | Zero-arg cache miss | First-call overhead (new instance per iteration) |
| 3 | With-argument cache hit | Key construction + hash lookup with one positional arg |
| 4 | Fast path vs locked path | Cost of `max_size:` (adds a Mutex for LRU promotion) |
| 5 | Shared vs instance cache | Class-level vs per-instance cache throughput |
| 6 | Concurrent cache hits | 8 threads × 50 000 iterations under contention |

## Interpreting results

**Cache hits are ~50–70× slower than raw `||=`** on a single thread — an expected trade-off. SafeMemoize does significantly more work per call: prepended-module dispatch, deep-frozen key construction, hook dispatch, and metrics tracking. The `||=` pattern is also incorrect for `nil`/`false` return values, which is the whole reason this gem exists.

**The fast path vs locked path gap is ~1.3×.** The locked path (used when `max_size:`, `if:`, or `ttl_refresh:` is set) holds the Mutex for the full read-compute-write cycle; the fast path only acquires it for the write step.

**Shared and instance caches are effectively identical in throughput.** Both paths go through the same Mutex; the class-level cache has one shared Mutex rather than one per instance.

**Concurrent throughput is bounded by the Mutex.** Under 8-thread contention, all threads compete for the per-instance Mutex on every read, serialising access. This is the cost of correctness under concurrent writes; in read-heavy workloads where the cache is pre-warmed the contention is minimal.

## Representative results (Apple M-series, Ruby 3.4, MRI)

```
1. Zero-arg cache HIT (primed cache)
   raw safe ivar    ~22 M i/s
   safe_memoize     ~335 K i/s  (65× slower than raw)

2. Zero-arg cache MISS (new instance each iteration)
   raw safe ivar    ~8 M i/s
   safe_memoize     ~227 K i/s  (36× slower than raw)

3. With-argument cache HIT
   raw safe ivar    ~15 M i/s
   safe_memoize     ~314 K i/s  (47× slower than raw)

4. Fast path vs locked path
   fast path        ~310 K i/s
   max_size: 100    ~234 K i/s  (1.32× slower)

5. Shared vs instance cache
   instance cache   ~323 K i/s
   shared cache     ~324 K i/s  (same-ish)

6. Concurrent (8 threads × 50 000 iterations)
   raw safe ivar         ~12 M i/s
   safe_memoize (fast)  ~327 K i/s
   safe_memoize (shared) ~323 K i/s
```

Results vary by hardware, Ruby version, and GVL scheduling. Run on your own hardware for authoritative numbers.

For a full recorded run with analysis, see [BENCHMARK.md](BENCHMARK.md).