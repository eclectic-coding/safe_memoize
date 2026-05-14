# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize do
  describe "cache expiration and invalidation hooks" do
    let(:test_class_with_ttl) do
      Class.new do
        prepend SafeMemoize

        def self.name
          "TestClass"
        end

        def expensive_computation(x)
          rand
        end

        memoize :expensive_computation, ttl: 0.1
      end
    end

    let(:test_class) do
      Class.new do
        prepend SafeMemoize

        def self.name
          "TestClass"
        end

        def expensive_computation(x)
          rand
        end

        memoize :expensive_computation
      end
    end

    describe "#on_memo_expire" do
      it "calls the hook when an entry expires" do
        instance = test_class_with_ttl.new
        expired_calls = []

        instance.on_memo_expire do |cache_key, record|
          expired_calls << {key: cache_key, record: record}
        end

        # Cache with 0.1 second TTL
        instance.expensive_computation(1)
        expect(expired_calls).to be_empty

        # Sleep to let it expire
        sleep(0.15)

        # Call memo_count to trigger pruning
        instance.memo_count

        expect(expired_calls).not_to be_empty
        expect(expired_calls[0][:key]).to include(:expensive_computation)
      end

      it "does not call the hook if entry is still valid" do
        instance = test_class.new
        expired_calls = []

        instance.on_memo_expire { |_, _| expired_calls << true }

        # Cache with no TTL
        instance.expensive_computation(1)
        instance.memo_count

        expect(expired_calls).to be_empty
      end

      it "raises ArgumentError without a block" do
        instance = test_class.new
        expect { instance.on_memo_expire }.to raise_error(ArgumentError, /block required/)
      end

      it "supports multiple on_memo_expire hooks" do
        instance = test_class_with_ttl.new
        calls1 = []
        calls2 = []

        instance.on_memo_expire { |key, _| calls1 << key }
        instance.on_memo_expire { |key, _| calls2 << key }

        instance.expensive_computation(1)
        sleep(0.15)
        instance.memo_count

        expect(calls1.size).to eq(1)
        expect(calls2.size).to eq(1)
      end
    end

    describe "#on_memo_evict" do
      it "calls the hook when reset_memo is called" do
        instance = test_class.new
        evicted_calls = []

        instance.on_memo_evict do |cache_key, record|
          evicted_calls << {key: cache_key, record: record}
        end

        instance.expensive_computation(1)
        instance.expensive_computation(2)

        expect(evicted_calls).to be_empty

        instance.reset_memo(:expensive_computation, 1)

        expect(evicted_calls.length).to eq(1)
        expect(evicted_calls[0][:key]).to include(:expensive_computation)
      end

      it "calls the hook for all entries when reset_all_memos is called" do
        instance = test_class.new
        evicted_calls = []

        instance.on_memo_evict { |_, _| evicted_calls << true }

        instance.expensive_computation(1)
        instance.expensive_computation(2)

        expect(evicted_calls).to be_empty

        instance.reset_all_memos

        expect(evicted_calls.size).to eq(2)
      end

      it "raises ArgumentError without a block" do
        instance = test_class.new
        expect { instance.on_memo_evict }.to raise_error(ArgumentError, /block required/)
      end

      it "supports multiple on_memo_evict hooks" do
        instance = test_class.new
        calls1 = []
        calls2 = []

        instance.on_memo_evict { |_, _| calls1 << true }
        instance.on_memo_evict { |_, _| calls2 << true }

        instance.expensive_computation(1)
        instance.reset_memo(:expensive_computation, 1)

        expect(calls1.size).to eq(1)
        expect(calls2.size).to eq(1)
      end
    end

    describe "#clear_memo_hooks" do
      it "clears all hooks of a specific type" do
        instance = test_class.new
        evicted_calls = []

        instance.on_memo_evict { |_, _| evicted_calls << true }
        instance.clear_memo_hooks(:on_evict)

        instance.expensive_computation(1)
        instance.reset_memo(:expensive_computation, 1)

        expect(evicted_calls).to be_empty
      end

      it "clears all hooks when no type is specified" do
        instance = test_class_with_ttl.new
        expire_calls = []
        evict_calls = []

        instance.on_memo_expire { |_, _| expire_calls << true }
        instance.on_memo_evict { |_, _| evict_calls << true }

        instance.clear_memo_hooks

        instance.expensive_computation(1)
        sleep(0.15)
        instance.memo_count
        instance.reset_memo(:expensive_computation, 1)

        expect(expire_calls).to be_empty
        expect(evict_calls).to be_empty
      end
    end

    describe "hook payload" do
      it "provides cache_key and record to the hook" do
        instance = test_class.new
        hook_data = []

        instance.on_memo_evict do |cache_key, record|
          hook_data << {cache_key: cache_key, record: record}
        end

        computed_value = instance.expensive_computation(42)
        instance.reset_memo(:expensive_computation, 42)

        expect(hook_data.size).to eq(1)
        expect(hook_data[0][:cache_key]).to be_a(Array)
        expect(hook_data[0][:cache_key][0]).to eq(:expensive_computation)
        expect(hook_data[0][:cache_key][1]).to eq([42])
        expect(hook_data[0][:record]).to be_a(Hash)
        expect(hook_data[0][:record]).to have_key(:value)
        expect(hook_data[0][:record][:value]).to eq(computed_value)
      end
    end

    describe "hooks isolation between instances" do
      it "hooks registered on one instance do not affect others" do
        instance1 = test_class.new
        instance2 = test_class.new
        calls1 = []
        calls2 = []

        instance1.on_memo_evict { |_, _| calls1 << true }
        instance2.on_memo_evict { |_, _| calls2 << true }

        instance1.expensive_computation(1)
        instance2.expensive_computation(2)

        instance1.reset_all_memos

        expect(calls1.size).to eq(1)
        expect(calls2).to be_empty
      end
    end
  end
end
