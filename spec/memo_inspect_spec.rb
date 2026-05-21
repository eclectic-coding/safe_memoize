# frozen_string_literal: true

RSpec.describe "memo_inspect" do
  let(:klass) do
    Class.new do
      prepend SafeMemoize

      attr_reader :call_count

      def initialize
        @call_count = 0
      end

      def compute(x)
        @call_count += 1
        x * 2
      end

      memoize :compute
    end
  end

  describe "when the entry is not cached" do
    it "returns nil" do
      obj = klass.new
      expect(obj.memo_inspect(:compute, 5)).to be_nil
    end
  end

  describe "cached: field" do
    it "is true for a live cached entry" do
      obj = klass.new
      obj.compute(5)
      expect(obj.memo_inspect(:compute, 5)[:cached]).to be true
    end
  end

  describe "value: field" do
    it "returns the cached value" do
      obj = klass.new
      obj.compute(5)
      expect(obj.memo_inspect(:compute, 5)[:value]).to eq(10)
    end

    it "returns a cached nil value" do
      nil_klass = Class.new do
        prepend SafeMemoize

        def fetch
          nil
        end

        memoize :fetch
      end

      obj = nil_klass.new
      obj.fetch
      result = obj.memo_inspect(:fetch)
      expect(result).not_to be_nil
      expect(result[:cached]).to be true
      expect(result[:value]).to be_nil
    end

    it "returns a cached false value" do
      false_klass = Class.new do
        prepend SafeMemoize

        def flag
          false
        end

        memoize :flag
      end

      obj = false_klass.new
      obj.flag
      result = obj.memo_inspect(:flag)
      expect(result).not_to be_nil
      expect(result[:value]).to be false
    end
  end

  describe "hits: and misses: fields" do
    it "reports 0 hits and 1 miss after the first call" do
      obj = klass.new
      obj.compute(5)
      result = obj.memo_inspect(:compute, 5)
      expect(result[:hits]).to eq(0)
      expect(result[:misses]).to eq(1)
    end

    it "increments hits on subsequent calls" do
      obj = klass.new
      obj.compute(5)
      obj.compute(5)
      obj.compute(5)
      result = obj.memo_inspect(:compute, 5)
      expect(result[:hits]).to eq(2)
      expect(result[:misses]).to eq(1)
    end

    it "scopes metrics to the specific argument combination" do
      obj = klass.new
      obj.compute(1)
      obj.compute(2)
      obj.compute(1)

      expect(obj.memo_inspect(:compute, 1)[:hits]).to eq(1)
      expect(obj.memo_inspect(:compute, 2)[:hits]).to eq(0)
    end
  end

  describe "ttl_remaining: field" do
    it "is nil when no TTL is set" do
      obj = klass.new
      obj.compute(5)
      expect(obj.memo_inspect(:compute, 5)[:ttl_remaining]).to be_nil
    end

    it "returns a positive float when the entry has TTL remaining" do
      ttl_klass = Class.new do
        prepend SafeMemoize

        def val
          42
        end

        memoize :val, ttl: 10
      end

      obj = ttl_klass.new
      obj.val
      result = obj.memo_inspect(:val)
      expect(result[:ttl_remaining]).to be_a(Float)
      expect(result[:ttl_remaining]).to be > 0
      expect(result[:ttl_remaining]).to be <= 10
    end

    it "returns 0 for an expired entry (should not normally be reached via memo_inspect since expired records are rejected)" do
      # memo_inspect returns nil for expired entries because memo_cache_record
      # checks liveness — this just documents that boundary.
      ttl_klass = Class.new do
        prepend SafeMemoize

        def val
          1
        end

        memoize :val, ttl: 0.01
      end

      obj = ttl_klass.new
      obj.val
      sleep(0.02)
      expect(obj.memo_inspect(:val)).to be_nil
    end
  end

  describe "age: field" do
    it "returns a non-negative float" do
      obj = klass.new
      obj.compute(5)
      age = obj.memo_inspect(:compute, 5)[:age]
      expect(age).to be_a(Float)
      expect(age).to be >= 0
    end

    it "grows over time" do
      obj = klass.new
      obj.compute(5)
      age_before = obj.memo_inspect(:compute, 5)[:age]
      sleep(0.01)
      age_after = obj.memo_inspect(:compute, 5)[:age]
      expect(age_after).to be > age_before
    end
  end

  describe "custom_key: field" do
    it "is nil when using the default key" do
      obj = klass.new
      obj.compute(5)
      expect(obj.memo_inspect(:compute, 5)[:custom_key]).to be_nil
    end

    it "returns the custom key value when memoize_with_custom_key is used" do
      obj = klass.new
      obj.memoize_with_custom_key(:compute) { |x| "bucket_#{x % 2}" }
      obj.compute(4)
      expect(obj.memo_inspect(:compute, 4)[:custom_key]).to eq("bucket_0")
    end

    it "returns the custom key value when key: is set at the class level" do
      keyed_klass = Class.new do
        prepend SafeMemoize

        def lookup(x)
          x
        end

        memoize :lookup, key: ->(x) { x.even? ? :even : :odd }
      end

      obj = keyed_klass.new
      obj.lookup(4)
      expect(obj.memo_inspect(:lookup, 4)[:custom_key]).to eq(:even)
    end
  end

  describe "lru_position: field" do
    it "is nil when no max_size is set" do
      obj = klass.new
      obj.compute(5)
      expect(obj.memo_inspect(:compute, 5)[:lru_position]).to be_nil
    end

    it "returns 1 for the most recently used entry" do
      lru_klass = Class.new do
        prepend SafeMemoize

        def val(x)
          x
        end

        memoize :val, max_size: 3
      end

      obj = lru_klass.new
      obj.val(1)
      obj.val(2)
      obj.val(3)

      expect(obj.memo_inspect(:val, 3)[:lru_position]).to eq(1)
    end

    it "returns a higher position for a less recently used entry" do
      lru_klass = Class.new do
        prepend SafeMemoize

        def val(x)
          x
        end

        memoize :val, max_size: 3
      end

      obj = lru_klass.new
      obj.val(1)
      obj.val(2)
      obj.val(3)

      expect(obj.memo_inspect(:val, 1)[:lru_position]).to eq(3)
      expect(obj.memo_inspect(:val, 2)[:lru_position]).to eq(2)
      expect(obj.memo_inspect(:val, 3)[:lru_position]).to eq(1)
    end

    it "updates after a cache hit promotes an entry" do
      lru_klass = Class.new do
        prepend SafeMemoize

        def val(x)
          x
        end

        memoize :val, max_size: 3
      end

      obj = lru_klass.new
      obj.val(1)
      obj.val(2)
      obj.val(3)

      obj.val(1)

      expect(obj.memo_inspect(:val, 1)[:lru_position]).to eq(1)
      expect(obj.memo_inspect(:val, 3)[:lru_position]).to eq(2)
    end
  end

  describe "returns all fields in one call" do
    it "returns a hash with the expected keys" do
      obj = klass.new
      obj.compute(7)
      result = obj.memo_inspect(:compute, 7)
      expect(result.keys).to contain_exactly(
        :cached, :value, :hits, :misses, :ttl_remaining, :age, :custom_key, :lru_position
      )
    end
  end
end
