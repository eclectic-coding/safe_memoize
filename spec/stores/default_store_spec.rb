# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SafeMemoize.configure default_store" do
  # Always reset global configuration between examples so nothing leaks.
  after { SafeMemoize.reset_configuration! }

  def new_store = SafeMemoize::Stores::Memory.new

  def build_class(**memoize_opts)
    Class.new do
      prepend SafeMemoize

      def work(x) = x * 2
      memoize :work, **memoize_opts
    end
  end

  # ---------------------------------------------------------------------------
  # Basic application
  # ---------------------------------------------------------------------------

  describe "when default_store is set" do
    it "routes memoize calls through the default store" do
      store = new_store
      SafeMemoize.configure { |c| c.default_store = store }

      obj = build_class.new
      obj.work(5)
      expect(store.read([:work, [5], {}])).to eq 10
    end

    it "computes only once across instances sharing the store" do
      store = new_store
      SafeMemoize.configure { |c| c.default_store = store }

      count = 0
      klass = Class.new do
        prepend SafeMemoize

        define_method(:work) {
          count += 1
          count
        }
        memoize :work
      end

      klass.new.work
      klass.new.work
      expect(count).to eq 1
    end

    it "caches nil correctly through the default store" do
      store = new_store
      SafeMemoize.configure { |c| c.default_store = store }

      klass = Class.new do
        prepend SafeMemoize

        def nullable = nil
        memoize :nullable
      end
      obj = klass.new
      expect(obj.nullable).to be_nil
      expect(obj.nullable).to be_nil
      expect(store.exist?([:nullable, [], {}])).to be true
    end

    it "caches false correctly through the default store" do
      store = new_store
      SafeMemoize.configure { |c| c.default_store = store }

      klass = Class.new do
        prepend SafeMemoize

        def falsy = false
        memoize :falsy
      end
      obj = klass.new
      expect(obj.falsy).to be false
      expect(store.exist?([:falsy, [], {}])).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Per-method store: takes precedence
  # ---------------------------------------------------------------------------

  describe "precedence: per-method store: overrides default_store" do
    it "uses the per-method store, not the global default" do
      global_store = new_store
      method_store = new_store
      SafeMemoize.configure { |c| c.default_store = global_store }

      s = method_store
      klass = Class.new do
        prepend SafeMemoize

        def work(x) = x + 1
        memoize :work, store: s
      end

      klass.new.work(3)
      expect(method_store.read([:work, [3], {}])).to eq 4
      expect(global_store.read([:work, [3], {}])).to be SafeMemoize::Stores::Base::MISS
    end
  end

  # ---------------------------------------------------------------------------
  # Incompatible options — silently fall back to per-instance hash
  # ---------------------------------------------------------------------------

  describe "silent fallback when default_store is incompatible" do
    it "bypasses the default store when max_size: is set" do
      store = new_store
      SafeMemoize.configure { |c| c.default_store = store }

      obj = build_class(max_size: 5).new
      obj.work(7)
      expect(store.read([:work, [7], {}])).to be SafeMemoize::Stores::Base::MISS
      expect(obj.memoized?(:work, 7)).to be true
    end

    it "bypasses the default store when shared: is set" do
      store = new_store
      SafeMemoize.configure { |c| c.default_store = store }

      obj = build_class(shared: true).new
      obj.work(9)
      expect(store.read([:work, [9], {}])).to be SafeMemoize::Stores::Base::MISS
    end
  end

  # ---------------------------------------------------------------------------
  # Interaction with other memoize options
  # ---------------------------------------------------------------------------

  describe "interaction with other memoize options" do
    it "forwards ttl: to the default store as expires_in" do
      store = new_store
      SafeMemoize.configure { |c| c.default_store = store }

      klass = Class.new do
        prepend SafeMemoize

        def work(x) = x
        memoize :work, ttl: 0.01
      end

      obj = klass.new
      obj.work(1)
      sleep 0.02
      expect(store.read([:work, [1], {}])).to be SafeMemoize::Stores::Base::MISS
    end

    it "respects if: conditional through the default store" do
      store = new_store
      SafeMemoize.configure { |c| c.default_store = store }

      klass = Class.new do
        prepend SafeMemoize

        def work(x) = x
        memoize :work, if: ->(v) { v > 10 }
      end

      klass.new.work(5)
      expect(store.exist?([:work, [5], {}])).to be false
      klass.new.work(20)
      expect(store.exist?([:work, [20], {}])).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  describe "validation" do
    it "raises ArgumentError at memoize time when default_store is not a Stores::Base instance" do
      SafeMemoize.configure { |c| c.default_store = "not a store" }

      expect do
        Class.new do
          prepend SafeMemoize

          def work = 1
          memoize :work
        end
      end.to raise_error(ArgumentError, /default_store.*Stores::Base/)
    end
  end

  # ---------------------------------------------------------------------------
  # reset_configuration! clears the default store
  # ---------------------------------------------------------------------------

  describe "reset_configuration!" do
    it "clears the default store so subsequent memoize calls use per-instance hash" do
      store = new_store
      SafeMemoize.configure { |c| c.default_store = store }
      SafeMemoize.reset_configuration!

      obj = build_class.new
      obj.work(2)
      expect(store.read([:work, [2], {}])).to be SafeMemoize::Stores::Base::MISS
      expect(obj.memoized?(:work, 2)).to be true
    end
  end
end
