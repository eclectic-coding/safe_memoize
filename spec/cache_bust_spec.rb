# frozen_string_literal: true

RSpec.describe "SafeMemoize cache_bust:" do
  after { SafeMemoize.reset_configuration! }

  # ---------------------------------------------------------------------------
  # Basic invalidation behaviour
  # ---------------------------------------------------------------------------

  describe "automatic cache busting" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        attr_accessor :version

        def initialize
          @version = 1
          @calls = 0
        end

        def compute
          @calls += 1
          "result_v#{@version}"
        end
        memoize :compute, cache_bust: -> { @version }

        def call_count = @calls
      end
    end

    it "caches the result when the token is unchanged" do
      obj = klass.new
      obj.compute
      obj.compute
      expect(obj.call_count).to eq(1)
    end

    it "recomputes when the token changes" do
      obj = klass.new
      expect(obj.compute).to eq("result_v1")
      obj.version = 2
      expect(obj.compute).to eq("result_v2")
      expect(obj.call_count).to eq(2)
    end

    it "reverts to the cached value when the token returns to a prior value" do
      obj = klass.new
      obj.compute         # stores v1 result
      obj.version = 2
      obj.compute         # stores v2 result
      obj.version = 1
      obj.compute         # hits v1 cache entry
      expect(obj.call_count).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # Works with arguments
  # ---------------------------------------------------------------------------

  describe "with method arguments" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        attr_accessor :version

        def initialize = (@version = 1
                          @calls = 0)

        def fetch(id)
          @calls += 1
          "#{id}@v#{@version}"
        end
        memoize :fetch, cache_bust: -> { @version }

        def call_count = @calls
      end
    end

    it "caches per unique (args, token) combination" do
      obj = klass.new
      obj.fetch(1)
      obj.fetch(2)
      obj.fetch(1)
      expect(obj.call_count).to eq(2)
    end

    it "treats same args with different token as distinct entries" do
      obj = klass.new
      obj.fetch(1)
      obj.version = 2
      obj.fetch(1)
      expect(obj.call_count).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # Symbol form
  # ---------------------------------------------------------------------------

  describe "Symbol form (instance method name)" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        attr_accessor :rev

        def initialize = (@rev = 0
                          @calls = 0)

        def cache_version = @rev

        def data
          @calls += 1
          "v#{@rev}"
        end
        memoize :data, cache_bust: :cache_version

        def call_count = @calls
      end
    end

    it "calls the named instance method to obtain the token" do
      obj = klass.new
      obj.data
      obj.rev = 1
      obj.data
      expect(obj.call_count).to eq(2)
    end

    it "hits the cache when the version is unchanged" do
      obj = klass.new
      obj.data
      obj.data
      expect(obj.call_count).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Compound token (array)
  # ---------------------------------------------------------------------------

  describe "compound token" do
    it "incorporates multiple values into the version" do
      klass = Class.new do
        prepend SafeMemoize

        attr_accessor :v1, :v2

        def initialize = (@v1 = 1
                          @v2 = "a"
                          @calls = 0)

        def compute
          @calls += 1
        end
        memoize :compute, cache_bust: -> { [@v1, @v2] }

        def call_count = @calls
      end

      obj = klass.new
      obj.compute
      obj.v1 = 2
      obj.compute
      obj.v2 = "b"
      obj.compute
      expect(obj.call_count).to eq(3)
    end
  end

  # ---------------------------------------------------------------------------
  # Introspection transparency
  # ---------------------------------------------------------------------------

  describe "introspection" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        attr_accessor :version

        def initialize = (@version = 1)

        def value = 42
        memoize :value, cache_bust: -> { @version }
      end
    end

    it "memoized? returns true for the current token" do
      obj = klass.new
      obj.value
      expect(obj.memoized?(:value)).to be true
    end

    it "memoized? returns false after the token changes" do
      obj = klass.new
      obj.value
      obj.version = 2
      expect(obj.memoized?(:value)).to be false
    end

    it "memo_count counts all live versions" do
      obj = klass.new
      obj.value          # v1 entry
      obj.version = 2
      obj.value          # v2 entry
      expect(obj.memo_count(:value)).to eq(2)
    end

    it "reset_memo with no args clears all versions" do
      obj = klass.new
      obj.value
      obj.version = 2
      obj.value
      obj.reset_memo(:value)
      expect(obj.memo_count(:value)).to eq(0)
    end

    it "reset_all_memos clears all versions" do
      obj = klass.new
      obj.value
      obj.version = 2
      obj.value
      obj.reset_all_memos
      expect(obj.memo_count(:value)).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Composability
  # ---------------------------------------------------------------------------

  describe "composability" do
    it "composes with TTL — old token entries expire naturally" do
      klass = Class.new do
        prepend SafeMemoize

        attr_accessor :version

        def initialize = (@version = 1
                          @calls = 0)

        def data
          @calls += 1
        end
        memoize :data, cache_bust: -> { @version }, ttl: 0.01

        def call_count = @calls
      end

      obj = klass.new
      obj.data
      sleep(0.02)
      obj.data
      expect(obj.call_count).to eq(2)
    end

    it "composes with namespace:" do
      klass = Class.new do
        prepend SafeMemoize

        attr_accessor :version

        def initialize = (@version = 1
                          @calls = 0)

        def result
          @calls += 1
        end
        memoize :result, cache_bust: -> { @version }, namespace: "ns"

        def call_count = @calls
      end

      obj = klass.new
      obj.result
      obj.result
      expect(obj.call_count).to eq(1)
      obj.version = 2
      obj.result
      expect(obj.call_count).to eq(2)
    end

    it "composes with shared_cache: for cross-class busting" do
      calls = 0

      klass_a = Class.new do
        prepend SafeMemoize

        attr_reader :token

        def initialize(token) = (@token = token)

        define_method(:fetch) { calls += 1 }
        memoize :fetch, shared_cache: "bust_shared", cache_bust: -> { @token }
      end

      klass_b = Class.new do
        prepend SafeMemoize

        attr_reader :token

        def initialize(token) = (@token = token)

        define_method(:fetch) { calls += 1 }
        memoize :fetch, shared_cache: "bust_shared", cache_bust: -> { @token }
      end

      klass_a.new(1).fetch  # miss
      klass_b.new(1).fetch  # hit — same token
      expect(calls).to eq(1)

      klass_a.new(2).fetch  # miss — new token
      expect(calls).to eq(2)
    ensure
      SafeMemoize.reset_shared_caches!
    end
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

  describe "validation" do
    def bare_class
      Class.new {
        prepend SafeMemoize

        def x = 1
      }
    end

    it "raises ArgumentError for a non-callable, non-Symbol value" do
      expect { bare_class.memoize(:x, cache_bust: 42) }
        .to raise_error(ArgumentError, /callable or Symbol/)
    end

    it "raises ArgumentError when combined with key:" do
      expect { bare_class.memoize(:x, cache_bust: -> { 1 }, key: -> { 1 }) }
        .to raise_error(ArgumentError, /key:/)
    end
  end
end
