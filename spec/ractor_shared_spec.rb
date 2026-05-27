# frozen_string_literal: true

require "spec_helper"

RACTOR_SAFE_SUPPORTED =
  defined?(Ractor) &&
  RUBY_VERSION >= "3.0.0" &&
  Ractor.method_defined?(:take)

RSpec.describe "SafeMemoize ractor_safe: true" do
  before { skip "Ractor not available on this Ruby" unless RACTOR_SAFE_SUPPORTED }

  # Build a ractor_safe memoized class with an optional body proc.
  # The default body returns args.first.
  def make_ractor_class(ttl: nil, &body)
    body ||= proc { |*args| args.first }
    klass = Class.new { prepend SafeMemoize }
    klass.define_method(:work, &body)
    klass.memoize :work, shared: true, ractor_safe: true, ttl: ttl
    klass
  end

  # ─────────────────────────────────────────────────────────────
  # Argument validation
  # ─────────────────────────────────────────────────────────────

  describe "argument validation" do
    def bare_class
      Class.new do
        prepend SafeMemoize

        def compute = 42
      end
    end

    it "raises when shared: true is not set" do
      expect { bare_class.memoize :compute, ractor_safe: true }
        .to raise_error(ArgumentError, /requires shared: true/)
    end

    it "raises for if:" do
      expect { bare_class.memoize :compute, shared: true, ractor_safe: true, if: ->(v) { v } }
        .to raise_error(ArgumentError, /incompatible with if:/)
    end

    it "raises for unless:" do
      expect { bare_class.memoize :compute, shared: true, ractor_safe: true, unless: ->(v) { v } }
        .to raise_error(ArgumentError, /incompatible with if:/)
    end

    it "raises for max_size:" do
      expect { bare_class.memoize :compute, shared: true, ractor_safe: true, max_size: 10 }
        .to raise_error(ArgumentError, /incompatible with max_size:/)
    end

    it "raises for ttl_refresh:" do
      expect { bare_class.memoize :compute, shared: true, ractor_safe: true, ttl: 10, ttl_refresh: true }
        .to raise_error(ArgumentError, /incompatible with ttl_refresh:/)
    end

    it "raises for key:" do
      expect { bare_class.memoize :compute, shared: true, ractor_safe: true, key: ->(*a) { a } }
        .to raise_error(ArgumentError, /incompatible with key:/)
    end

    it "raises for store:" do
      store = SafeMemoize::Stores::Memory.new
      expect { bare_class.memoize :compute, shared: true, ractor_safe: true, store: store }
        .to raise_error(ArgumentError, /store:/)
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Basic caching
  # ─────────────────────────────────────────────────────────────

  describe "basic caching" do
    it "caches the result on repeated calls" do
      calls = 0
      klass = make_ractor_class {
        calls += 1
        "result"
      }
      obj = klass.new
      expect(obj.work).to eq("result")
      expect(obj.work).to eq("result")
      expect(calls).to eq(1)
    ensure
      klass.reset_all_ractor_memos
    end

    it "caches nil correctly" do
      calls = 0
      klass = make_ractor_class {
        calls += 1
        nil
      }
      obj = klass.new
      expect(obj.work).to be_nil
      expect(obj.work).to be_nil
      expect(calls).to eq(1)
    ensure
      klass.reset_all_ractor_memos
    end

    it "caches false correctly" do
      calls = 0
      klass = make_ractor_class {
        calls += 1
        false
      }
      obj = klass.new
      expect(obj.work).to be(false)
      expect(obj.work).to be(false)
      expect(calls).to eq(1)
    ensure
      klass.reset_all_ractor_memos
    end

    it "shares the cache across all instances" do
      calls = 0
      klass = make_ractor_class {
        calls += 1
        "shared"
      }
      klass.new.work
      klass.new.work
      klass.new.work
      expect(calls).to eq(1)
    ensure
      klass.reset_all_ractor_memos
    end

    it "caches per argument set" do
      calls = 0
      klass = make_ractor_class { |n|
        calls += 1
        n * 2
      }
      obj = klass.new
      obj.work(1)
      obj.work(1)
      obj.work(2)
      obj.work(2)
      expect(calls).to eq(2)
    ensure
      klass.reset_all_ractor_memos
    end

    it "bypasses cache when a block is given" do
      calls = 0
      klass = Class.new do
        prepend SafeMemoize

        define_method(:work) { |&blk|
          calls += 1
          blk&.call
        }
        memoize :work, shared: true, ractor_safe: true
      end
      obj = klass.new
      obj.work {}
      obj.work {}
      expect(calls).to eq(2)
    ensure
      klass.reset_all_ractor_memos
    end

    it "raises ArgumentError for non-Ractor-shareable return values" do
      klass = make_ractor_class { Mutex.new }
      expect { klass.new.work }
        .to raise_error(ArgumentError, /ractor_safe: memoized values must be Ractor-shareable/)
    end

    it "deep-freezes the cached value" do
      klass = make_ractor_class { "hello" }
      result = klass.new.work
      expect(result).to be_frozen
    ensure
      klass.reset_all_ractor_memos
    end
  end

  # ─────────────────────────────────────────────────────────────
  # TTL
  # ─────────────────────────────────────────────────────────────

  describe "TTL" do
    it "re-computes after the entry expires" do
      calls = 0
      klass = make_ractor_class(ttl: 0.05) {
        calls += 1
        "v"
      }
      obj = klass.new
      obj.work
      sleep(0.1)
      obj.work
      expect(calls).to eq(2)
    ensure
      klass.reset_all_ractor_memos
    end

    it "serves from cache within TTL" do
      calls = 0
      klass = make_ractor_class(ttl: 60) {
        calls += 1
        "v"
      }
      obj = klass.new
      obj.work
      obj.work
      expect(calls).to eq(1)
    ensure
      klass.reset_all_ractor_memos
    end

    it "does not count expired entries in ractor_memo_count" do
      klass = make_ractor_class(ttl: 0.05) { "v" }
      klass.new.work
      expect(klass.ractor_memo_count).to eq(1)
      sleep(0.1)
      expect(klass.ractor_memo_count).to eq(0)
    ensure
      klass.reset_all_ractor_memos
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Thread safety (multiple threads in the main Ractor)
  # ─────────────────────────────────────────────────────────────

  describe "thread safety" do
    it "returns consistent values from many concurrent threads" do
      klass = Class.new do
        prepend SafeMemoize

        def compute = "value"
        memoize :compute, shared: true, ractor_safe: true
      end

      results = 20.times.map { Thread.new { klass.new.compute } }.map(&:value)
      expect(results.uniq).to eq(["value"])
    ensure
      klass.reset_all_ractor_memos
    end

    it "never returns stale results under concurrent access" do
      klass = Class.new do
        prepend SafeMemoize

        def fetch(n) = n * 2
        memoize :fetch, shared: true, ractor_safe: true
      end

      threads = 10.times.map { |i| Thread.new { klass.new.fetch(i % 3) } }
      results = threads.map(&:value)
      expected = results.map { |r| [2, 4, 0].include?(r) }
      expect(expected).to all be(true)
    ensure
      klass.reset_all_ractor_memos
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Public API
  # ─────────────────────────────────────────────────────────────

  describe "#ractor_memoized?" do
    let(:klass) do
      k = Class.new { prepend SafeMemoize }
      k.define_method(:work) { |n| n * 2 }
      k.memoize :work, shared: true, ractor_safe: true
      k
    end

    after { klass.reset_all_ractor_memos }

    it "returns false before the first call" do
      expect(klass.ractor_memoized?(:work, 1)).to be(false)
    end

    it "returns true after a call" do
      klass.new.work(1)
      expect(klass.ractor_memoized?(:work, 1)).to be(true)
    end

    it "returns false for different args" do
      klass.new.work(1)
      expect(klass.ractor_memoized?(:work, 2)).to be(false)
    end

    it "accepts a string method name" do
      klass.new.work(1)
      expect(klass.ractor_memoized?("work", 1)).to be(true)
    end

    it "returns false after TTL expires" do
      k2 = Class.new { prepend SafeMemoize }
      k2.define_method(:work) { |n| n * 2 }
      k2.memoize :work, shared: true, ractor_safe: true, ttl: 0.05
      k2.new.work(1)
      sleep(0.1)
      expect(k2.ractor_memoized?(:work, 1)).to be(false)
    ensure
      k2.reset_all_ractor_memos
    end
  end

  describe "#ractor_memo_count" do
    let(:klass) do
      k = Class.new { prepend SafeMemoize }
      k.define_method(:work) { |n| n * 2 }
      k.memoize :work, shared: true, ractor_safe: true
      k
    end

    after { klass.reset_all_ractor_memos }

    it "returns 0 for an empty cache" do
      expect(klass.ractor_memo_count).to eq(0)
    end

    it "counts all live entries with no argument" do
      klass.new.work(1)
      klass.new.work(2)
      expect(klass.ractor_memo_count).to eq(2)
    end

    it "counts entries for a specific method" do
      klass.new.work(1)
      klass.new.work(2)
      expect(klass.ractor_memo_count(:work)).to eq(2)
    end

    it "returns 0 for an unknown method name" do
      klass.new.work(1)
      expect(klass.ractor_memo_count(:other)).to eq(0)
    end
  end

  describe "#reset_ractor_memo" do
    it "removes a specific entry by args" do
      calls = 0
      klass = make_ractor_class { |n|
        calls += 1
        n * 2
      }
      klass.new.work(1)
      klass.new.work(2)
      klass.reset_ractor_memo(:work, 1)
      klass.new.work(1)
      klass.new.work(2)
      expect(calls).to eq(3)
    ensure
      klass.reset_all_ractor_memos
    end

    it "removes all entries for a method when called with no args" do
      calls = 0
      klass = make_ractor_class { |n|
        calls += 1
        n * 2
      }
      klass.new.work(1)
      klass.new.work(2)
      klass.reset_ractor_memo(:work)
      klass.new.work(1)
      klass.new.work(2)
      expect(calls).to eq(4)
    ensure
      klass.reset_all_ractor_memos
    end

    it "accepts a string method name" do
      calls = 0
      klass = make_ractor_class {
        calls += 1
        "v"
      }
      klass.new.work
      klass.reset_ractor_memo("work")
      klass.new.work
      expect(calls).to eq(2)
    ensure
      klass.reset_all_ractor_memos
    end

    it "is a no-op when the entry does not exist" do
      klass = make_ractor_class { "v" }
      expect { klass.reset_ractor_memo(:work, 99) }.not_to raise_error
    ensure
      klass.reset_all_ractor_memos
    end
  end

  describe "#reset_all_ractor_memos" do
    it "clears the entire cache" do
      calls = 0
      klass = make_ractor_class { |n|
        calls += 1
        n * 2
      }
      klass.new.work(1)
      klass.new.work(2)
      klass.reset_all_ractor_memos
      klass.new.work(1)
      klass.new.work(2)
      expect(calls).to eq(4)
    ensure
      klass.reset_all_ractor_memos
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Lifecycle hooks
  # ─────────────────────────────────────────────────────────────

  describe "lifecycle hooks" do
    it "fires on_miss on first call" do
      missed = []
      klass = make_ractor_class { "v" }
      obj = klass.new
      obj.on_memo_miss { |k, _r| missed << k }
      obj.work
      obj.work
      expect(missed.size).to eq(1)
    ensure
      klass.reset_all_ractor_memos
    end

    it "fires on_hit on cache hits" do
      hits = []
      klass = make_ractor_class { "v" }
      obj = klass.new
      obj.on_memo_hit { |k, _r| hits << k }
      obj.work
      obj.work
      obj.work
      expect(hits.size).to eq(2)
    ensure
      klass.reset_all_ractor_memos
    end

    it "fires on_store when the value is first cached" do
      stored = []
      klass = make_ractor_class { "v" }
      obj = klass.new
      obj.on_memo_store { |k, _r| stored << k }
      obj.work
      obj.work
      expect(stored.size).to eq(1)
    ensure
      klass.reset_all_ractor_memos
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Metrics
  # ─────────────────────────────────────────────────────────────

  describe "metrics" do
    it "tracks hits and misses per instance" do
      klass = make_ractor_class { "v" }
      obj = klass.new
      obj.work
      obj.work
      obj.work
      stats = obj.cache_stats
      expect(stats[:total_hits]).to eq(2)
      expect(stats[:total_misses]).to eq(1)
    ensure
      klass.reset_all_ractor_memos
    end
  end

  # ─────────────────────────────────────────────────────────────
  # Worker Ractor access
  # ─────────────────────────────────────────────────────────────

  describe "worker Ractor access" do
    before { skip "Ractor#take not available" unless Ractor.method_defined?(:take) }

    it "allows a worker Ractor to call the memoized method" do
      klass = Class.new do
        prepend SafeMemoize

        def compute = 42
        memoize :compute, shared: true, ractor_safe: true
      end

      result = Ractor.new(klass) { |k| k.new.compute }.take
      expect(result).to eq(42)
    ensure
      klass.reset_all_ractor_memos
    end

    it "does not raise un-shareable Proc when calling from a worker Ractor" do
      klass = Class.new do
        prepend SafeMemoize

        def compute = "hello"
        memoize :compute, shared: true, ractor_safe: true
      end

      expect { Ractor.new(klass) { |k| k.new.compute }.take }.not_to raise_error
    ensure
      klass.reset_all_ractor_memos
    end

    it "shares the cached value between the main Ractor and a worker Ractor" do
      klass = Class.new do
        prepend SafeMemoize

        def compute = 42
        memoize :compute, shared: true, ractor_safe: true
      end

      klass.new.compute
      result = Ractor.new(klass) { |k| k.new.compute }.take
      expect(result).to eq(42)
      expect(klass.ractor_memo_count(:compute)).to eq(1)
    ensure
      klass.reset_all_ractor_memos
    end

    it "allows multiple worker Ractors to read the same cached value" do
      klass = Class.new do
        prepend SafeMemoize

        def compute = 99
        memoize :compute, shared: true, ractor_safe: true
      end

      ractors = 4.times.map { Ractor.new(klass) { |k| k.new.compute } }
      results = ractors.map(&:take)
      expect(results).to all eq(99)
    ensure
      klass.reset_all_ractor_memos
    end
  end
end
