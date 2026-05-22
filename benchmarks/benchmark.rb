#!/usr/bin/env ruby
# frozen_string_literal: true

# Run with: bundle exec ruby benchmarks/benchmark.rb
#
# Optional comparison gems (install separately if desired):
#   gem install memery memo_wise
#
# Each section prints iterations/second and a comparison table.
# Higher i/s is better.

require "benchmark/ips"
require_relative "../lib/safe_memoize"

# ── Optional comparison gems ──────────────────────────────────────────────────

HAS_MEMERY = begin
  require "memery"
  true
rescue LoadError
  warn "  [skip] memery not installed (gem install memery to include)"
  false
end

HAS_MEMO_WISE = begin
  require "memo_wise"
  true
rescue LoadError
  warn "  [skip] memo_wise not installed (gem install memo_wise to include)"
  false
end

# ── Subject classes ───────────────────────────────────────────────────────────

# Raw patterns — no gem, for baseline reference
class RawIvarUnsafe
  # Classic ||= — fast but silently broken for nil/false return values
  def compute = (@compute ||= 42)
end

class RawIvarSafe
  # Safe raw pattern — correct but verbose
  def compute
    return @compute if defined?(@compute)
    @compute = 42
  end

  def fetch(n)
    @fetch ||= {}
    return @fetch[n] if @fetch.key?(n)
    @fetch[n] = n * 2
  end
end

# SafeMemoize
class SmZeroArg
  prepend SafeMemoize
  def compute = 42
  memoize :compute
end

class SmWithArg
  prepend SafeMemoize
  def fetch(n) = n * 2
  memoize :fetch
end

class SmLruPath
  prepend SafeMemoize
  def fetch(n) = n * 2
  memoize :fetch, max_size: 100
end

class SmShared
  prepend SafeMemoize
  def compute = 42
  memoize :compute, shared: true
end

# memery
if HAS_MEMERY
  class MemeryZeroArg
    include Memery
    memoize def compute = 42
  end

  class MemeryWithArg
    include Memery
    memoize def fetch(n) = n * 2
  end
end

# memo_wise
if HAS_MEMO_WISE
  class MemoWiseZeroArg
    prepend MemoWise
    def compute = 42
    memo_wise :compute
  end

  class MemoWiseWithArg
    prepend MemoWise
    def fetch(n) = n * 2
    memo_wise :fetch
  end
end

# ── Helpers ───────────────────────────────────────────────────────────────────

IPS_CONFIG = {time: 5, warmup: 2}

def section(title)
  puts
  puts "=" * 62
  puts "  #{title}"
  puts "=" * 62
end

# ── 1. Zero-arg cache HIT — steady-state throughput ──────────────────────────

section "1. Zero-arg cache HIT  (steady-state, primed cache)"

raw_unsafe = RawIvarUnsafe.new.tap(&:compute)
raw_safe   = RawIvarSafe.new.tap(&:compute)
sm_zero    = SmZeroArg.new.tap(&:compute)
mem_zero   = MemeryZeroArg.new.tap(&:compute) if HAS_MEMERY
mw_zero    = MemoWiseZeroArg.new.tap(&:compute) if HAS_MEMO_WISE

Benchmark.ips do |x|
  x.config(**IPS_CONFIG)
  x.report("raw ||= (unsafe)")  { raw_unsafe.compute }
  x.report("raw safe ivar")     { raw_safe.compute }
  x.report("safe_memoize")      { sm_zero.compute }
  x.report("memery")            { mem_zero.compute } if HAS_MEMERY
  x.report("memo_wise")         { mw_zero.compute } if HAS_MEMO_WISE
  x.compare!
end

# ── 2. Zero-arg cache MISS — first-call overhead ──────────────────────────────

section "2. Zero-arg cache MISS  (new instance each iteration)"

Benchmark.ips do |x|
  x.config(**IPS_CONFIG)
  x.report("raw safe ivar")  { RawIvarSafe.new.compute }
  x.report("safe_memoize")   { SmZeroArg.new.compute }
  x.report("memery")         { MemeryZeroArg.new.compute } if HAS_MEMERY
  x.report("memo_wise")      { MemoWiseZeroArg.new.compute } if HAS_MEMO_WISE
  x.compare!
end

# ── 3. With-argument cache HIT ────────────────────────────────────────────────

section "3. With-argument cache HIT  (single fixed argument)"

raw_arg  = RawIvarSafe.new.tap { |o| o.fetch(1) }
sm_arg   = SmWithArg.new.tap { |o| o.fetch(1) }
mem_arg  = MemeryWithArg.new.tap { |o| o.fetch(1) } if HAS_MEMERY
mw_arg   = MemoWiseWithArg.new.tap { |o| o.fetch(1) } if HAS_MEMO_WISE

Benchmark.ips do |x|
  x.config(**IPS_CONFIG)
  x.report("raw safe ivar")  { raw_arg.fetch(1) }
  x.report("safe_memoize")   { sm_arg.fetch(1) }
  x.report("memery")         { mem_arg.fetch(1) } if HAS_MEMERY
  x.report("memo_wise")      { mw_arg.fetch(1) } if HAS_MEMO_WISE
  x.compare!
end

# ── 4. Fast path vs locked path ───────────────────────────────────────────────

section "4. Fast path vs locked path  (max_size: adds mutex for LRU)"

sm_fast = SmWithArg.new.tap { |o| o.fetch(1) }
sm_lru  = SmLruPath.new.tap { |o| o.fetch(1) }

Benchmark.ips do |x|
  x.config(**IPS_CONFIG)
  x.report("fast path (no max_size)")   { sm_fast.fetch(1) }
  x.report("locked path (max_size:100)") { sm_lru.fetch(1) }
  x.compare!
end

# ── 5. Shared cache vs instance cache ────────────────────────────────────────

section "5. Shared cache vs instance cache  (class-level vs instance-level)"

sm_inst   = SmZeroArg.new.tap(&:compute)
sm_shared = SmShared.new.tap(&:compute)

Benchmark.ips do |x|
  x.config(**IPS_CONFIG)
  x.report("instance cache")  { sm_inst.compute }
  x.report("shared cache")    { sm_shared.compute }
  x.compare!
end

# ── 6. Concurrent cache hits under thread contention ─────────────────────────

section "6. Concurrent cache hits  (8 threads × 50_000 iterations)"

THREADS   = 8
ITERS     = 50_000
TOTAL     = THREADS * ITERS

def bench_threaded(label, obj, method, *args)
  ts = THREADS.times.map { Thread.new { ITERS.times { obj.public_send(method, *args) } } }
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ts.each(&:join)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  ips = TOTAL / elapsed
  label_str = ips >= 1_000_000 ? format("%.2fM", ips / 1_000_000.0) : format("%.1fK", ips / 1_000.0)
  printf "  %-34s %6.3fs  (%s i/s)\n", label, elapsed, label_str
end

puts

bench_threaded("raw safe ivar",         raw_safe,   :compute)
bench_threaded("safe_memoize (fast)",   sm_inst,    :compute)
bench_threaded("safe_memoize (shared)", sm_shared,  :compute)
bench_threaded("memery",                mem_zero,   :compute) if HAS_MEMERY
bench_threaded("memo_wise",             mw_zero,    :compute) if HAS_MEMO_WISE

puts
puts "Done."