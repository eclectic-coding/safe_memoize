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
  end
end
