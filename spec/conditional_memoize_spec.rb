# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize do
  describe "conditional memoization" do
    describe "memoize :if option" do
      it "raises ArgumentError when both :if and :unless are given" do
        expect {
          Class.new do
            prepend SafeMemoize

            def value = 1
            memoize :value, if: ->(_) { true }, unless: ->(_) { false }
          end
        }.to raise_error(ArgumentError, /cannot specify both :if and :unless/)
      end

      it "raises ArgumentError when :if is not callable" do
        expect {
          Class.new do
            prepend SafeMemoize

            def value = 1
            memoize :value, if: true
          end
        }.to raise_error(ArgumentError, /:if must be callable/)
      end

      it "raises ArgumentError when :unless is not callable" do
        expect {
          Class.new do
            prepend SafeMemoize

            def value = 1
            memoize :value, unless: "truthy"
          end
        }.to raise_error(ArgumentError, /:unless must be callable/)
      end
    end

    describe "memoize with :if" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def fetch(value)
            @call_count += 1
            value
          end

          memoize :fetch, if: ->(result) { !result.nil? }
        end
      end

      it "caches the result when the condition is met" do
        obj = klass.new
        expect(obj.fetch("data")).to eq("data")
        expect(obj.fetch("data")).to eq("data")
        expect(obj.call_count).to eq(1)
      end

      it "does not cache when the condition is not met" do
        obj = klass.new
        expect(obj.fetch(nil)).to be_nil
        expect(obj.fetch(nil)).to be_nil
        expect(obj.call_count).to eq(2)
      end

      it "caches false values when the condition allows it" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def flag
            @call_count += 1
            false
          end

          memoize :flag, if: ->(result) { !result.nil? }
        end

        obj = klass.new
        obj.flag
        obj.flag
        expect(obj.call_count).to eq(1)
      end

      it "caches once the condition is eventually met" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def fetch
            @call_count += 1
            (@call_count < 3) ? nil : "ready"
          end

          memoize :fetch, if: ->(result) { !result.nil? }
        end

        obj = klass.new
        expect(obj.fetch).to be_nil   # miss, not cached
        expect(obj.fetch).to be_nil   # miss, not cached
        expect(obj.fetch).to eq("ready")  # miss, now cached
        expect(obj.fetch).to eq("ready")  # hit
        expect(obj.call_count).to eq(3)
      end
    end

    describe "memoize with :unless" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def fetch(value)
            @call_count += 1
            value
          end

          memoize :fetch, unless: ->(result) { result.nil? }
        end
      end

      it "caches the result when the condition is not met" do
        obj = klass.new
        expect(obj.fetch("data")).to eq("data")
        expect(obj.fetch("data")).to eq("data")
        expect(obj.call_count).to eq(1)
      end

      it "does not cache when the condition is met" do
        obj = klass.new
        expect(obj.fetch(nil)).to be_nil
        expect(obj.fetch(nil)).to be_nil
        expect(obj.call_count).to eq(2)
      end
    end

    describe "interaction with memoized? and memo_count" do
      it "memoized? returns false for a result that was not cached" do
        klass = Class.new do
          prepend SafeMemoize

          def fetch(v) = v
          memoize :fetch, if: ->(result) { !result.nil? }
        end

        obj = klass.new
        obj.fetch(nil)
        expect(obj.memoized?(:fetch, nil)).to be(false)
      end

      it "memo_count does not count un-cached results" do
        klass = Class.new do
          prepend SafeMemoize

          def fetch(v) = v
          memoize :fetch, if: ->(result) { !result.nil? }
        end

        obj = klass.new
        obj.fetch(nil)
        obj.fetch("ok")
        expect(obj.memo_count(:fetch)).to eq(1)
      end
    end

    describe "combining :if with max_size" do
      it "only cached results count toward the LRU limit" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def fetch(v)
            @call_count += 1
            v
          end

          memoize :fetch, max_size: 2, if: ->(result) { !result.nil? }
        end

        obj = klass.new

        obj.fetch(nil)   # not cached
        obj.fetch(nil)   # recomputed — still not cached
        expect(obj.call_count).to eq(2)
        expect(obj.memo_count(:fetch)).to eq(0)

        obj.fetch("a")   # cached (1/2)
        obj.fetch("b")   # cached (2/2)
        expect(obj.memo_count(:fetch)).to eq(2)

        obj.fetch("c")   # cached — evicts "a" (LRU)
        expect(obj.memo_count(:fetch)).to eq(2)

        obj.fetch("a")   # "a" was evicted, recomputed
        expect(obj.call_count).to eq(6)
      end
    end

    describe "combining :if with ttl" do
      it "caches with TTL only when the condition is met" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def fetch(v)
            @call_count += 1
            v
          end

          memoize :fetch, ttl: 0.1, if: ->(result) { !result.nil? }
        end

        obj = klass.new
        obj.fetch(nil)   # not cached
        obj.fetch(nil)   # recomputed
        expect(obj.call_count).to eq(2)

        obj.fetch("ok")  # cached with TTL
        obj.fetch("ok")  # hit
        expect(obj.call_count).to eq(3)
      end
    end

    describe "isolation between instances" do
      it "conditions are evaluated independently per instance" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def fetch(v)
            @call_count += 1
            v
          end

          memoize :fetch, if: ->(result) { !result.nil? }
        end

        a = klass.new
        b = klass.new

        a.fetch(nil)
        b.fetch("data")

        expect(a.memo_count(:fetch)).to eq(0)
        expect(b.memo_count(:fetch)).to eq(1)
      end
    end

    describe "thread safety" do
      it "does not cache conditionally-skipped results under concurrent access" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
            @mutex = Mutex.new
          end

          def compute(v)
            @mutex.synchronize { @call_count += 1 }
            sleep(0.001)
            v
          end

          memoize :compute, if: ->(result) { !result.nil? }
        end

        obj = klass.new

        threads = 10.times.map { Thread.new { obj.compute(nil) } }
        threads.each(&:join)

        expect(obj.memo_count(:compute)).to eq(0)
        expect(obj.call_count).to eq(10)
      end
    end
  end
end
