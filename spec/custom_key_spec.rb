# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize do
  describe "manual cache key generation" do
    let(:test_class) do
      Class.new do
        prepend SafeMemoize

        def self.name
          "TestClass"
        end

        def compute_value(user_id, options)
          "result_#{user_id}_#{options}"
        end

        memoize :compute_value
      end
    end

    describe "#memoize_with_custom_key" do
      it "uses a custom key generator for caching" do
        call_tracker = []

        test_class_tracked = Class.new do
          prepend SafeMemoize

          def self.name
            "TestClass"
          end

          def initialize(tracker)
            @tracker = tracker
          end

          def compute_value(user_id, options)
            @tracker << user_id
            "result_#{user_id}_#{options}"
          end

          memoize :compute_value
        end

        instance = test_class_tracked.new(call_tracker)

        # Register custom key: use only user_id, ignore options
        instance.memoize_with_custom_key(:compute_value) do |user_id, options|
          user_id
        end

        instance.compute_value(1, {a: 1})
        instance.compute_value(1, {a: 2})  # Different options, same user_id

        expect(call_tracker.length).to eq(1)  # Should only be called once due to custom key
      end

      it "allows complex custom keys" do
        instance = test_class.new

        # Custom key based on user_id and a specific option
        instance.memoize_with_custom_key(:compute_value) do |user_id, options|
          {user: user_id, category: options[:category]}
        end

        result1 = instance.compute_value(1, {category: "A", other: "X"})
        result2 = instance.compute_value(1, {category: "A", other: "Y"})
        result3 = instance.compute_value(1, {category: "B", other: "X"})

        # result1 and result2 should use the same cache (same user and category)
        expect(result1).to eq(result2)

        # result3 should be different
        expect(result3).not_to eq(result1)
      end

      it "supports string-based custom keys" do
        instance = test_class.new

        instance.memoize_with_custom_key(:compute_value) do |user_id, options|
          "user_#{user_id}"
        end

        result1 = instance.compute_value(1, {})
        result2 = instance.compute_value(1, {different: "value"})

        expect(result1).to eq(result2)
      end

      it "supports custom keys with multiple unique values" do
        call_tracker = []

        test_class_tracked = Class.new do
          prepend SafeMemoize

          def self.name
            "TestClass"
          end

          def initialize(tracker)
            @tracker = tracker
          end

          def compute_value(user_id, options)
            @tracker << user_id
            "result_#{user_id}"
          end

          memoize :compute_value
        end

        instance = test_class_tracked.new(call_tracker)

        instance.memoize_with_custom_key(:compute_value) do |user_id, _options|
          user_id
        end

        instance.compute_value(1, {})
        instance.compute_value(1, {})  # Cache hit
        instance.compute_value(2, {})  # Cache miss (different user_id)

        expect(call_tracker.length).to eq(2)
      end

      it "raises ArgumentError without a block" do
        instance = test_class.new
        expect { instance.memoize_with_custom_key(:compute_value) }.to raise_error(ArgumentError, /block required/)
      end

      it "custom keys work with cache_stats" do
        instance = test_class.new

        instance.memoize_with_custom_key(:compute_value) do |user_id, _|
          user_id
        end

        instance.compute_value(1, {})
        instance.compute_value(1, {})

        stats = instance.cache_stats

        expect(stats[:total_hits]).to eq(1)
        expect(stats[:total_misses]).to eq(1)
      end
    end

    describe "#clear_custom_keys" do
      it "removes a specific method's custom key generator" do
        instance = test_class.new

        instance.memoize_with_custom_key(:compute_value) do |user_id, _|
          user_id
        end

        result1 = instance.compute_value(1, {a: 1})
        result2 = instance.compute_value(1, {a: 2})

        expect(result1).to eq(result2)

        # Clear the custom key
        instance.clear_custom_keys(:compute_value)
        instance.cache_metrics_reset

        # Now with default key generation, these should be different cache keys
        instance.compute_value(1, {a: 1})
        instance.compute_value(1, {a: 2})

        stats = instance.cache_stats

        # After clearing, we should have more cache misses
        expect(stats[:total_misses]).to be >= 1
      end

      it "removes all custom key generators when no method specified" do
        instance = test_class.new

        instance.memoize_with_custom_key(:compute_value) do |user_id, _|
          user_id
        end

        instance.clear_custom_keys

        stats = instance.cache_stats
        expect(stats[:total_hits]).to eq(0)
      end
    end

    describe "custom keys with hooks" do
      it "custom keys work with on_memo_evict hooks" do
        instance = test_class.new
        evicted_keys = []

        instance.memoize_with_custom_key(:compute_value) do |user_id, _|
          user_id
        end

        instance.on_memo_evict do |key, _|
          evicted_keys << key
        end

        instance.compute_value(1, {})
        instance.reset_memo(:compute_value)

        expect(evicted_keys).not_to be_empty
      end
    end

    describe "custom keys isolation between instances" do
      it "custom key generators are isolated per instance" do
        instance1 = test_class.new
        instance2 = test_class.new

        instance1.memoize_with_custom_key(:compute_value) do |user_id, _|
          user_id
        end

        # instance2 should not have the custom key generator
        result1a = instance1.compute_value(1, {a: 1})
        result1b = instance1.compute_value(1, {a: 2})

        result2a = instance2.compute_value(1, {a: 1})
        result2b = instance2.compute_value(1, {a: 2})

        # instance1 results should be the same (same cache key)
        expect(result1a).to eq(result1b)

        # instance2 results should be different (different default cache keys)
        expect(result2a).not_to eq(result2b)
      end
    end

    describe "custom keys with TTL" do
      let(:test_class_with_ttl) do
        Class.new do
          prepend SafeMemoize

          def self.name
            "TestClass"
          end

          def compute_value(user_id, options)
            "result_#{user_id}_#{options}"
          end

          memoize :compute_value, ttl: 0.1
        end
      end

      it "custom keys work with TTL expiration" do
        instance = test_class_with_ttl.new

        instance.memoize_with_custom_key(:compute_value) do |user_id, _|
          user_id
        end

        instance.compute_value(1, {})

        sleep(0.15)

        stats = instance.cache_stats
        instance.memo_count

        expect(stats[:total_misses]).to eq(1)
      end
    end

    describe "custom keys with memo_keys and memo_values" do
      it "memo_keys surfaces the custom_key field instead of args/kwargs" do
        instance = test_class.new

        instance.memoize_with_custom_key(:compute_value) do |user_id, _|
          user_id
        end

        instance.compute_value(42, {})

        keys = instance.memo_keys(:compute_value)
        expect(keys.length).to eq(1)
        expect(keys.first).to include(custom_key: 42)
        expect(keys.first).not_to have_key(:args)
      end

      it "memo_values surfaces the custom_key field and the cached value" do
        instance = test_class.new

        instance.memoize_with_custom_key(:compute_value) do |user_id, _|
          user_id
        end

        instance.compute_value(7, {opt: true})

        values = instance.memo_values(:compute_value)
        expect(values.length).to eq(1)
        expect(values.first).to include(custom_key: 7, value: "result_7_{opt: true}")
      end
    end

    describe "custom keys with default arguments" do
      it "supports methods with default arguments" do
        test_class_with_defaults = Class.new do
          prepend SafeMemoize

          def self.name
            "TestClass"
          end

          def compute_value(user_id, options = {})
            "result_#{user_id}"
          end

          memoize :compute_value
        end

        instance = test_class_with_defaults.new

        instance.memoize_with_custom_key(:compute_value) do |user_id, options = {}|
          user_id
        end

        result1 = instance.compute_value(1)
        result2 = instance.compute_value(1, {})

        expect(result1).to eq(result2)
      end
    end
  end
end
