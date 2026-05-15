# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize do
  describe "LRU cache size limit" do
    def make_class(max_size:, ttl: nil)
      Class.new do
        prepend SafeMemoize

        attr_reader :call_log

        def initialize
          @call_log = []
        end

        define_method(:fetch) do |id|
          @call_log << id
          "value-#{id}"
        end

        memoize :fetch, max_size: max_size, ttl: ttl
      end
    end

    describe "memoize max_size: option" do
      it "raises ArgumentError for non-positive max_size" do
        expect {
          Class.new do
            prepend SafeMemoize

            def value = 1
            memoize :value, max_size: 0
          end
        }.to raise_error(ArgumentError, /max_size must be positive/)
      end

      it "raises ArgumentError for non-integer max_size" do
        expect {
          Class.new do
            prepend SafeMemoize

            def value = 1
            memoize :value, max_size: "big"
          end
        }.to raise_error(ArgumentError, /max_size must be a positive integer/)
      end

      it "raises ArgumentError for float max_size" do
        expect {
          Class.new do
            prepend SafeMemoize

            def value = 1
            memoize :value, max_size: 1.5
          end
        }.to raise_error(ArgumentError, /max_size must be a positive integer/)
      end
    end

    describe "basic eviction" do
      it "does not evict entries until the limit is reached" do
        klass = make_class(max_size: 3)
        obj = klass.new

        obj.fetch(1)
        obj.fetch(2)
        obj.fetch(3)

        expect(obj.call_log).to eq([1, 2, 3])
        expect(obj.memo_count(:fetch)).to eq(3)
      end

      it "evicts the least recently used entry when the limit is exceeded" do
        klass = make_class(max_size: 2)
        obj = klass.new

        obj.fetch(1)
        obj.fetch(2)
        # Cache: [1, 2] — 1 is LRU

        obj.fetch(3)
        # Cache: [2, 3] — 1 was evicted

        expect(obj.memo_count(:fetch)).to eq(2)

        # 1 was evicted, so re-fetching it triggers recomputation
        obj.fetch(1)
        expect(obj.call_log).to eq([1, 2, 3, 1])
      end

      it "keeps the most recently used entry when evicting" do
        klass = make_class(max_size: 2)
        obj = klass.new

        obj.fetch(1)
        obj.fetch(2)
        # LRU order: [1(LRU), 2(MRU)]

        # Access 1 — promotes it: LRU order becomes [2(LRU), 1(MRU)]
        obj.fetch(1)
        expect(obj.call_log).to eq([1, 2])  # hit, no recomputation

        # Adding 3 evicts 2 (LRU), not 1 (recently used). Cache: {1, 3}
        obj.fetch(3)
        expect(obj.memo_count(:fetch)).to eq(2)

        # 2 was evicted; re-fetching it evicts 1 (now LRU). Cache: {3, 2}
        obj.fetch(2)
        expect(obj.call_log).to eq([1, 2, 3, 2])

        # 3 is still cached (was MRU when 2 was re-added)
        obj.fetch(3)
        expect(obj.call_log).to eq([1, 2, 3, 2])
      end

      it "handles max_size: 1 correctly" do
        klass = make_class(max_size: 1)
        obj = klass.new

        obj.fetch(1)
        obj.fetch(1)  # hit
        expect(obj.call_log).to eq([1])

        obj.fetch(2)  # evicts 1
        expect(obj.call_log).to eq([1, 2])
        expect(obj.memo_count(:fetch)).to eq(1)

        obj.fetch(1)  # 1 was evicted
        expect(obj.call_log).to eq([1, 2, 1])
      end
    end

    describe "LRU order maintenance" do
      it "updates access order on cache hits" do
        klass = make_class(max_size: 3)
        obj = klass.new

        obj.fetch(1)
        obj.fetch(2)
        obj.fetch(3)
        # LRU order: [1(LRU), 2, 3(MRU)]

        # Hit on 1 — promotes it: LRU order becomes [2(LRU), 3, 1(MRU)]
        obj.fetch(1)
        expect(obj.call_log).to eq([1, 2, 3])  # 1 was a hit

        # Adding 4 evicts 2 (LRU). Cache: {1, 3, 4}
        obj.fetch(4)
        expect(obj.call_log).to eq([1, 2, 3, 4])  # 4 is a miss

        # 2 was evicted — recomputation evicts 3 (now LRU). Cache: {1, 4, 2}
        obj.fetch(2)
        expect(obj.call_log).to eq([1, 2, 3, 4, 2])

        # 1 is still cached
        obj.fetch(1)
        expect(obj.call_log).to eq([1, 2, 3, 4, 2])
      end

      it "handles repeated access to the same key without growing the cache" do
        klass = make_class(max_size: 2)
        obj = klass.new

        10.times { obj.fetch(1) }
        expect(obj.memo_count(:fetch)).to eq(1)
        expect(obj.call_log).to eq([1])
      end
    end

    describe "on_evict hook integration" do
      it "fires the on_evict hook when an entry is LRU-evicted" do
        klass = make_class(max_size: 2)
        obj = klass.new
        evicted = []

        obj.on_memo_evict { |key, _record| evicted << key }

        obj.fetch(1)
        obj.fetch(2)
        expect(evicted).to be_empty

        obj.fetch(3)  # evicts 1
        expect(evicted.size).to eq(1)
        expect(evicted.first).to include(:fetch)
      end

      it "does not fire on_evict for cache hits" do
        klass = make_class(max_size: 2)
        obj = klass.new
        evicted = []

        obj.on_memo_evict { |_, _| evicted << true }

        obj.fetch(1)
        5.times { obj.fetch(1) }  # all hits
        expect(evicted).to be_empty
      end
    end

    describe "interaction with reset_memo" do
      it "stays within max_size after manual reset_memo" do
        klass = make_class(max_size: 2)
        obj = klass.new

        obj.fetch(1)
        obj.fetch(2)

        obj.reset_memo(:fetch, 1)
        expect(obj.memo_count(:fetch)).to eq(1)

        # Now there's room — adding 3 should not evict 2
        obj.fetch(3)
        expect(obj.memo_count(:fetch)).to eq(2)

        obj.fetch(2)  # 2 still cached
        expect(obj.call_log).to eq([1, 2, 3])
      end

      it "stays within max_size after reset_all_memos" do
        klass = make_class(max_size: 2)
        obj = klass.new

        obj.fetch(1)
        obj.fetch(2)
        obj.reset_all_memos

        obj.fetch(1)
        obj.fetch(2)
        expect(obj.memo_count(:fetch)).to eq(2)

        obj.fetch(3)  # evicts 1
        obj.fetch(1)  # recomputed
        expect(obj.call_log).to eq([1, 2, 1, 2, 3, 1])
      end
    end

    describe "isolation between instances" do
      it "each instance has its own LRU state" do
        klass = make_class(max_size: 2)
        a = klass.new
        b = klass.new

        a.fetch(1)
        a.fetch(2)
        a.fetch(3)  # evicts 1 from a's cache

        b.fetch(1)  # b's cache is independent
        expect(b.call_log).to eq([1])
        expect(b.memo_count(:fetch)).to eq(1)

        expect(a.call_log).to eq([1, 2, 3])
      end
    end

    describe "combining max_size with TTL" do
      it "evicts via LRU before TTL expires, then recomputes after TTL expires" do
        klass = make_class(max_size: 2, ttl: 0.1)
        obj = klass.new

        obj.fetch(1)
        obj.fetch(2)
        expect(obj.memo_count(:fetch)).to eq(2)

        # LRU eviction still works within the TTL window
        obj.fetch(3)  # evicts 1 (LRU)
        expect(obj.call_log).to eq([1, 2, 3])
        expect(obj.memo_count(:fetch)).to eq(2)

        sleep(0.12)

        # After TTL, remaining entries expire; re-fetching recomputes
        obj.fetch(2)
        obj.fetch(3)
        expect(obj.call_log).to eq([1, 2, 3, 2, 3])
      end
    end

    describe "thread safety" do
      it "does not exceed max_size under concurrent access" do
        klass = Class.new do
          prepend SafeMemoize

          def compute(n)
            sleep(0.001)
            n * 2
          end

          memoize :compute, max_size: 5
        end

        obj = klass.new
        ids = (1..20).to_a

        threads = ids.map do |id|
          Thread.new { 3.times { obj.compute(id) } }
        end
        threads.each(&:join)

        expect(obj.memo_count(:compute)).to be <= 5
      end
    end

    describe "memo inspection with max_size" do
      it "memo_count reflects evictions" do
        klass = make_class(max_size: 2)
        obj = klass.new

        obj.fetch(1)
        obj.fetch(2)
        expect(obj.memo_count(:fetch)).to eq(2)

        obj.fetch(3)
        expect(obj.memo_count(:fetch)).to eq(2)
      end

      it "memoized? returns false for an evicted entry" do
        klass = make_class(max_size: 1)
        obj = klass.new

        obj.fetch(1)
        expect(obj.memoized?(:fetch, 1)).to be(true)

        obj.fetch(2)  # evicts 1
        expect(obj.memoized?(:fetch, 1)).to be(false)
        expect(obj.memoized?(:fetch, 2)).to be(true)
      end
    end
  end
end
