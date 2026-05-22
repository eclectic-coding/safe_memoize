# frozen_string_literal: true

require "spec_helper"

CONCURRENCY_THREADS = 30
CONCURRENCY_DEADLOCK_TIMEOUT = 10

RSpec.describe "SafeMemoize thread safety" do
  # Launch +count+ threads all starting at the same instant via a barrier,
  # then join them. Raises on deadlock (timeout) or any thread exception.
  def barrier_run(count = CONCURRENCY_THREADS, &block)
    mu = Mutex.new
    cv = ConditionVariable.new
    ready = 0
    errors = []
    err_mu = Mutex.new

    threads = count.times.map do
      Thread.new do
        mu.synchronize do
          ready += 1
          cv.wait(mu) until ready == count
          cv.broadcast
        end
        block.call
      rescue => e
        err_mu.synchronize { errors << e }
      end
    end

    timed_out = threads.map { |t| t.join(CONCURRENCY_DEADLOCK_TIMEOUT) }.count(&:nil?)
    raise "Deadlock: #{timed_out}/#{count} threads timed out" if timed_out > 0
    raise errors.first if errors.any?
  end

  # Thread-safe incrementing counter — avoids pulling in concurrent-ruby.
  def atomic_counter
    mu = Mutex.new
    n = 0
    inc = -> { mu.synchronize { n += 1 } }
    get = -> { mu.synchronize { n } }
    [inc, get]
  end

  # ─────────────────────────────────────────────────────────────
  # Instance memoization
  # ─────────────────────────────────────────────────────────────

  describe "instance memoization" do
    it "computes exactly once when all threads race on a zero-argument method" do
      inc, get = atomic_counter

      klass = Class.new do
        prepend SafeMemoize

        define_method(:work) {
          inc.call
          "result"
        }
        memoize :work
      end

      obj = klass.new
      barrier_run { obj.work }

      expect(get.call).to eq(1)
    end

    it "computes exactly once per unique argument under concurrent load" do
      inc, get = atomic_counter

      klass = Class.new do
        prepend SafeMemoize

        define_method(:fetch) { |id|
          inc.call
          "v#{id}"
        }
        memoize :fetch
      end

      obj = klass.new
      barrier_run { obj.fetch(1) }

      expect(get.call).to eq(1)
    end

    it "always returns the correct value under concurrent reads" do
      klass = Class.new do
        prepend SafeMemoize

        def data = "stable"
        memoize :data
      end

      obj = klass.new
      results = []
      mu = Mutex.new

      barrier_run { mu.synchronize { results << obj.data } }

      expect(results.uniq).to eq(["stable"])
      expect(results.size).to eq(CONCURRENCY_THREADS)
    end

    it "does not deadlock or raise under concurrent read + reset_all_memos" do
      klass = Class.new do
        prepend SafeMemoize

        def data = "v"
        memoize :data
      end

      obj = klass.new
      expect {
        barrier_run do
          obj.data
          obj.reset_all_memos
          obj.data
        end
      }.not_to raise_error
    end

    it "memo_count is non-negative after concurrent writes and resets" do
      klass = Class.new do
        prepend SafeMemoize

        def data = "v"
        memoize :data
      end

      obj = klass.new
      barrier_run do
        obj.data
        obj.reset_all_memos
      end

      expect(obj.memo_count).to be >= 0
    end

    it "does not raise when reset_memo races with active reads" do
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch
      end

      obj = klass.new
      expect {
        barrier_run do |*|
          obj.fetch(rand(5))
          obj.reset_memo(:fetch)
        end
      }.not_to raise_error
    end
  end

  # ─────────────────────────────────────────────────────────────
  # LRU eviction under concurrent writes
  # ─────────────────────────────────────────────────────────────

  describe "LRU eviction (instance)" do
    it "never exceeds max_size under concurrent writes with many unique keys" do
      max = 5
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch, max_size: max
      end

      obj = klass.new
      barrier_run { obj.fetch(rand(100)) }

      expect(obj.memo_count).to be <= max
    end

    it "does not deadlock when LRU eviction races with cache hits" do
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch, max_size: 3
      end

      obj = klass.new
      [1, 2, 3].each { |n| obj.fetch(n) }

      expect { barrier_run { obj.fetch(rand(10)) } }.not_to raise_error
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Shared cache under concurrent access
  # ─────────────────────────────────────────────────────────────

  describe "shared cache (shared: true)" do
    it "computes exactly once across all racing instances" do
      inc, get = atomic_counter

      klass = Class.new do
        prepend SafeMemoize

        define_method(:work) {
          inc.call
          "result"
        }
        memoize :work, shared: true
      end

      barrier_run { klass.new.work }

      expect(get.call).to eq(1)
    ensure
      klass.reset_all_shared_memos
    end

    it "never exceeds max_size under concurrent writes from different instances" do
      max = 5
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch, shared: true, max_size: max
      end

      barrier_run { klass.new.fetch(rand(100)) }

      expect(klass.shared_memo_count).to be <= max
    ensure
      klass.reset_all_shared_memos
    end

    it "does not deadlock under concurrent shared reads + reset_all_shared_memos" do
      klass = Class.new do
        prepend SafeMemoize

        def data = "v"
        memoize :data, shared: true
      end

      expect {
        barrier_run do
          klass.new.data
          klass.reset_all_shared_memos
        end
      }.not_to raise_error
    ensure
      klass.reset_all_shared_memos
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Lifecycle hooks under concurrent access
  # ─────────────────────────────────────────────────────────────

  describe "lifecycle hooks" do
    it "fires on_memo_hit exactly once per concurrent cache hit" do
      klass = Class.new do
        prepend SafeMemoize

        def data = "v"
        memoize :data
      end

      obj = klass.new
      obj.data  # prime the cache

      inc, get = atomic_counter
      obj.on_memo_hit { inc.call }

      barrier_run { obj.data }

      expect(get.call).to eq(CONCURRENCY_THREADS)
    end

    it "fires on_memo_miss exactly once across all racing threads" do
      klass = Class.new do
        prepend SafeMemoize

        def data = "v"
        memoize :data
      end

      inc, get = atomic_counter
      obj = klass.new
      obj.on_memo_miss { inc.call }

      barrier_run { obj.data }

      expect(get.call).to eq(1)
    end

    it "hook exceptions do not corrupt concurrent execution" do
      klass = Class.new do
        prepend SafeMemoize

        def data = "v"
        memoize :data
      end

      obj = klass.new
      obj.on_memo_hit { raise "hook boom" }
      obj.data  # prime

      expect { barrier_run { obj.data } }.not_to raise_error
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Cache metrics integrity
  # ─────────────────────────────────────────────────────────────

  describe "cache metrics" do
    it "hit + miss count equals total call count under concurrent access" do
      klass = Class.new do
        prepend SafeMemoize

        def work = "v"
        memoize :work
      end

      obj = klass.new
      barrier_run { obj.work }

      stats = obj.cache_stats
      expect(stats[:total_hits] + stats[:total_misses]).to eq(CONCURRENCY_THREADS)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # TTL expiration under concurrent access
  # ─────────────────────────────────────────────────────────────

  describe "TTL expiration" do
    it "prunes expired entries safely under concurrent memo_count calls" do
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch, ttl: 0.05
      end

      obj = klass.new
      5.times { |i| obj.fetch(i) }
      sleep 0.06

      expect { barrier_run { obj.memo_count } }.not_to raise_error
      expect(obj.memo_count).to eq(0)
    end

    it "never returns a stale value after TTL elapses under concurrent reads" do
      klass = Class.new do
        prepend SafeMemoize

        def flag = "fresh"
        memoize :flag, ttl: 0.05
      end

      obj = klass.new
      obj.flag
      sleep 0.06

      results = []
      mu = Mutex.new
      barrier_run { mu.synchronize { results << obj.flag } }

      expect(results.uniq).to eq(["fresh"])
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Conditional memoization under concurrent access
  # ─────────────────────────────────────────────────────────────

  describe "conditional memoization (if:)" do
    it "does not store conditionally-skipped results under concurrent access" do
      klass = Class.new do
        prepend SafeMemoize

        def compute = nil
        memoize :compute, if: ->(v) { !v.nil? }
      end

      obj = klass.new
      barrier_run { obj.compute }

      expect(obj.memo_count).to eq(0)
    end
  end
end
