# frozen_string_literal: true

RSpec.describe "SafeMemoize named shared caches" do
  after do
    SafeMemoize.reset_shared_caches!
    SafeMemoize.reset_configuration!
  end

  # ---------------------------------------------------------------------------
  # Registry API
  # ---------------------------------------------------------------------------

  describe "SafeMemoize.shared_cache" do
    it "auto-creates a Memory store on first access" do
      store = SafeMemoize.shared_cache("widgets")
      expect(store).to be_a(SafeMemoize::Stores::Memory)
    end

    it "returns the same store on repeated calls" do
      expect(SafeMemoize.shared_cache("widgets")).to be(SafeMemoize.shared_cache("widgets"))
    end

    it "returns different stores for different names" do
      expect(SafeMemoize.shared_cache("a")).not_to be(SafeMemoize.shared_cache("b"))
    end
  end

  describe "SafeMemoize.register_shared_cache" do
    it "replaces the store for a name" do
      custom = SafeMemoize::Stores::Memory.new
      SafeMemoize.register_shared_cache("orders", custom)
      expect(SafeMemoize.shared_cache("orders")).to be(custom)
    end

    it "raises ArgumentError for a non-store value" do
      expect { SafeMemoize.register_shared_cache("x", "oops") }
        .to raise_error(ArgumentError, /Stores::Base/)
    end
  end

  describe "SafeMemoize.clear_shared_cache" do
    it "clears all entries in the named store" do
      store = SafeMemoize.shared_cache("products")
      store.write([:find, [1], {}], "cached")
      SafeMemoize.clear_shared_cache("products")
      expect(store.keys).to be_empty
    end

    it "is a no-op for an unregistered name" do
      expect { SafeMemoize.clear_shared_cache("nonexistent") }.not_to raise_error
    end
  end

  describe "SafeMemoize.drop_shared_cache" do
    it "removes the named cache from the registry" do
      SafeMemoize.shared_cache("tmp")
      SafeMemoize.drop_shared_cache("tmp")
      expect(SafeMemoize.shared_caches).not_to have_key("tmp")
    end

    it "returns the removed store" do
      store = SafeMemoize.shared_cache("tmp")
      expect(SafeMemoize.drop_shared_cache("tmp")).to be(store)
    end

    it "returns nil for an unregistered name" do
      expect(SafeMemoize.drop_shared_cache("ghost")).to be_nil
    end
  end

  describe "SafeMemoize.shared_caches" do
    it "returns a snapshot of all registered caches" do
      SafeMemoize.shared_cache("a")
      SafeMemoize.shared_cache("b")
      expect(SafeMemoize.shared_caches.keys).to contain_exactly("a", "b")
    end

    it "returns a dup — mutations do not affect the registry" do
      SafeMemoize.shared_cache("orig")
      SafeMemoize.shared_caches["injected"] = SafeMemoize::Stores::Memory.new
      expect(SafeMemoize.shared_caches).not_to have_key("injected")
    end
  end

  describe "SafeMemoize.reset_shared_caches!" do
    it "empties the registry" do
      SafeMemoize.shared_cache("x")
      SafeMemoize.reset_shared_caches!
      expect(SafeMemoize.shared_caches).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # shared_cache: option on memoize
  # ---------------------------------------------------------------------------

  describe "shared_cache: option" do
    def make_class(cache_name, &method_body)
      Class.new do
        prepend SafeMemoize

        define_method(:fetch, &method_body || proc { |id| id })
        memoize :fetch, shared_cache: cache_name
      end
    end

    it "caches the result" do
      klass = make_class("items")
      obj = klass.new
      obj.fetch(1)
      obj.fetch(1)
      expect(SafeMemoize.shared_cache("items").keys.length).to eq(1)
    end

    it "shares the cache across instances of the same class" do
      calls = 0
      klass = make_class("counters") { |_| calls += 1 }
      klass.new.fetch(42)
      klass.new.fetch(42)
      expect(calls).to eq(1)
    end

    it "shares the cache across instances of different classes" do
      calls = 0

      klass_a = Class.new do
        prepend SafeMemoize

        define_method(:find) { |id|
          calls += 1
          id
        }
        memoize :find, shared_cache: "cross"
      end

      klass_b = Class.new do
        prepend SafeMemoize

        define_method(:find) { |id|
          calls += 1
          id
        }
        memoize :find, shared_cache: "cross"
      end

      klass_a.new.find(99)
      klass_b.new.find(99)
      expect(calls).to eq(1)
    end

    it "does not share between different named caches" do
      calls = 0
      body = proc { |id|
        calls += 1
        id
      }

      klass_a = Class.new {
        prepend SafeMemoize

        define_method(:run, &body)
        memoize :run, shared_cache: "alpha"
      }

      klass_b = Class.new {
        prepend SafeMemoize

        define_method(:run, &body)
        memoize :run, shared_cache: "beta"
      }

      klass_a.new.run(1)
      klass_b.new.run(1)
      expect(calls).to eq(2)
    end

    it "supports TTL forwarded to the store" do
      klass = make_class("ttl_cache")
      klass.new
      klass2 = Class.new do
        prepend SafeMemoize

        def fetch(id) = id
        memoize :fetch, shared_cache: "ttl_cache", ttl: 0.01
      end
      obj2 = klass2.new
      obj2.fetch(7)
      sleep(0.02)
      expect(SafeMemoize.shared_cache("ttl_cache").read([:fetch, [7], {}])).to eq(SafeMemoize::Stores::Base::MISS)
    end

    it "supports conditional caching via if:" do
      klass = Class.new do
        prepend SafeMemoize

        def compute(x) = x
        memoize :compute, shared_cache: "cond", if: ->(v) { v > 0 }
      end

      obj = klass.new
      obj.compute(-1)
      obj.compute(1)
      expect(SafeMemoize.shared_cache("cond").keys.length).to eq(1)
    end

    it "composes with namespace: to isolate cross-class entries" do
      calls = 0

      klass_a = Class.new do
        prepend SafeMemoize

        define_method(:lookup) { |id|
          calls += 1
          "a:#{id}"
        }
        memoize :lookup, shared_cache: "shared_ns", namespace: "a"
      end

      klass_b = Class.new do
        prepend SafeMemoize

        define_method(:lookup) { |id|
          calls += 1
          "b:#{id}"
        }
        memoize :lookup, shared_cache: "shared_ns", namespace: "b"
      end

      expect(klass_a.new.lookup(1)).to eq("a:1")
      expect(klass_b.new.lookup(1)).to eq("b:1")
      expect(calls).to eq(2)
      expect(SafeMemoize.shared_cache("shared_ns").keys.length).to eq(2)
    end

    it "works with a pre-registered custom store" do
      custom = SafeMemoize::Stores::Memory.new
      SafeMemoize.register_shared_cache("custom_store", custom)

      klass = Class.new do
        prepend SafeMemoize

        def value = 42
        memoize :value, shared_cache: "custom_store"
      end

      klass.new.value
      expect(custom.keys).not_to be_empty
    end

    it "SafeMemoize.clear_shared_cache evicts all cross-class entries" do
      klass_a = Class.new {
        prepend SafeMemoize

        def x = 1
        memoize :x, shared_cache: "evict_me"
      }

      klass_b = Class.new {
        prepend SafeMemoize

        def x = 2
        memoize :x, shared_cache: "evict_me"
      }

      klass_a.new.x
      klass_b.new.x
      SafeMemoize.clear_shared_cache("evict_me")
      expect(SafeMemoize.shared_cache("evict_me").keys).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  describe "shared_cache: validation" do
    def define_class(&blk)
      klass = Class.new {
        prepend SafeMemoize

        def x = 1
      }

      klass.instance_eval(&blk) if blk
      klass
    end

    it "raises ArgumentError for a non-String value" do
      klass = define_class
      expect { klass.memoize(:x, shared_cache: 123) }.to raise_error(ArgumentError, /String/)
    end

    it "raises ArgumentError for an empty string" do
      klass = define_class
      expect { klass.memoize(:x, shared_cache: "") }.to raise_error(ArgumentError, /empty/)
    end

    it "raises ArgumentError when combined with shared:" do
      klass = define_class
      expect { klass.memoize(:x, shared_cache: "s", shared: true) }
        .to raise_error(ArgumentError, /shared:/)
    end

    it "raises ArgumentError when combined with store:" do
      klass = define_class
      store = SafeMemoize::Stores::Memory.new
      expect { klass.memoize(:x, shared_cache: "s", store: store) }
        .to raise_error(ArgumentError, /store:/)
    end

    it "raises ArgumentError when combined with fiber_local:" do
      klass = define_class
      expect { klass.memoize(:x, shared_cache: "s", fiber_local: true) }
        .to raise_error(ArgumentError, /fiber_local:/)
    end

    it "raises ArgumentError when combined with max_size:" do
      klass = define_class
      expect { klass.memoize(:x, shared_cache: "s", max_size: 10) }
        .to raise_error(ArgumentError, /max_size:/)
    end
  end
end
