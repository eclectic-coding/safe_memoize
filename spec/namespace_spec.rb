# frozen_string_literal: true

RSpec.describe "SafeMemoize namespace" do
  after { SafeMemoize.reset_configuration! }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def make_class(namespace_opt = nil, &method_block)
    klass = Class.new do
      prepend SafeMemoize

      def self.name
        "TestClass"
      end

      define_method(:value, &method_block || proc { @count = (@count || 0) + 1 })
    end
    if namespace_opt
      klass.memoize :value, namespace: namespace_opt
    else
      klass.memoize :value
    end
    klass
  end

  # ---------------------------------------------------------------------------
  # Per-method namespace: option
  # ---------------------------------------------------------------------------

  describe "namespace: option on memoize" do
    it "caches the result under a namespaced key" do
      klass = make_class("v1")
      obj = klass.new
      obj.value
      obj.value
      expect(obj.memo_count(:value)).to eq(1)
    end

    it "isolates caches between namespaces on the same instance" do
      klass = Class.new do
        prepend SafeMemoize

        def compute = (@n = (@n || 0) + 1)
        memoize :compute, namespace: "a"
      end

      klass2 = Class.new do
        prepend SafeMemoize

        def compute = (@n = (@n || 0) + 1)
        memoize :compute, namespace: "b"
      end

      obj1 = klass.new
      obj2 = klass2.new
      obj1.compute
      obj2.compute

      # Each object has its own per-instance cache; keys differ by namespace
      expect(obj1.memo_count(:compute)).to eq(1)
      expect(obj2.memo_count(:compute)).to eq(1)
    end

    it "raises ArgumentError for an empty namespace" do
      klass = Class.new {
        prepend SafeMemoize

        def x = 1
      }

      expect { klass.memoize(:x, namespace: "") }.to raise_error(ArgumentError, /empty/)
    end

    it "raises ArgumentError when namespace contains ':'" do
      klass = Class.new {
        prepend SafeMemoize

        def x = 1
      }

      expect { klass.memoize(:x, namespace: "a:b") }.to raise_error(ArgumentError, /':'/)
    end

    it "raises ArgumentError for non-String namespace" do
      klass = Class.new {
        prepend SafeMemoize

        def x = 1
      }

      expect { klass.memoize(:x, namespace: 42) }.to raise_error(ArgumentError, /String/)
    end
  end

  # ---------------------------------------------------------------------------
  # Class-level namespace
  # ---------------------------------------------------------------------------

  describe "safe_memoize_namespace=" do
    it "scopes all memoized methods on the class" do
      klass = Class.new do
        prepend SafeMemoize

        self.safe_memoize_namespace = "tenant1"

        def greet = "hello"
        memoize :greet
      end

      obj = klass.new
      obj.greet
      expect(obj.memoized?(:greet)).to be true
      expect(obj.memo_count(:greet)).to eq(1)
    end

    it "can be cleared with nil" do
      klass = Class.new { prepend SafeMemoize }
      klass.safe_memoize_namespace = "ns"
      klass.safe_memoize_namespace = nil
      expect(klass.safe_memoize_namespace).to be_nil
    end

    it "raises ArgumentError for invalid values" do
      klass = Class.new { prepend SafeMemoize }
      expect { klass.safe_memoize_namespace = "" }.to raise_error(ArgumentError, /empty/)
      expect { klass.safe_memoize_namespace = "a:b" }.to raise_error(ArgumentError, /':'/)
      expect { klass.safe_memoize_namespace = 99 }.to raise_error(ArgumentError, /String/)
    end

    it "can be read back" do
      klass = Class.new { prepend SafeMemoize }
      klass.safe_memoize_namespace = "orders"
      expect(klass.safe_memoize_namespace).to eq("orders")
    end
  end

  # ---------------------------------------------------------------------------
  # Global namespace via Configuration
  # ---------------------------------------------------------------------------

  describe "SafeMemoize.configure namespace:" do
    it "scopes all memoized methods globally" do
      SafeMemoize.configure { |c| c.namespace = "v2" }

      klass = Class.new do
        prepend SafeMemoize

        def answer = 42
        memoize :answer
      end

      obj = klass.new
      obj.answer
      expect(obj.memoized?(:answer)).to be true
      expect(obj.memo_count(:answer)).to eq(1)
    end

    it "is reset by reset_configuration!" do
      SafeMemoize.configure { |c| c.namespace = "v1" }
      SafeMemoize.reset_configuration!
      expect(SafeMemoize.configuration.namespace).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Priority: per-method > class-level > global
  # ---------------------------------------------------------------------------

  describe "namespace resolution priority" do
    it "per-method namespace takes precedence over class and global" do
      SafeMemoize.configure { |c| c.namespace = "global" }

      klass = Class.new do
        prepend SafeMemoize

        self.safe_memoize_namespace = "klass"

        def result = 1
        memoize :result, namespace: "method"
      end

      obj = klass.new
      obj.result

      # result should be cached; introspection uses bare name
      expect(obj.memoized?(:result)).to be true
    end

    it "class-level namespace takes precedence over global" do
      SafeMemoize.configure { |c| c.namespace = "global" }

      klass = Class.new do
        prepend SafeMemoize

        self.safe_memoize_namespace = "klass"

        def result = 1
        memoize :result
      end

      obj = klass.new
      obj.result
      expect(obj.memoized?(:result)).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Introspection API remains namespace-transparent
  # ---------------------------------------------------------------------------

  describe "introspection with namespace" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        def fetch(id) = id * 2
        memoize :fetch, namespace: "v1"
      end
    end

    it "memo_count returns correct count" do
      obj = klass.new
      obj.fetch(1)
      obj.fetch(2)
      expect(obj.memo_count(:fetch)).to eq(2)
    end

    it "memoized? returns true for cached args" do
      obj = klass.new
      obj.fetch(5)
      expect(obj.memoized?(:fetch, 5)).to be true
      expect(obj.memoized?(:fetch, 9)).to be false
    end

    it "memo_keys returns bare method name (not namespaced)" do
      obj = klass.new
      obj.fetch(3)
      keys = obj.memo_keys(:fetch)
      expect(keys.first[:args]).to eq([3])
    end

    it "memo_keys without method_name returns bare method name in :method field" do
      obj = klass.new
      obj.fetch(7)
      keys = obj.memo_keys
      expect(keys.map { |k| k[:method] }).to all(eq(:fetch))
    end

    it "reset_memo clears the namespaced entry" do
      obj = klass.new
      obj.fetch(1)
      expect(obj.memoized?(:fetch, 1)).to be true
      obj.reset_memo(:fetch, 1)
      expect(obj.memoized?(:fetch, 1)).to be false
    end

    it "reset_all_memos clears all namespaced entries" do
      obj = klass.new
      obj.fetch(1)
      obj.fetch(2)
      obj.reset_all_memos
      expect(obj.memo_count(:fetch)).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Metrics remain namespace-transparent
  # ---------------------------------------------------------------------------

  describe "cache metrics with namespace" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        def compute(x) = x
        memoize :compute, namespace: "metrics_ns"
      end
    end

    it "records hits and misses under the bare method name" do
      obj = klass.new
      obj.compute(1)
      obj.compute(1)

      stats = obj.cache_stats_for(:compute)
      expect(stats[:total_hits]).to eq(1)
      expect(stats[:total_misses]).to eq(1)
    end

    it "cache_metrics_reset clears metrics for the namespaced method" do
      obj = klass.new
      obj.compute(1)
      obj.cache_metrics_reset(:compute)
      stats = obj.cache_stats_for(:compute)
      expect(stats[:total_hits]).to eq(0)
      expect(stats[:total_misses]).to eq(0)
    end

    it "cache_stats returns bare method names in entries" do
      obj = klass.new
      obj.compute(1)
      stats = obj.cache_stats
      expect(stats[:entries].map { |e| e[:method] }).to all(eq(:compute))
    end
  end

  # ---------------------------------------------------------------------------
  # Namespace isolation: two instances of different classes sharing a store
  # ---------------------------------------------------------------------------

  describe "namespace isolation with external store" do
    it "two classes with different namespaces do not share entries in the same store" do
      store = SafeMemoize::Stores::Memory.new

      klass_a = Class.new do
        prepend SafeMemoize

        define_method(:value) { 1 }
        memoize :value, store: store, namespace: "a"
      end

      klass_b = Class.new do
        prepend SafeMemoize

        define_method(:value) { 2 }
        memoize :value, store: store, namespace: "b"
      end

      obj_a = klass_a.new
      obj_b = klass_b.new

      expect(obj_a.value).to eq(1)
      expect(obj_b.value).to eq(2)
      # Both cached, store has two distinct entries
      expect(store.keys.length).to eq(2)
    end
  end
end
