# frozen_string_literal: true

RSpec.describe SafeMemoize do
  it "has a version number" do
    expect(SafeMemoize::VERSION).not_to be_nil
  end

  describe ".memoize" do
    context "basic memoization" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def expensive
            @call_count += 1
            "result"
          end

          memoize :expensive
        end
      end

      it "caches the result" do
        obj = klass.new
        expect(obj.expensive).to eq("result")
        expect(obj.expensive).to eq("result")
        expect(obj.call_count).to eq(1)
      end

      it "returns the same object" do
        obj = klass.new
        first = obj.expensive
        second = obj.expensive
        expect(first).to equal(second)
      end
    end

    context "nil and false safety" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          attr_reader :nil_count, :false_count

          def initialize
            @nil_count = 0
            @false_count = 0
          end

          def returns_nil
            @nil_count += 1
            nil
          end

          def returns_false
            @false_count += 1
            false
          end

          memoize :returns_nil
          memoize :returns_false
        end
      end

      it "memoizes nil without re-computation" do
        obj = klass.new
        expect(obj.returns_nil).to be_nil
        expect(obj.returns_nil).to be_nil
        expect(obj.nil_count).to eq(1)
      end

      it "memoizes false without re-computation" do
        obj = klass.new
        expect(obj.returns_false).to eq(false)
        expect(obj.returns_false).to eq(false)
        expect(obj.false_count).to eq(1)
      end
    end

    context "argument support" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          attr_reader :call_log

          def initialize
            @call_log = []
          end

          def compute(x, y)
            @call_log << [x, y]
            x + y
          end

          def with_kwargs(a, b:)
            @call_log << [a, b]
            "#{a}-#{b}"
          end

          memoize :compute
          memoize :with_kwargs
        end
      end

      it "caches per unique positional arguments" do
        obj = klass.new
        expect(obj.compute(1, 2)).to eq(3)
        expect(obj.compute(1, 2)).to eq(3)
        expect(obj.compute(3, 4)).to eq(7)
        expect(obj.call_log).to eq([[1, 2], [3, 4]])
      end

      it "caches per unique keyword arguments" do
        obj = klass.new
        expect(obj.with_kwargs("x", b: "y")).to eq("x-y")
        expect(obj.with_kwargs("x", b: "y")).to eq("x-y")
        expect(obj.with_kwargs("x", b: "z")).to eq("x-z")
        expect(obj.call_log).to eq([["x", "y"], ["x", "z"]])
      end
    end

    context "thread safety" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
            @count_mutex = Mutex.new
          end

          def slow_method
            @count_mutex.synchronize { @call_count += 1 }
            sleep(0.001)
            "done"
          end

          memoize :slow_method
        end
      end

      it "computes only once across concurrent threads" do
        obj = klass.new
        threads = 10.times.map do
          Thread.new do
            100.times { obj.slow_method }
          end
        end
        threads.each(&:join)

        expect(obj.call_count).to eq(1)
        expect(obj.slow_method).to eq("done")
      end
    end

    context "cache reset" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          attr_reader :a_count, :b_count

          def initialize
            @a_count = 0
            @b_count = 0
          end

          def method_a
            @a_count += 1
            "a"
          end

          def method_b
            @b_count += 1
            "b"
          end

          memoize :method_a
          memoize :method_b
        end
      end

      it "reset_memo clears cache for a single method" do
        obj = klass.new
        obj.method_a
        obj.method_b
        expect(obj.a_count).to eq(1)
        expect(obj.b_count).to eq(1)

        obj.reset_memo(:method_a)
        obj.method_a
        obj.method_b
        expect(obj.a_count).to eq(2)
        expect(obj.b_count).to eq(1)
      end

      it "reset_memo clears only the matching positional argument entry" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_log

          def initialize
            @call_log = []
          end

          def compute(value)
            @call_log << value
            value * 2
          end

          memoize :compute
        end

        obj = klass.new

        expect(obj.compute(1)).to eq(2)
        expect(obj.compute(2)).to eq(4)
        expect(obj.call_log).to eq([1, 2])

        obj.reset_memo(:compute, 1)

        expect(obj.compute(1)).to eq(2)
        expect(obj.compute(2)).to eq(4)
        expect(obj.call_log).to eq([1, 2, 1])
      end

      it "reset_memo clears only the matching keyword argument entry" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_log

          def initialize
            @call_log = []
          end

          def lookup(id, locale:)
            @call_log << [id, locale]
            "#{id}-#{locale}"
          end

          memoize :lookup
        end

        obj = klass.new

        expect(obj.lookup(7, locale: :en)).to eq("7-en")
        expect(obj.lookup(7, locale: :fr)).to eq("7-fr")
        expect(obj.call_log).to eq([[7, :en], [7, :fr]])

        obj.reset_memo(:lookup, 7, locale: :en)

        expect(obj.lookup(7, locale: :en)).to eq("7-en")
        expect(obj.lookup(7, locale: :fr)).to eq("7-fr")
        expect(obj.call_log).to eq([[7, :en], [7, :fr], [7, :en]])
      end

      it "reset_memo without arguments clears all cached entries for the method" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_log

          def initialize
            @call_log = []
          end

          def lookup(id, locale:)
            @call_log << [id, locale]
            "#{id}-#{locale}"
          end

          memoize :lookup
        end

        obj = klass.new

        expect(obj.lookup(7, locale: :en)).to eq("7-en")
        expect(obj.lookup(7, locale: :fr)).to eq("7-fr")
        expect(obj.call_log).to eq([[7, :en], [7, :fr]])

        obj.reset_memo(:lookup)

        expect(obj.lookup(7, locale: :en)).to eq("7-en")
        expect(obj.lookup(7, locale: :fr)).to eq("7-fr")
        expect(obj.call_log).to eq([[7, :en], [7, :fr], [7, :en], [7, :fr]])
      end

      it "ignores argument-specific resets when no matching cache entry exists" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_log

          def initialize
            @call_log = []
          end

          def compute(value)
            @call_log << value
            value * 2
          end

          memoize :compute
        end

        obj = klass.new

        expect(obj.compute(1)).to eq(2)

        obj.reset_memo(:compute, 2)

        expect(obj.compute(1)).to eq(2)
        expect(obj.call_log).to eq([1])
      end

      it "reset_all_memos clears cache for all methods" do
        obj = klass.new
        obj.method_a
        obj.method_b
        expect(obj.a_count).to eq(1)
        expect(obj.b_count).to eq(1)

        obj.reset_all_memos
        obj.method_a
        obj.method_b
        expect(obj.a_count).to eq(2)
        expect(obj.b_count).to eq(2)
      end
    end

    context "memo_ttl_remaining" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          def value = 1
          def keyed(x) = x

          memoize :value, ttl: 60
          memoize :keyed, ttl: 60
        end
      end

      it "returns 0 when the entry has not been cached yet" do
        expect(klass.new.memo_ttl_remaining(:value)).to eq(0)
      end

      it "returns nil when the method has no TTL" do
        klass2 = Class.new do
          prepend SafeMemoize

          def value = 1
          memoize :value
        end
        obj = klass2.new
        obj.value
        expect(obj.memo_ttl_remaining(:value)).to be_nil
      end

      it "returns a positive number of seconds remaining" do
        obj = klass.new
        obj.value
        remaining = obj.memo_ttl_remaining(:value)
        expect(remaining).to be > 0
        expect(remaining).to be <= 60
      end

      it "returns 0 after the entry expires" do
        klass2 = Class.new do
          prepend SafeMemoize

          def value = 1
          memoize :value, ttl: 0.01
        end
        obj = klass2.new
        obj.value
        sleep(0.02)
        expect(obj.memo_ttl_remaining(:value)).to eq(0)
      end

      it "scopes to a specific argument combination" do
        obj = klass.new
        obj.keyed(1)
        expect(obj.memo_ttl_remaining(:keyed, 1)).to be > 0
        expect(obj.memo_ttl_remaining(:keyed, 2)).to eq(0)
      end
    end

    context "memo_refresh" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def value
            @call_count += 1
            @call_count
          end

          def keyed(x)
            @call_count += 1
            x * @call_count
          end

          memoize :value
          memoize :keyed
        end
      end

      it "recomputes and updates the cached value" do
        obj = klass.new
        first = obj.value
        result = obj.memo_refresh(:value)
        expect(result).not_to eq(first)
        expect(obj.value).to eq(result)
      end

      it "returns the newly computed value" do
        obj = klass.new
        obj.value
        expect(obj.memo_refresh(:value)).to eq(2)
      end

      it "recomputes only the matching argument entry" do
        obj = klass.new
        obj.keyed(1)
        obj.keyed(2)
        obj.memo_refresh(:keyed, 1)
        expect(obj.call_count).to eq(3)
      end

      it "works on a method that has not been cached yet" do
        obj = klass.new
        expect { obj.memo_refresh(:value) }.not_to raise_error
        expect(obj.call_count).to eq(1)
      end
    end

    context "memo_age" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value
        end
      end

      it "returns nil when the entry has not been cached" do
        expect(klass.new.memo_age(:value)).to be_nil
      end

      it "returns a non-negative float after the entry is cached" do
        obj = klass.new
        obj.value
        expect(obj.memo_age(:value)).to be >= 0
        expect(obj.memo_age(:value)).to be_a(Float)
      end

      it "grows over time" do
        obj = klass.new
        obj.value
        age1 = obj.memo_age(:value)
        sleep(0.02)
        age2 = obj.memo_age(:value)
        expect(age2).to be > age1
      end

      it "returns nil after the entry expires" do
        klass2 = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value, ttl: 0.01
        end
        obj = klass2.new
        obj.value
        sleep(0.02)
        expect(obj.memo_age(:value)).to be_nil
      end

      it "returns age for a warmed entry" do
        obj = klass.new
        obj.warm_memo(:value) { 42 }
        expect(obj.memo_age(:value)).to be >= 0
      end
    end

    context "memo_stale?" do
      it "returns false when the entry has not been cached" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value
        end
        expect(klass.new.memo_stale?(:value)).to be(false)
      end

      it "returns false for a live cached entry" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value, ttl: 60
        end
        obj = klass.new
        obj.value
        expect(obj.memo_stale?(:value)).to be(false)
      end

      it "returns false for an entry with no TTL" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value
        end
        obj = klass.new
        obj.value
        expect(obj.memo_stale?(:value)).to be(false)
      end

      it "returns true after the TTL has elapsed" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value, ttl: 0.01
        end
        obj = klass.new
        obj.value
        sleep(0.02)
        expect(obj.memo_stale?(:value)).to be(true)
      end
    end

    context "memo_touch" do
      it "returns false when the entry has not been cached" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value, ttl: 60
        end
        expect(klass.new.memo_touch(:value)).to be(false)
      end

      it "returns false when the entry has expired" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value, ttl: 0.01
        end
        obj = klass.new
        obj.value
        sleep(0.02)
        expect(obj.memo_touch(:value)).to be(false)
      end

      it "returns true for a live entry" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value, ttl: 60
        end
        obj = klass.new
        obj.value
        expect(obj.memo_touch(:value)).to be(true)
      end

      it "extends the TTL using the original TTL when none given" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value, ttl: 0.1
        end
        obj = klass.new
        obj.value
        sleep(0.07)
        obj.memo_touch(:value)
        sleep(0.07)
        expect(obj.memoized?(:value)).to be(true)
      end

      it "extends the TTL by an explicit duration" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value, ttl: 0.01
        end
        obj = klass.new
        obj.value
        obj.memo_touch(:value, ttl: 60)
        expect(obj.memo_ttl_remaining(:value)).to be > 30
      end

      it "resets memo_age after touching" do
        klass = Class.new do
          prepend SafeMemoize

          def value = 1

          memoize :value, ttl: 60
        end
        obj = klass.new
        obj.value
        sleep(0.02)
        age_before = obj.memo_age(:value)
        obj.memo_touch(:value)
        expect(obj.memo_age(:value)).to be < age_before
      end
    end

    context "cache inspection" do
      it "returns whether a zero-argument method has been memoized" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def expensive
            @call_count += 1
            "result"
          end

          memoize :expensive
        end

        obj = klass.new

        expect(obj.memoized?(:expensive)).to be(false)

        obj.expensive

        expect(obj.memoized?(:expensive)).to be(true)
        expect(obj.call_count).to eq(1)
      end

      it "reports cached nil and false values as memoized" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :nil_count, :false_count

          def initialize
            @nil_count = 0
            @false_count = 0
          end

          def returns_nil
            @nil_count += 1
            nil
          end

          def returns_false
            @false_count += 1
            false
          end

          memoize :returns_nil
          memoize :returns_false
        end

        obj = klass.new

        obj.returns_nil
        obj.returns_false

        expect(obj.memoized?(:returns_nil)).to be(true)
        expect(obj.memoized?(:returns_false)).to be(true)
      end

      it "checks memoization per unique positional and keyword arguments" do
        klass = Class.new do
          prepend SafeMemoize

          def lookup(id, locale:)
            "#{id}-#{locale}"
          end

          memoize :lookup
        end

        obj = klass.new

        expect(obj.memoized?(:lookup, 7, locale: :en)).to be(false)

        obj.lookup(7, locale: :en)

        expect(obj.memoized?(:lookup, 7, locale: :en)).to be(true)
        expect(obj.memoized?(:lookup, 7, locale: :fr)).to be(false)
        expect(obj.memoized?(:lookup, 8, locale: :en)).to be(false)
      end

      it "returns false after a cached entry is reset" do
        klass = Class.new do
          prepend SafeMemoize

          def compute(value)
            value * 2
          end

          memoize :compute
        end

        obj = klass.new
        obj.compute(5)

        expect(obj.memoized?(:compute, 5)).to be(true)

        obj.reset_memo(:compute, 5)

        expect(obj.memoized?(:compute, 5)).to be(false)
      end

      it "always returns false for block-based calls" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def with_block(&block)
            @call_count += 1
            block.call
          end

          memoize :with_block
        end

        obj = klass.new

        expect(obj.memoized?(:with_block) { "value" }).to be(false)

        obj.with_block { "value" }

        expect(obj.memoized?(:with_block) { "value" }).to be(false)
        expect(obj.memoized?(:with_block)).to be(false)
        expect(obj.call_count).to eq(1)
      end

      it "returns zero when no memoized values have been cached yet" do
        klass = Class.new do
          prepend SafeMemoize

          def value
            1
          end

          memoize :value
        end

        obj = klass.new

        expect(obj.memo_count).to eq(0)
        expect(obj.memo_count(:value)).to eq(0)
      end

      it "returns the global memoized entry count" do
        klass = Class.new do
          prepend SafeMemoize

          def a
            "a"
          end

          def b(id)
            "b-#{id}"
          end

          memoize :a
          memoize :b
        end

        obj = klass.new

        obj.a
        obj.b(1)
        obj.b(2)

        expect(obj.memo_count).to eq(3)
      end

      it "returns the per-method memoized entry count" do
        klass = Class.new do
          prepend SafeMemoize

          def find(id)
            "item-#{id}"
          end

          memoize :find
        end

        obj = klass.new

        obj.find(1)
        obj.find(2)

        expect(obj.memo_count(:find)).to eq(2)
        expect(obj.memo_count("find")).to eq(2)
        expect(obj.memo_count(:missing)).to eq(0)
      end

      it "tracks count changes after targeted and full resets" do
        klass = Class.new do
          prepend SafeMemoize

          def compute(v)
            v * 2
          end

          memoize :compute
        end

        obj = klass.new

        obj.compute(1)
        obj.compute(2)
        expect(obj.memo_count(:compute)).to eq(2)

        obj.reset_memo(:compute, 1)
        expect(obj.memo_count(:compute)).to eq(1)

        obj.reset_all_memos
        expect(obj.memo_count).to eq(0)
      end

      it "returns an empty list of keys when nothing is cached" do
        klass = Class.new do
          prepend SafeMemoize

          def value
            1
          end

          memoize :value
        end

        obj = klass.new

        expect(obj.memo_keys).to eq([])
        expect(obj.memo_keys(:value)).to eq([])
      end

      it "returns global cache keys with method, args, and kwargs" do
        klass = Class.new do
          prepend SafeMemoize

          def a
            "a"
          end

          def lookup(id, locale:)
            "#{id}-#{locale}"
          end

          memoize :a
          memoize :lookup
        end

        obj = klass.new

        obj.a
        obj.lookup(7, locale: :en)

        expect(obj.memo_keys).to eq(
          [
            {method: :a, args: [], kwargs: {}},
            {method: :lookup, args: [7], kwargs: {locale: :en}}
          ]
        )
      end

      it "returns method-scoped keys with args and kwargs only" do
        klass = Class.new do
          prepend SafeMemoize

          def lookup(id, locale:)
            "#{id}-#{locale}"
          end

          memoize :lookup
        end

        obj = klass.new

        obj.lookup(7, locale: :en)
        obj.lookup(7, locale: :fr)

        expect(obj.memo_keys(:lookup)).to eq(
          [
            {args: [7], kwargs: {locale: :en}},
            {args: [7], kwargs: {locale: :fr}}
          ]
        )
        expect(obj.memo_keys("lookup")).to eq(
          [
            {args: [7], kwargs: {locale: :en}},
            {args: [7], kwargs: {locale: :fr}}
          ]
        )
      end

      it "updates key inspection results after reset operations" do
        klass = Class.new do
          prepend SafeMemoize

          def compute(value)
            value * 2
          end

          memoize :compute
        end

        obj = klass.new

        obj.compute(1)
        obj.compute(2)
        expect(obj.memo_keys(:compute)).to eq(
          [
            {args: [1], kwargs: {}},
            {args: [2], kwargs: {}}
          ]
        )

        obj.reset_memo(:compute, 1)
        expect(obj.memo_keys(:compute)).to eq([{args: [2], kwargs: {}}])

        obj.reset_all_memos
        expect(obj.memo_keys).to eq([])
      end

      it "returns an empty list of values when nothing is cached" do
        klass = Class.new do
          prepend SafeMemoize

          def value
            1
          end

          memoize :value
        end

        obj = klass.new

        expect(obj.memo_values).to eq([])
        expect(obj.memo_values(:value)).to eq([])
      end

      it "returns global cache entries including values" do
        klass = Class.new do
          prepend SafeMemoize

          def a
            "a"
          end

          def lookup(id, locale:)
            "#{id}-#{locale}"
          end

          memoize :a
          memoize :lookup
        end

        obj = klass.new

        obj.a
        obj.lookup(7, locale: :en)

        expect(obj.memo_values).to eq(
          [
            {method: :a, args: [], kwargs: {}, value: "a"},
            {method: :lookup, args: [7], kwargs: {locale: :en}, value: "7-en"}
          ]
        )
      end

      it "returns method-scoped entries including values" do
        klass = Class.new do
          prepend SafeMemoize

          def compute(v)
            v * 2
          end

          memoize :compute
        end

        obj = klass.new

        obj.compute(1)
        obj.compute(2)

        expect(obj.memo_values(:compute)).to eq(
          [
            {args: [1], kwargs: {}, value: 2},
            {args: [2], kwargs: {}, value: 4}
          ]
        )
        expect(obj.memo_values("compute")).to eq(
          [
            {args: [1], kwargs: {}, value: 2},
            {args: [2], kwargs: {}, value: 4}
          ]
        )
      end

      it "updates value inspection results after reset operations" do
        klass = Class.new do
          prepend SafeMemoize

          def compute(v)
            v * 2
          end

          memoize :compute
        end

        obj = klass.new

        obj.compute(1)
        obj.compute(2)
        expect(obj.memo_values(:compute)).to eq(
          [
            {args: [1], kwargs: {}, value: 2},
            {args: [2], kwargs: {}, value: 4}
          ]
        )

        obj.reset_memo(:compute, 1)
        expect(obj.memo_values(:compute)).to eq([{args: [2], kwargs: {}, value: 4}])

        obj.reset_all_memos
        expect(obj.memo_values).to eq([])
      end
    end

    context "ttl expiration" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def expensive
            @call_count += 1
            "result"
          end

          memoize :expensive, ttl: 0.01
        end
      end

      it "measures ttl from first call, not from memoize definition" do
        # Sleep before the first call to ensure the TTL clock starts at call time.
        # If expires_at were fixed at class-load time this entry would already be
        # near-expiry and the second call would recompute.
        sleep(0.015)
        obj = klass.new
        obj.expensive
        expect(obj.call_count).to eq(1)
        obj.expensive
        expect(obj.call_count).to eq(1) # still cached — ttl not yet elapsed
      end

      it "expires memoized entries after the ttl and prunes inspection results" do
        obj = klass.new

        expect(obj.expensive).to eq("result")
        expect(obj.memoized?(:expensive)).to be(true)
        expect(obj.memo_count).to eq(1)
        expect(obj.memo_keys).to eq([{method: :expensive, args: [], kwargs: {}}])
        expect(obj.memo_values).to eq([{method: :expensive, args: [], kwargs: {}, value: "result"}])

        sleep(0.02)

        expect(obj.memoized?(:expensive)).to be(false)
        expect(obj.memo_count).to eq(0)
        expect(obj.memo_keys).to eq([])
        expect(obj.memo_values).to eq([])

        expect(obj.expensive).to eq("result")
        expect(obj.call_count).to eq(2)
      end
    end

    context "ttl_refresh: true" do
      it "raises ArgumentError when used without ttl:" do
        expect do
          Class.new do
            prepend SafeMemoize

            def value = 1
            memoize :value, ttl_refresh: true
          end
        end.to raise_error(ArgumentError, /ttl_refresh.*ttl/)
      end

      it "resets the expiry clock on every cache hit" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count
          def initialize = (@call_count = 0)
          def compute = (@call_count += 1)
          memoize :compute, ttl: 0.03, ttl_refresh: true
        end

        obj = klass.new
        obj.compute               # miss — starts TTL
        sleep(0.02)
        obj.compute               # hit — refreshes TTL
        sleep(0.02)
        expect(obj.compute).to eq(1)   # still cached — TTL was refreshed
        expect(obj.call_count).to eq(1)
      end

      it "expires after a full ttl of inactivity" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count
          def initialize = (@call_count = 0)
          def compute = (@call_count += 1)
          memoize :compute, ttl: 0.02, ttl_refresh: true
        end

        obj = klass.new
        obj.compute
        sleep(0.04)
        obj.compute               # expired — recomputes
        expect(obj.call_count).to eq(2)
      end

      it "works with shared: true" do
        klass = Class.new do
          prepend SafeMemoize

          def value = rand
          memoize :value, shared: true, ttl: 0.03, ttl_refresh: true
        end

        first = klass.new.value
        sleep(0.02)
        klass.new.value           # hit — refreshes shared TTL
        sleep(0.02)
        expect(klass.new.value).to eq(first) # still cached
        klass.reset_all_shared_memos
      end
    end

    context "edge cases" do
      it "preserves private visibility for memoized methods" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def reveal_twice
            [secret, secret]
          end

          def call_secret_with_send
            send(:secret)
          end

          private

          def secret
            @call_count += 1
            "shh"
          end

          memoize :secret
        end

        obj = klass.new

        expect(obj.reveal_twice).to eq(["shh", "shh"])
        expect(obj.call_count).to eq(1)
        expect(obj.call_secret_with_send).to eq("shh")
        expect(obj.call_count).to eq(1)
        expect(obj.respond_to?(:secret)).to be(false)
        expect(obj.private_methods).to include(:secret)
      end

      it "preserves protected visibility for memoized methods" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def same_token_as?(other)
            [token, other.token]
          end

          protected

          def token
            @call_count += 1
            "token"
          end

          memoize :token
        end

        a = klass.new
        b = klass.new

        expect(a.same_token_as?(b)).to eq(["token", "token"])
        expect(a.same_token_as?(b)).to eq(["token", "token"])
        expect(a.call_count).to eq(1)
        expect(b.call_count).to eq(1)
        expect(a.respond_to?(:token)).to be(false)
        expect(a.protected_methods).to include(:token)
      end

      it "passes blocks through without caching" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def with_block(&block)
            @call_count += 1
            block.call
          end

          memoize :with_block
        end

        obj = klass.new
        expect(obj.with_block { "first" }).to eq("first")
        expect(obj.with_block { "second" }).to eq("second")
        expect(obj.call_count).to eq(2)
      end

      it "supports multiple memoized methods independently" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :x_count, :y_count

          def initialize
            @x_count = 0
            @y_count = 0
          end

          def method_x
            @x_count += 1
            "x"
          end

          def method_y
            @y_count += 1
            "y"
          end

          memoize :method_x
          memoize :method_y
        end

        obj = klass.new
        obj.method_x
        obj.method_y
        obj.method_x
        obj.method_y
        expect(obj.x_count).to eq(1)
        expect(obj.y_count).to eq(1)
      end

      it "does not share cache between instances" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def value
            @call_count += 1
            object_id
          end

          memoize :value
        end

        a = klass.new
        b = klass.new
        expect(a.value).not_to eq(b.value)
        expect(a.call_count).to eq(1)
        expect(b.call_count).to eq(1)
      end

      it "propagates exceptions without caching" do
        klass = Class.new do
          prepend SafeMemoize

          attr_reader :call_count

          def initialize
            @call_count = 0
          end

          def unstable
            @call_count += 1
            raise "boom" if @call_count == 1
            "recovered"
          end

          memoize :unstable
        end

        obj = klass.new
        expect { obj.unstable }.to raise_error(RuntimeError, "boom")
        expect(obj.unstable).to eq("recovered")
        expect(obj.call_count).to eq(2)
      end
    end

    context "undefined method guard" do
      it "raises ArgumentError with a descriptive message when the method does not exist" do
        expect do
          Class.new do
            prepend SafeMemoize

            memoize :nonexistent
          end
        end.to raise_error(ArgumentError, /cannot memoize :nonexistent.*no instance method/)
      end

      it "includes the class name in the error message" do
        expect do
          Class.new do
            prepend SafeMemoize

            memoize :missing_method
          end
        end.to raise_error(ArgumentError, /missing_method/)
      end

      it "does not raise for a public method" do
        expect do
          Class.new do
            prepend SafeMemoize

            def value = 1
            memoize :value
          end
        end.not_to raise_error
      end

      it "does not raise for a private method" do
        expect do
          Class.new do
            prepend SafeMemoize

            private

            def secret = "shh"
            memoize :secret
          end
        end.not_to raise_error
      end

      it "does not raise for a protected method" do
        expect do
          Class.new do
            prepend SafeMemoize

            protected

            def guarded = 42
            memoize :guarded
          end
        end.not_to raise_error
      end
    end
  end

  describe "safe_memoize_options" do
    context "ttl default" do
      it "applies the class-level ttl to every memoize call that omits ttl:" do
        klass = Class.new do
          prepend SafeMemoize

          safe_memoize_options ttl: 0.05

          def value = rand
          memoize :value
        end

        obj = klass.new
        first = obj.value
        expect(obj.value).to eq(first)

        sleep 0.07
        expect(obj.value).not_to eq(first)
      end

      it "is overridden by an explicit ttl: on the memoize call" do
        klass = Class.new do
          prepend SafeMemoize

          safe_memoize_options ttl: 0.05

          def a = rand
          memoize :a

          def b = rand
          memoize :b, ttl: 999
        end

        obj = klass.new
        a_first = obj.a
        b_first = obj.b

        sleep 0.07

        expect(obj.a).not_to eq(a_first)
        expect(obj.b).to eq(b_first)
      end
    end

    context "max_size default" do
      it "applies the class-level max_size to every memoize call" do
        klass = Class.new do
          prepend SafeMemoize

          safe_memoize_options max_size: 2

          def fetch(n) = n * 10
          memoize :fetch
        end

        obj = klass.new
        obj.fetch(1)
        obj.fetch(2)
        obj.fetch(3)

        expect(obj.memo_count(:fetch)).to eq(2)
      end

      it "is overridden by an explicit max_size: on the memoize call" do
        klass = Class.new do
          prepend SafeMemoize

          safe_memoize_options max_size: 2

          def small(n) = n
          memoize :small

          def large(n) = n
          memoize :large, max_size: 10
        end

        obj = klass.new
        5.times { |i| obj.small(i) }
        5.times { |i| obj.large(i) }

        expect(obj.memo_count(:small)).to eq(2)
        expect(obj.memo_count(:large)).to eq(5)
      end
    end

    context "copy_on_read default" do
      it "applies copy_on_read to all memoized methods on the class" do
        klass = Class.new do
          prepend SafeMemoize

          safe_memoize_options copy_on_read: true

          def data = [1, 2, 3]
          memoize :data
        end

        obj = klass.new
        r1 = obj.data
        r2 = obj.data
        expect(r1).to eq(r2)
        expect(r1).not_to be(r2)
      end
    end

    context "global config fallback" do
      it "class defaults take precedence over global config" do
        SafeMemoize.configure { |c| c.default_max_size = 10 }

        klass = Class.new do
          prepend SafeMemoize

          safe_memoize_options max_size: 2

          def fetch(n) = n
          memoize :fetch
        end

        obj = klass.new
        5.times { |i| obj.fetch(i) }
        expect(obj.memo_count(:fetch)).to eq(2)
      ensure
        SafeMemoize.reset_configuration!
      end

      it "global config still applies when no class default is set for that option" do
        SafeMemoize.configure { |c| c.default_max_size = 2 }

        klass = Class.new do
          prepend SafeMemoize

          def fetch(n) = n
          memoize :fetch
        end

        obj = klass.new
        5.times { |i| obj.fetch(i) }
        expect(obj.memo_count(:fetch)).to eq(2)
      ensure
        SafeMemoize.reset_configuration!
      end
    end

    context "clearing class defaults" do
      it "clears all defaults when called with no arguments" do
        klass = Class.new do
          prepend SafeMemoize

          safe_memoize_options ttl: 0.01

          def a = rand
          memoize :a
        end

        klass.safe_memoize_options

        klass.class_eval do
          def b = rand
          memoize :b
        end

        obj = klass.new
        b_first = obj.b
        sleep 0.02
        expect(obj.b).to eq(b_first)
      end
    end

    context "disallowed options" do
      it "raises ArgumentError for :shared" do
        expect do
          Class.new do
            prepend SafeMemoize

            safe_memoize_options shared: true
          end
        end.to raise_error(ArgumentError, /:shared/)
      end

      it "raises ArgumentError for :fiber_local" do
        expect do
          Class.new do
            prepend SafeMemoize

            safe_memoize_options fiber_local: true
          end
        end.to raise_error(ArgumentError, /:fiber_local/)
      end

      it "raises ArgumentError for :ractor_safe" do
        expect do
          Class.new do
            prepend SafeMemoize

            safe_memoize_options ractor_safe: true
          end
        end.to raise_error(ArgumentError, /:ractor_safe/)
      end

      it "raises ArgumentError for :shared_cache" do
        expect do
          Class.new do
            prepend SafeMemoize

            safe_memoize_options shared_cache: "my_cache"
          end
        end.to raise_error(ArgumentError, /:shared_cache/)
      end
    end
  end

  describe "copy_on_read: true" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        def config = {host: "localhost", port: 8080}
        memoize :config, copy_on_read: true

        def tags = %w[a b c]
        memoize :tags, copy_on_read: true

        def count = 42
        memoize :count, copy_on_read: true

        def nothing = nil
        memoize :nothing, copy_on_read: true
      end
    end

    it "returns equal values on successive calls" do
      obj = klass.new
      expect(obj.config).to eq({host: "localhost", port: 8080})
      expect(obj.config).to eq({host: "localhost", port: 8080})
    end

    it "returns a different object identity on every cache hit" do
      obj = klass.new
      r1 = obj.config
      r2 = obj.config
      expect(r1).not_to be(r2)
    end

    it "prevents caller mutation from corrupting the cache" do
      obj = klass.new
      result = obj.config
      result[:host] = "mutated"

      fresh = obj.config
      expect(fresh[:host]).to eq("localhost")
    end

    it "returns a different array object on every call" do
      obj = klass.new
      r1 = obj.tags
      r2 = obj.tags
      expect(r1).to eq(r2)
      expect(r1).not_to be(r2)
    end

    it "returns nil as-is (no dup attempted)" do
      obj = klass.new
      expect(obj.nothing).to be_nil
      expect(obj.nothing).to be_nil
    end

    it "returns frozen/immediate values as-is" do
      obj = klass.new
      r1 = obj.count
      r2 = obj.count
      expect(r1).to eq(42)
      expect(r2).to eq(42)
    end

    context "with max_size: (locked path)" do
      it "still dups on hit through the locked path" do
        k = Class.new do
          prepend SafeMemoize

          def data = [1, 2, 3]
          memoize :data, copy_on_read: true, max_size: 10
        end

        obj = k.new
        r1 = obj.data
        r2 = obj.data
        expect(r1).to eq(r2)
        expect(r1).not_to be(r2)

        r2 << 99
        expect(obj.data).to eq([1, 2, 3])
      end
    end

    context "with shared: true" do
      it "still dups on hit through the shared path" do
        k = Class.new do
          prepend SafeMemoize

          def shared_data = [10, 20]
          memoize :shared_data, copy_on_read: true, shared: true
        end

        obj = k.new
        r1 = obj.shared_data
        r2 = obj.shared_data
        expect(r1).to eq(r2)
        expect(r1).not_to be(r2)

        r1 << 99
        expect(k.new.shared_data).to eq([10, 20])
      end
    end

    context "with ttl:" do
      it "returns a dup on every hit, including after a ttl refresh" do
        k = Class.new do
          prepend SafeMemoize

          def items = %w[x y]
          memoize :items, copy_on_read: true, ttl: 60
        end

        obj = k.new
        r1 = obj.items
        r2 = obj.items
        expect(r1).to eq(r2)
        expect(r1).not_to be(r2)
      end
    end

    context "with deep_dup available" do
      it "calls deep_dup when the value responds to it" do
        inner = Object.new
        deep_copy = Object.new
        allow(inner).to receive(:respond_to?).with(:deep_dup).and_return(true)
        allow(inner).to receive(:respond_to?).with(anything).and_call_original
        allow(inner).to receive(:deep_dup).and_return(deep_copy)
        allow(inner).to receive(:frozen?).and_return(false)

        k = Class.new do
          prepend SafeMemoize

          define_method(:wrapped) { inner }
          memoize :wrapped, copy_on_read: true
        end

        obj = k.new
        obj.wrapped
        result = obj.wrapped
        expect(result).to be(deep_copy)
      end
    end

    context "ractor_safe: incompatibility" do
      it "raises ArgumentError when combined with ractor_safe:" do
        expect do
          Class.new do
            prepend SafeMemoize

            def value = 42
            memoize :value, shared: true, ractor_safe: true, copy_on_read: true
          end
        end.to raise_error(ArgumentError, /copy_on_read/)
      end
    end
  end
end
