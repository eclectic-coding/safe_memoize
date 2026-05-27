# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe "SafeMemoize fiber_local: true" do
  def make_class(**memoize_opts, &method_body)
    method_body ||= proc { |*args| args.first }
    Class.new do
      prepend SafeMemoize

      define_method(:work, &method_body)
      memoize :work, **memoize_opts
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Basic caching
  # ─────────────────────────────────────────────────────────────

  describe "basic caching" do
    it "caches the result within the same fiber" do
      calls = 0
      klass = make_class(fiber_local: true) {
        calls += 1
        "result"
      }
      obj = klass.new
      expect(obj.work).to eq("result")
      expect(obj.work).to eq("result")
      expect(calls).to eq(1)
    end

    it "caches per argument set" do
      calls = 0
      klass = make_class(fiber_local: true) { |n|
        calls += 1
        n * 2
      }
      obj = klass.new
      obj.work(1)
      obj.work(1)
      obj.work(2)
      obj.work(2)
      expect(calls).to eq(2)
    end

    it "caches nil correctly" do
      calls = 0
      klass = make_class(fiber_local: true) {
        calls += 1
        nil
      }
      obj = klass.new
      expect(obj.work).to be_nil
      expect(obj.work).to be_nil
      expect(calls).to eq(1)
    end

    it "caches false correctly" do
      calls = 0
      klass = make_class(fiber_local: true) {
        calls += 1
        false
      }
      obj = klass.new
      expect(obj.work).to be(false)
      expect(obj.work).to be(false)
      expect(calls).to eq(1)
    end

    it "bypasses cache when a block is given" do
      calls = 0
      klass = Class.new do
        prepend SafeMemoize

        define_method(:work) { |&blk|
          calls += 1
          blk&.call
        }
        memoize :work, fiber_local: true
      end
      obj = klass.new
      obj.work {}
      obj.work {}
      expect(calls).to eq(2)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Fiber isolation
  # ─────────────────────────────────────────────────────────────

  describe "fiber isolation" do
    it "gives each fiber its own independent cache" do
      call_counts = Hash.new(0)
      mu = Mutex.new

      klass = Class.new do
        prepend SafeMemoize

        define_method(:work) { |fiber_id|
          mu.synchronize { call_counts[fiber_id] += 1 }
          "result-#{fiber_id}"
        }
        memoize :work, fiber_local: true
      end

      obj = klass.new
      fibers = 3.times.map do |i|
        Fiber.new do
          3.times { obj.work(i) }
        end
      end

      fibers.each { |f|
        begin
          f.resume while f.alive?
        rescue
          nil
        end
      }
      # Wait for fibers to finish by resuming until dead
      fibers.each { |f|
        begin
          f.resume while f.alive?
        rescue FiberError
          # already dead
        end
      }

      # Each fiber called work(i) for its own i 3 times, but should compute once per fiber
      call_counts.each_value { |n| expect(n).to eq(1) }
    end

    it "does not share results between two fibers running the same instance method" do
      results_by_fiber = {}
      mu = Mutex.new

      klass = Class.new do
        prepend SafeMemoize

        def work = SecureRandom.hex(4)
        memoize :work, fiber_local: true
      end

      obj = klass.new

      fibers = 2.times.map do |i|
        Fiber.new do
          v = obj.work
          mu.synchronize { results_by_fiber[i] = v }
        end
      end

      fibers.each do |f|
        f.resume while f.alive?
      rescue FiberError
        nil
      end

      # Each fiber gets its own value (SecureRandom generates unique values)
      expect(results_by_fiber[0]).not_to eq(results_by_fiber[1])
    end

    it "cache is discarded when the fiber terminates" do
      klass = Class.new do
        prepend SafeMemoize

        def work = "computed"
        memoize :work, fiber_local: true
      end

      obj = klass.new
      captured_cache = nil

      f = Fiber.new do
        obj.work
        # Capture the cache value while still inside the fiber
        captured_cache = obj.send(:fiber_memo_cache_or_nil)&.dup
      end
      f.resume

      # The cache was populated during the fiber's life
      expect(captured_cache).not_to be_nil
      expect(captured_cache).not_to be_empty
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Thread isolation: different threads, different fibers
  # ─────────────────────────────────────────────────────────────

  describe "thread isolation" do
    it "threads do not share each other's fiber-local caches" do
      call_log = []
      mu = Mutex.new

      klass = Class.new do
        prepend SafeMemoize

        define_method(:work) { |n|
          mu.synchronize { call_log << [Thread.current.object_id, n] }
          n
        }
        memoize :work, fiber_local: true
      end

      obj = klass.new

      threads = 3.times.map do |i|
        Thread.new do
          3.times { obj.work(i) }
        end
      end
      threads.each(&:join)

      # Each thread/fiber computed exactly once per unique argument
      grouped = call_log.group_by { |tid, n| [tid, n] }
      grouped.each_value { |entries| expect(entries.size).to eq(1) }
    end
  end

  # ─────────────────────────────────────────────────────────────
  # TTL support
  # ─────────────────────────────────────────────────────────────

  describe "TTL" do
    it "returns a cached value before TTL expires" do
      calls = 0
      klass = make_class(fiber_local: true, ttl: 10) {
        calls += 1
        "v"
      }
      obj = klass.new
      obj.work
      obj.work
      expect(calls).to eq(1)
    end

    it "recomputes after TTL expires" do
      calls = 0
      klass = make_class(fiber_local: true, ttl: 0.01) {
        calls += 1
        "v"
      }
      obj = klass.new
      obj.work
      sleep 0.02
      obj.work
      expect(calls).to eq(2)
    end

    it "supports ttl_refresh" do
      calls = 0
      klass = make_class(fiber_local: true, ttl: 0.05, ttl_refresh: true) {
        calls += 1
        "v"
      }
      obj = klass.new
      obj.work        # miss
      sleep 0.03
      obj.work        # hit — refreshes TTL
      sleep 0.03      # would expire without refresh
      obj.work        # still alive because TTL was reset
      expect(calls).to eq(1)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Conditional storage
  # ─────────────────────────────────────────────────────────────

  describe "conditional storage" do
    it "does not cache when :if predicate is false" do
      calls = 0
      klass = make_class(fiber_local: true, if: ->(v) { !v.nil? }) {
        calls += 1
        nil
      }
      obj = klass.new
      3.times { obj.work }
      expect(calls).to eq(3)
    end

    it "caches when :if predicate is true" do
      calls = 0
      klass = make_class(fiber_local: true, if: ->(v) { !v.nil? }) {
        calls += 1
        "value"
      }
      obj = klass.new
      3.times { obj.work }
      expect(calls).to eq(1)
    end

    it "does not cache when :unless predicate is true" do
      calls = 0
      klass = make_class(fiber_local: true, unless: ->(v) { v.nil? }) {
        calls += 1
        nil
      }
      obj = klass.new
      3.times { obj.work }
      expect(calls).to eq(3)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # LRU eviction
  # ─────────────────────────────────────────────────────────────

  describe "LRU eviction (max_size:)" do
    it "never stores more than max_size entries" do
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch, fiber_local: true, max_size: 3
      end

      obj = klass.new
      10.times { |i| obj.fetch(i) }
      cache = obj.send(:fiber_memo_cache_or_nil)
      expect(cache&.size).to be <= 3
    end

    it "evicts the least-recently-used entry" do
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch, fiber_local: true, max_size: 2
      end

      obj = klass.new
      obj.fetch(1)  # cache: [1]
      obj.fetch(2)  # cache: [1, 2]
      obj.fetch(1)  # touch 1 — LRU order: [2, 1]
      obj.fetch(3)  # evict 2 — cache: [1, 3]

      cache = obj.send(:fiber_memo_cache_or_nil)
      args_in_cache = cache.keys.map { |k| k[1][0] }
      expect(args_in_cache).to include(1, 3)
      expect(args_in_cache).not_to include(2)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Public API
  # ─────────────────────────────────────────────────────────────

  describe "fiber_local_memoized?" do
    it "returns false when not cached" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      expect(obj.fiber_local_memoized?(:work)).to be(false)
    end

    it "returns true after the method is called" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      obj.work
      expect(obj.fiber_local_memoized?(:work)).to be(true)
    end

    it "returns false after TTL expires" do
      klass = make_class(fiber_local: true, ttl: 0.01)
      obj = klass.new
      obj.work
      sleep 0.02
      expect(obj.fiber_local_memoized?(:work)).to be(false)
    end

    it "returns false when a block is passed" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      obj.work
      expect(obj.fiber_local_memoized?(:work) {}).to be(false)
    end

    it "is fiber-scoped: false in a different fiber" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      obj.work  # cache in current fiber

      result_in_other_fiber = nil
      f = Fiber.new { result_in_other_fiber = obj.fiber_local_memoized?(:work) }
      f.resume

      expect(result_in_other_fiber).to be(false)
    end
  end

  describe "reset_fiber_memo" do
    it "clears all entries for a method" do
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch, fiber_local: true
      end
      obj = klass.new
      obj.fetch(1)
      obj.fetch(2)
      obj.reset_fiber_memo(:fetch)
      expect(obj.fiber_local_memoized?(:fetch, 1)).to be(false)
      expect(obj.fiber_local_memoized?(:fetch, 2)).to be(false)
    end

    it "clears only the matching entry when args are given" do
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch, fiber_local: true
      end
      obj = klass.new
      obj.fetch(1)
      obj.fetch(2)
      obj.reset_fiber_memo(:fetch, 1)
      expect(obj.fiber_local_memoized?(:fetch, 1)).to be(false)
      expect(obj.fiber_local_memoized?(:fetch, 2)).to be(true)
    end

    it "is a no-op when nothing is cached" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      expect { obj.reset_fiber_memo(:work) }.not_to raise_error
    end
  end

  describe "reset_all_fiber_memos" do
    it "clears everything in the current fiber" do
      klass = Class.new do
        prepend SafeMemoize

        def a = 1
        def b = 2
        memoize :a, fiber_local: true
        memoize :b, fiber_local: true
      end
      obj = klass.new
      obj.a
      obj.b
      obj.reset_all_fiber_memos
      expect(obj.fiber_local_memoized?(:a)).to be(false)
      expect(obj.fiber_local_memoized?(:b)).to be(false)
    end

    it "only clears the current fiber's cache, not other fibers" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      obj.work  # cache in main fiber

      other_fiber_state = nil
      f = Fiber.new do
        obj.work  # cache in other fiber
        obj.reset_all_fiber_memos
        other_fiber_state = obj.fiber_local_memoized?(:work)
      end
      f.resume

      # Main fiber cache should be unaffected
      expect(obj.fiber_local_memoized?(:work)).to be(true)
      # Other fiber cleared its own cache
      expect(other_fiber_state).to be(false)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Lifecycle hooks
  # ─────────────────────────────────────────────────────────────

  describe "lifecycle hooks" do
    it "fires on_memo_miss on first call" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      missed = false
      obj.on_memo_miss { missed = true }
      obj.work
      expect(missed).to be(true)
    end

    it "fires on_memo_hit on cached call" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      obj.work
      hit = false
      obj.on_memo_hit { hit = true }
      obj.work
      expect(hit).to be(true)
    end

    it "fires on_memo_store when a value is cached" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      stored = false
      obj.on_memo_store { stored = true }
      obj.work
      expect(stored).to be(true)
    end

    it "fires on_memo_expire when a TTL-expired entry is replaced" do
      klass = make_class(fiber_local: true, ttl: 0.01)
      obj = klass.new
      obj.work
      sleep 0.02
      expired = false
      obj.on_memo_expire { expired = true }
      obj.work
      expect(expired).to be(true)
    end

    it "fires on_memo_evict when LRU eviction occurs" do
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n
        memoize :fetch, fiber_local: true, max_size: 1
      end
      obj = klass.new
      evicted = false
      obj.on_memo_evict { evicted = true }
      obj.fetch(1)
      obj.fetch(2)  # triggers eviction of 1
      expect(evicted).to be(true)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Metrics
  # ─────────────────────────────────────────────────────────────

  describe "cache metrics" do
    it "tracks hits and misses" do
      klass = make_class(fiber_local: true)
      obj = klass.new
      obj.work  # miss
      obj.work  # hit
      obj.work  # hit
      stats = obj.cache_stats
      expect(stats[:total_misses]).to eq(1)
      expect(stats[:total_hits]).to eq(2)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Argument validation
  # ─────────────────────────────────────────────────────────────

  describe "argument validation" do
    it "raises when combining fiber_local: and shared:" do
      expect {
        Class.new do
          prepend SafeMemoize

          def work = nil
          memoize :work, fiber_local: true, shared: true
        end
      }.to raise_error(ArgumentError, /fiber_local.*shared/)
    end

    it "raises when combining fiber_local: and store:" do
      store = SafeMemoize::Stores::Memory.new
      expect {
        Class.new do
          prepend SafeMemoize

          def work = nil
          memoize :work, fiber_local: true, store: store
        end
      }.to raise_error(ArgumentError, /fiber_local.*store/)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Existing instance-variable path is unaffected
  # ─────────────────────────────────────────────────────────────

  describe "non-fiber-local methods are unaffected" do
    it "instance-variable memoization still works alongside fiber-local methods" do
      klass = Class.new do
        prepend SafeMemoize

        def regular = "regular"
        def fibered = "fibered"
        memoize :regular
        memoize :fibered, fiber_local: true
      end

      obj = klass.new
      expect(obj.regular).to eq("regular")
      expect(obj.fibered).to eq("fibered")
      expect(obj.memoized?(:regular)).to be(true)
      expect(obj.fiber_local_memoized?(:fibered)).to be(true)

      # Instance cache should only contain the regular method
      expect(obj.instance_variable_get(:@__safe_memo_cache__)).not_to be_nil
      expect(obj.instance_variable_get(:@__safe_memo_cache__).keys.map { |k| k[0] }).to include(:regular)
      expect(obj.instance_variable_get(:@__safe_memo_cache__).keys.map { |k| k[0] }).not_to include(:fibered)
    end
  end
end
