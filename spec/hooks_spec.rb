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

    describe "#on_memo_hit" do
      it "calls the hook on a cache hit" do
        instance = test_class.new
        hit_calls = []

        instance.on_memo_hit do |cache_key, record|
          hit_calls << {key: cache_key, record: record}
        end

        instance.expensive_computation(1)
        expect(hit_calls).to be_empty

        instance.expensive_computation(1)
        expect(hit_calls.size).to eq(1)
        expect(hit_calls[0][:key]).to include(:expensive_computation)
        expect(hit_calls[0][:record]).to have_key(:value)
      end

      it "does not call the hook on a cache miss" do
        instance = test_class.new
        hit_calls = []

        instance.on_memo_hit { |_, _| hit_calls << true }

        instance.expensive_computation(1)
        instance.expensive_computation(2)

        expect(hit_calls).to be_empty
      end

      it "calls the hook on every subsequent hit" do
        instance = test_class.new
        hit_calls = []

        instance.on_memo_hit { |_, _| hit_calls << true }

        instance.expensive_computation(1)
        3.times { instance.expensive_computation(1) }

        expect(hit_calls.size).to eq(3)
      end

      it "raises ArgumentError without a block" do
        instance = test_class.new
        expect { instance.on_memo_hit }.to raise_error(ArgumentError, /block required/)
      end

      it "supports multiple on_memo_hit hooks" do
        instance = test_class.new
        calls1 = []
        calls2 = []

        instance.on_memo_hit { |_, _| calls1 << true }
        instance.on_memo_hit { |_, _| calls2 << true }

        instance.expensive_computation(1)
        instance.expensive_computation(1)

        expect(calls1.size).to eq(1)
        expect(calls2.size).to eq(1)
      end

      it "fires for hits via the LRU path" do
        klass = Class.new do
          prepend SafeMemoize

          def expensive_computation(x)
            x * 2
          end

          memoize :expensive_computation, max_size: 10
        end

        instance = klass.new
        hit_calls = []

        instance.on_memo_hit { |_, _| hit_calls << true }

        instance.expensive_computation(1)
        instance.expensive_computation(1)

        expect(hit_calls.size).to eq(1)
      end

      it "does not fire when clear_memo_hooks is called" do
        instance = test_class.new
        hit_calls = []

        instance.on_memo_hit { |_, _| hit_calls << true }
        instance.clear_memo_hooks(:on_hit)

        instance.expensive_computation(1)
        instance.expensive_computation(1)

        expect(hit_calls).to be_empty
      end
    end

    describe "#on_memo_miss" do
      it "calls the hook on a cache miss" do
        instance = test_class.new
        miss_calls = []

        instance.on_memo_miss do |cache_key, record|
          miss_calls << {key: cache_key, record: record}
        end

        instance.expensive_computation(1)
        expect(miss_calls.size).to eq(1)
        expect(miss_calls[0][:key]).to include(:expensive_computation)
        expect(miss_calls[0][:record]).to have_key(:value)
      end

      it "does not call the hook on a cache hit" do
        instance = test_class.new
        miss_calls = []

        instance.on_memo_miss { |_, _| miss_calls << true }

        instance.expensive_computation(1)
        instance.expensive_computation(1)

        expect(miss_calls.size).to eq(1)
      end

      it "calls the hook for each unique argument combination" do
        instance = test_class.new
        miss_calls = []

        instance.on_memo_miss { |_, _| miss_calls << true }

        instance.expensive_computation(1)
        instance.expensive_computation(2)
        instance.expensive_computation(1)

        expect(miss_calls.size).to eq(2)
      end

      it "fires for misses via the LRU path" do
        klass = Class.new do
          prepend SafeMemoize

          def expensive_computation(x)
            x * 2
          end

          memoize :expensive_computation, max_size: 10
        end

        instance = klass.new
        miss_calls = []

        instance.on_memo_miss { |_, _| miss_calls << true }

        instance.expensive_computation(1)
        instance.expensive_computation(1)

        expect(miss_calls.size).to eq(1)
      end

      it "raises ArgumentError without a block" do
        instance = test_class.new
        expect { instance.on_memo_miss }.to raise_error(ArgumentError, /block required/)
      end

      it "supports multiple on_memo_miss hooks" do
        instance = test_class.new
        calls1 = []
        calls2 = []

        instance.on_memo_miss { |_, _| calls1 << true }
        instance.on_memo_miss { |_, _| calls2 << true }

        instance.expensive_computation(1)

        expect(calls1.size).to eq(1)
        expect(calls2.size).to eq(1)
      end

      it "does not fire when clear_memo_hooks is called" do
        instance = test_class.new
        miss_calls = []

        instance.on_memo_miss { |_, _| miss_calls << true }
        instance.clear_memo_hooks(:on_miss)

        instance.expensive_computation(1)

        expect(miss_calls).to be_empty
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

    describe "#on_memo_store" do
      it "fires on a cache miss (fast path)" do
        instance = test_class.new
        stored = []
        instance.on_memo_store { |key, _| stored << key }

        instance.expensive_computation(1)
        expect(stored.size).to eq(1)
        expect(stored[0]).to include(:expensive_computation)
      end

      it "fires on a cache miss (LRU path)" do
        klass = Class.new do
          prepend SafeMemoize

          def value(x) = x * 2
          memoize :value, max_size: 10
        end

        instance = klass.new
        stored = []
        instance.on_memo_store { |_, _| stored << true }

        instance.value(1)
        instance.value(1)
        expect(stored.size).to eq(1)
      end

      it "does not fire on a cache hit" do
        instance = test_class.new
        stored = []
        instance.on_memo_store { |_, _| stored << true }

        instance.expensive_computation(1)
        instance.expensive_computation(1)
        expect(stored.size).to eq(1)
      end

      it "fires when warm_memo populates an entry" do
        instance = test_class.new
        stored = []
        instance.on_memo_store { |key, _| stored << key }

        instance.warm_memo(:expensive_computation, 7) { 99 }
        expect(stored.size).to eq(1)
        expect(stored[0]).to include(:expensive_computation)
      end

      it "fires for each entry loaded via load_memo" do
        instance = test_class.new
        stored = []
        instance.on_memo_store { |_, _| stored << true }

        instance.load_memo({
          [:expensive_computation, [1], {}] => 2,
          [:expensive_computation, [2], {}] => 4
        })
        expect(stored.size).to eq(2)
      end

      it "does not fire when a conditional :if prevents storing" do
        klass = Class.new do
          prepend SafeMemoize

          def value = nil
          memoize :value, if: ->(r) { !r.nil? }
        end

        instance = klass.new
        stored = []
        instance.on_memo_store { |_, _| stored << true }

        instance.value
        expect(stored).to be_empty
      end

      it "fires for shared: true cache misses on the calling instance" do
        klass = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true
        end

        instance = klass.new
        stored = []
        instance.on_memo_store { |_, _| stored << true }

        instance.value
        expect(stored.size).to eq(1)
      end

      it "raises ArgumentError without a block" do
        instance = test_class.new
        expect { instance.on_memo_store }.to raise_error(ArgumentError, /block required/)
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

    describe "hook error isolation" do
      around do |example|
        example.run
      ensure
        SafeMemoize.reset_configuration!
      end

      let(:klass) do
        Class.new do
          prepend SafeMemoize

          def value
            42
          end

          memoize :value
        end
      end

      it "does not propagate hook exceptions to the caller" do
        obj = klass.new
        obj.on_memo_hit { raise "hook exploded" }
        obj.value

        expect { obj.value }.not_to raise_error
      end

      it "emits a warning to stderr by default when a hook raises" do
        obj = klass.new
        obj.on_memo_miss { raise "boom" }

        expect { obj.value }.to output(/\[SafeMemoize\] Hook error in on_miss/).to_stderr
      end

      it "includes the error message in the default warning" do
        obj = klass.new
        obj.on_memo_miss { raise "something went wrong" }

        expect { obj.value }.to output(/something went wrong/).to_stderr
      end

      it "calls on_hook_error handler instead of warning when configured" do
        received = []
        SafeMemoize.configure do |c|
          c.on_hook_error = ->(error, hook_type, _key) { received << [error.message, hook_type] }
        end

        obj = klass.new
        obj.on_memo_miss { raise "handler called" }

        expect { obj.value }.not_to output.to_stderr
        expect(received).to eq([["handler called", :on_miss]])
      end

      it "passes the hook type and cache key to the error handler" do
        payloads = []
        SafeMemoize.configure do |c|
          c.on_hook_error = ->(error, hook_type, cache_key) { payloads << {hook_type: hook_type, cache_key: cache_key} }
        end

        obj = klass.new
        obj.on_memo_hit { raise "oops" }
        obj.value
        obj.value

        expect(payloads.first[:hook_type]).to eq(:on_hit)
        expect(payloads.first[:cache_key]).not_to be_nil
      end

      it "isolates errors per hook — remaining hooks in the same event still fire" do
        obj = klass.new
        SafeMemoize.configure { |c| c.on_hook_error = ->(*) {} }

        fired = []
        obj.on_memo_miss { raise "first hook fails" }
        obj.on_memo_miss { fired << :second }

        obj.value
        expect(fired).to eq([:second])
      end

      it "can be configured to raise on hook errors" do
        SafeMemoize.configure { |c| c.on_hook_error = ->(error, *) { raise error } }

        obj = klass.new
        obj.on_memo_miss { raise "strict mode" }

        expect { obj.value }.to raise_error("strict mode")
      end

      it "restores default warn behaviour after reset_configuration!" do
        SafeMemoize.configure { |c| c.on_hook_error = ->(*) { raise "should not be called" } }
        SafeMemoize.reset_configuration!

        obj = klass.new
        obj.on_memo_miss { raise "warn me" }

        expect { obj.value }.to output(/\[SafeMemoize\]/).to_stderr
      end
    end
  end
end
