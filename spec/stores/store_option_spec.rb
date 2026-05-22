# frozen_string_literal: true

require "spec_helper"

RSpec.describe "memoize store: option" do
  let(:store) { SafeMemoize::Stores::Memory.new }

  def build_class(store:, **opts, &body)
    Class.new do
      prepend SafeMemoize

      class_eval(&body) if body
      define_method(:compute) { |*args| args.sum }
      memoize :compute, store: store, **opts
    end
  end

  # ---------------------------------------------------------------------------
  # Basic read / write
  # ---------------------------------------------------------------------------

  describe "basic caching" do
    let(:klass) { build_class(store: store) }
    let(:obj) { klass.new }

    it "caches the return value on first call" do
      obj.compute(1, 2)
      expect(store.read([:compute, [1, 2], {}])).to eq 3
    end

    it "returns the same value on repeated calls" do
      expect(obj.compute(1, 2)).to eq 3
      expect(obj.compute(1, 2)).to eq 3
    end

    it "computes only once for the same arguments" do
      call_count = 0
      s = store
      klass = Class.new do
        prepend SafeMemoize

        define_method(:work) do
          call_count += 1
          call_count
        end
        memoize :work, store: s
      end
      obj = klass.new
      obj.work
      obj.work
      expect(call_count).to eq 1
    end

    it "caches nil correctly" do
      s = store
      klass = Class.new do
        prepend SafeMemoize

        def nullable = nil
        memoize :nullable, store: s
      end
      obj = klass.new
      obj.nullable
      expect(store.exist?([:nullable, [], {}])).to be true
    end

    it "caches false correctly" do
      s = store
      klass = Class.new do
        prepend SafeMemoize

        def falsy = false
        memoize :falsy, store: s
      end
      obj = klass.new
      expect(obj.falsy).to be false
      expect(obj.falsy).to be false
      expect(store.exist?([:falsy, [], {}])).to be true
    end

    it "caches different argument combinations independently" do
      expect(obj.compute(1)).to eq 1
      expect(obj.compute(2)).to eq 2
      expect(obj.compute(1)).to eq 1
    end

    it "passes blocks through without caching" do
      result = obj.compute(1, 2) { "block" }
      expect(result).to be_a(String).or eq(3) # block bypasses cache
      expect(store.exist?([:compute, [1, 2], {}])).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Store is shared across instances
  # ---------------------------------------------------------------------------

  describe "cross-instance sharing" do
    it "shares cached values across all instances of the class" do
      call_count = 0
      s = store
      klass = Class.new do
        prepend SafeMemoize

        define_method(:shared_work) do
          call_count += 1
          call_count
        end
        memoize :shared_work, store: s
      end

      klass.new.shared_work
      klass.new.shared_work
      expect(call_count).to eq 1
    end
  end

  # ---------------------------------------------------------------------------
  # TTL
  # ---------------------------------------------------------------------------

  describe "ttl: option" do
    it "passes expires_in to the store on write" do
      writes = []
      spy = Class.new(SafeMemoize::Stores::Memory) do
        define_method(:write) { |key, value, expires_in: nil|
          writes << {key: key, value: value, expires_in: expires_in}
          super(key, value, expires_in: expires_in)
        }
      end.new

      s = spy
      klass = Class.new do
        prepend SafeMemoize

        def compute = 42
        memoize :compute, store: s, ttl: 30
      end

      klass.new.compute
      expect(writes.last).to include(value: 42, expires_in: 30.0)
    end

    it "expires entries after the TTL" do
      klass = build_class(store: store, ttl: 0.01)
      obj = klass.new
      obj.compute(5)
      sleep 0.02
      expect(store.read([:compute, [5], {}])).to be SafeMemoize::Stores::Base::MISS
    end
  end

  # ---------------------------------------------------------------------------
  # ttl_refresh:
  # ---------------------------------------------------------------------------

  describe "ttl_refresh: option" do
    it "re-writes the entry on every cache hit to extend TTL" do
      write_count = 0
      s = Class.new(SafeMemoize::Stores::Memory) do
        define_method(:write) { |key, value, expires_in: nil|
          write_count += 1
          super(key, value, expires_in: expires_in)
        }
      end.new

      klass = Class.new do
        prepend SafeMemoize

        def compute = 99
        memoize :compute, store: s, ttl: 60, ttl_refresh: true
      end

      obj = klass.new
      obj.compute  # miss → write
      obj.compute  # hit → refresh write
      obj.compute  # hit → refresh write

      expect(write_count).to eq 3
    end
  end

  # ---------------------------------------------------------------------------
  # Conditional storage
  # ---------------------------------------------------------------------------

  describe "if: option" do
    it "stores when the condition is met" do
      klass = build_class(store: store, if: ->(v) { v > 0 })
      klass.new.compute(1, 1)
      expect(store.exist?([:compute, [1, 1], {}])).to be true
    end

    it "does not store when the condition is not met" do
      klass = build_class(store: store, if: ->(v) { v > 10 })
      klass.new.compute(1, 1)
      expect(store.exist?([:compute, [1, 1], {}])).to be false
    end
  end

  describe "unless: option" do
    it "does not store when the condition is truthy" do
      klass = build_class(store: store, unless: ->(v) { v < 10 })
      klass.new.compute(1, 1)
      expect(store.exist?([:compute, [1, 1], {}])).to be false
    end

    it "stores when the condition is falsy" do
      klass = build_class(store: store, unless: ->(v) { v < 0 })
      klass.new.compute(5, 5)
      expect(store.exist?([:compute, [5, 5], {}])).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Hooks
  # ---------------------------------------------------------------------------

  describe "lifecycle hooks" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        def compute = 7
        memoize :compute, store: SafeMemoize::Stores::Memory.new
      end
    end
    let(:obj) { klass.new }

    it "fires on_miss on a cache miss" do
      fired = false
      obj.on_memo_miss { fired = true }
      obj.compute
      expect(fired).to be true
    end

    it "fires on_store when a value is written" do
      fired = false
      obj.on_memo_store { fired = true }
      obj.compute
      expect(fired).to be true
    end

    it "fires on_hit on a cache hit" do
      fired = false
      obj.on_memo_hit { fired = true }
      obj.compute
      obj.compute
      expect(fired).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Metrics
  # ---------------------------------------------------------------------------

  describe "cache metrics" do
    let(:klass) do
      s = store
      Class.new do
        prepend SafeMemoize

        def work = 1
        memoize :work, store: s
      end
    end
    let(:obj) { klass.new }

    it "tracks hits and misses" do
      obj.work
      obj.work
      stats = obj.cache_stats
      expect(stats[:total_hits]).to eq 1
      expect(stats[:total_misses]).to eq 1
    end
  end

  # ---------------------------------------------------------------------------
  # Visibility preservation
  # ---------------------------------------------------------------------------

  describe "method visibility" do
    it "preserves private visibility" do
      s = store
      klass = Class.new do
        prepend SafeMemoize

        private

        def secret = 42
        memoize :secret, store: s
      end
      obj = klass.new
      expect { obj.secret }.to raise_error(NoMethodError)
      expect(obj.send(:secret)).to eq 42
    end
  end

  # ---------------------------------------------------------------------------
  # ArgumentError guards
  # ---------------------------------------------------------------------------

  describe "ArgumentError guards" do
    it "raises when store: is not a Stores::Base instance" do
      expect do
        Class.new do
          prepend SafeMemoize

          def work = 1
          memoize :work, store: "not a store"
        end
      end.to raise_error(ArgumentError, /store:.*Stores::Base/)
    end

    it "raises when max_size: is combined with store:" do
      expect do
        Class.new do
          prepend SafeMemoize

          def work = 1
          memoize :work, store: SafeMemoize::Stores::Memory.new, max_size: 10
        end
      end.to raise_error(ArgumentError, /max_size.*store/)
    end

    it "raises when shared: is combined with store:" do
      expect do
        Class.new do
          prepend SafeMemoize

          def work = 1
          memoize :work, store: SafeMemoize::Stores::Memory.new, shared: true
        end
      end.to raise_error(ArgumentError, /shared.*store/)
    end
  end
end
