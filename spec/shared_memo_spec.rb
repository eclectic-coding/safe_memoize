# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize do
  describe "shared: true" do
    let(:shared_class) do
      Class.new do
        prepend SafeMemoize

        def compute
          rand
        end

        def find(id)
          rand + id
        end

        memoize :compute, shared: true
        memoize :find, shared: true
      end
    end

    it "returns the same value across different instances" do
      a = shared_class.new
      b = shared_class.new
      expect(a.compute).to eq(b.compute)
    end

    it "caches per unique arguments across instances" do
      a = shared_class.new
      b = shared_class.new
      expect(a.find(1)).to eq(b.find(1))
      expect(a.find(1)).not_to eq(a.find(2))
    end

    it "computes only once across all instances" do
      call_count = 0
      klass = Class.new do
        prepend SafeMemoize

        define_method(:value) { call_count += 1 }
        memoize :value, shared: true
      end

      3.times { klass.new.value }
      expect(call_count).to eq(1)
    end

    it "does not affect per-instance memoization on the same class" do
      klass = Class.new do
        prepend SafeMemoize

        def per_instance
          rand
        end

        def shared_val
          rand
        end

        memoize :per_instance
        memoize :shared_val, shared: true
      end

      a = klass.new
      b = klass.new

      expect(a.per_instance).to eq(a.per_instance)
      expect(b.per_instance).to eq(b.per_instance)
      expect(a.per_instance).not_to eq(b.per_instance)
      expect(a.shared_val).to eq(b.shared_val)
    end

    it "passes blocks through without caching" do
      instance = shared_class.new
      results = [instance.compute { 1 }, instance.compute { 1 }]
      expect(results.uniq.size).to be > 1
    end

    describe ".reset_shared_memo" do
      it "clears all cached entries for a method" do
        a = shared_class.new
        first = a.compute
        shared_class.reset_shared_memo(:compute)
        expect(shared_class.new.compute).not_to eq(first)
      end

      it "clears only the matching argument entry" do
        a = shared_class.new
        first_1 = a.find(1)
        first_2 = a.find(2)

        shared_class.reset_shared_memo(:find, 1)

        expect(shared_class.new.find(1)).not_to eq(first_1)
        expect(shared_class.new.find(2)).to eq(first_2)
      end
    end

    describe ".reset_all_shared_memos" do
      it "clears all shared cached entries" do
        a = shared_class.new
        first_compute = a.compute
        first_find = a.find(1)

        shared_class.reset_all_shared_memos

        expect(shared_class.new.compute).not_to eq(first_compute)
        expect(shared_class.new.find(1)).not_to eq(first_find)
      end
    end

    describe ".shared_memoized?" do
      it "returns false before the method is called" do
        klass = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true
        end

        expect(klass.shared_memoized?(:value)).to be false
      end

      it "returns true after the method is called" do
        klass = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true
        end

        klass.new.value
        expect(klass.shared_memoized?(:value)).to be true
      end

      it "checks per argument combination" do
        klass = Class.new do
          prepend SafeMemoize

          def find(id) = rand + id
          memoize :find, shared: true
        end

        klass.new.find(1)
        expect(klass.shared_memoized?(:find, 1)).to be true
        expect(klass.shared_memoized?(:find, 2)).to be false
      end
    end

    describe ".shared_memo_count" do
      it "returns 0 before any calls" do
        klass = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true
        end

        expect(klass.shared_memo_count).to eq(0)
      end

      it "returns the total number of cached entries" do
        klass = Class.new do
          prepend SafeMemoize

          def find(id) = rand + id
          memoize :find, shared: true
        end

        klass.new.find(1)
        klass.new.find(2)
        klass.new.find(1)

        expect(klass.shared_memo_count).to eq(2)
      end

      it "scopes count to a specific method" do
        klass = Class.new do
          prepend SafeMemoize

          def foo = rand
          def bar(x) = rand + x
          memoize :foo, shared: true
          memoize :bar, shared: true
        end

        klass.new.foo
        klass.new.bar(1)
        klass.new.bar(2)

        expect(klass.shared_memo_count(:bar)).to eq(2)
        expect(klass.shared_memo_count(:foo)).to eq(1)
      end
    end

    describe "with ttl:" do
      it "expires shared entries after the ttl" do
        klass = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true, ttl: 0.1
        end

        first = klass.new.value
        expect(klass.new.value).to eq(first)
        sleep(0.15)
        expect(klass.new.value).not_to eq(first)
      end
    end

    describe "with if:" do
      it "does not cache when the condition is not met" do
        klass = Class.new do
          prepend SafeMemoize

          def value = nil
          memoize :value, shared: true, if: ->(r) { !r.nil? }
        end

        3.times { klass.new.value }
        expect(klass.shared_memo_count).to eq(0)
      end
    end

    describe "with max_size:" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          def fetch(n) = n * 10
          memoize :fetch, shared: true, max_size: 2
        end
      end

      after { klass.reset_all_shared_memos }

      it "caches up to max_size entries across instances" do
        klass.new.fetch(1)
        klass.new.fetch(2)
        expect(klass.shared_memo_count(:fetch)).to eq(2)
      end

      it "evicts the least recently used entry when the limit is exceeded" do
        klass.new.fetch(1)
        klass.new.fetch(2)
        klass.new.fetch(3)
        expect(klass.shared_memo_count(:fetch)).to eq(2)
        expect(klass.shared_memoized?(:fetch, 1)).to be false
        expect(klass.shared_memoized?(:fetch, 2)).to be true
        expect(klass.shared_memoized?(:fetch, 3)).to be true
      end

      it "updates LRU order on a cache hit" do
        a = klass.new
        a.fetch(1)
        a.fetch(2)
        a.fetch(1) # promote 1 to MRU
        klass.new.fetch(3) # should evict 2, not 1
        expect(klass.shared_memoized?(:fetch, 1)).to be true
        expect(klass.shared_memoized?(:fetch, 2)).to be false
        expect(klass.shared_memoized?(:fetch, 3)).to be true
      end

      it "fires on_evict on the calling instance when a shared entry is LRU-evicted" do
        evicted = []
        instance = klass.new
        instance.on_memo_evict { |key, _| evicted << key }
        klass.new.fetch(1)
        klass.new.fetch(2)
        instance.fetch(3) # this instance triggers the eviction
        expect(evicted).not_to be_empty
      end
    end

    describe "isolation between classes" do
      it "does not share cache across different classes" do
        klass_a = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true
        end

        klass_b = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true
        end

        expect(klass_a.new.value).not_to eq(klass_b.new.value)
      end
    end

    describe "hooks" do
      it "fires on_memo_hit for shared cache hits" do
        klass = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true
        end

        instance = klass.new
        hits = []
        instance.on_memo_hit { |_, _| hits << true }

        instance.value
        instance.value

        expect(hits.size).to eq(1)
      end

      it "fires on_memo_miss for shared cache misses" do
        klass = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true
        end

        instance = klass.new
        misses = []
        instance.on_memo_miss { |_, _| misses << true }

        instance.value
        instance.value

        expect(misses.size).to eq(1)
      end
    end
  end
end
