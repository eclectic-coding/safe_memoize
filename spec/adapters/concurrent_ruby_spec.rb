# frozen_string_literal: true

require "spec_helper"

CONCURRENT_RUBY_AVAILABLE = begin
  require "concurrent/map"
  require "concurrent/atomic/reentrant_read_write_lock"
  true
rescue LoadError
  false
end

RSpec.describe SafeMemoize::Adapters::ConcurrentRuby do
  before { skip "concurrent-ruby not available" unless CONCURRENT_RUBY_AVAILABLE }

  subject(:store) { described_class.new }

  let(:miss) { SafeMemoize::Stores::Base::MISS }

  describe "#read" do
    it "returns MISS for an absent key" do
      expect(store.read(:missing)).to be miss
    end

    it "returns a stored value" do
      store.write(:key, "hello")
      expect(store.read(:key)).to eq "hello"
    end

    it "returns nil when nil is cached" do
      store.write(:key, nil)
      expect(store.read(:key)).to be_nil
    end

    it "returns false when false is cached" do
      store.write(:key, false)
      expect(store.read(:key)).to be false
    end
  end

  describe "#write" do
    it "overwrites an existing entry" do
      store.write(:key, 1)
      store.write(:key, 2)
      expect(store.read(:key)).to eq 2
    end

    it "stores entries with different keys independently" do
      store.write(:a, "A")
      store.write(:b, "B")
      expect(store.read(:a)).to eq "A"
      expect(store.read(:b)).to eq "B"
    end
  end

  describe "TTL" do
    it "returns the value before expiry" do
      store.write(:key, "live", expires_in: 60)
      expect(store.read(:key)).to eq "live"
    end

    it "returns MISS after expiry" do
      store.write(:key, "dead", expires_in: 0.001)
      sleep 0.01
      expect(store.read(:key)).to be miss
    end

    it "never expires when expires_in is nil" do
      store.write(:key, "forever")
      expect(store.read(:key)).to eq "forever"
    end

    it "#exist? returns false for an expired entry" do
      store.write(:key, 42, expires_in: 0.001)
      sleep 0.01
      expect(store.exist?(:key)).to be false
    end
  end

  describe "#delete" do
    it "removes an entry" do
      store.write(:key, 42)
      store.delete(:key)
      expect(store.read(:key)).to be miss
    end

    it "is a no-op for a missing key" do
      expect { store.delete(:missing) }.not_to raise_error
    end
  end

  describe "#clear" do
    it "removes all entries" do
      store.write(:a, 1)
      store.write(:b, 2)
      store.clear
      expect(store.read(:a)).to be miss
      expect(store.read(:b)).to be miss
    end

    it "leaves the store usable after clearing" do
      store.write(:a, 1)
      store.clear
      store.write(:b, 2)
      expect(store.read(:b)).to eq 2
    end
  end

  describe "#keys" do
    it "returns an empty array for an empty store" do
      expect(store.keys).to eq []
    end

    it "returns all live keys" do
      store.write(:a, 1)
      store.write(:b, 2)
      expect(store.keys).to contain_exactly(:a, :b)
    end

    it "excludes expired keys" do
      store.write(:live, "yes", expires_in: 60)
      store.write(:dead, "no", expires_in: 0.001)
      sleep 0.01
      expect(store.keys).to eq [:live]
    end

    it "excludes deleted keys" do
      store.write(:a, 1)
      store.write(:b, 2)
      store.delete(:a)
      expect(store.keys).to eq [:b]
    end
  end

  describe "#exist?" do
    it "returns false for a missing key" do
      expect(store.exist?(:missing)).to be false
    end

    it "returns true for a live key" do
      store.write(:key, 42)
      expect(store.exist?(:key)).to be true
    end

    it "returns false for an expired key" do
      store.write(:key, 42, expires_in: 0.001)
      sleep 0.01
      expect(store.exist?(:key)).to be false
    end

    it "returns true when the cached value is nil" do
      store.write(:key, nil)
      expect(store.exist?(:key)).to be true
    end

    it "returns true when the cached value is false" do
      store.write(:key, false)
      expect(store.exist?(:key)).to be true
    end
  end

  describe "thread safety" do
    it "handles concurrent writes and reads without raising" do
      threads = 20.times.map do |i|
        Thread.new do
          store.write(i, i * 2)
          store.read(i)
        end
      end
      expect { threads.each(&:join) }.not_to raise_error
    end

    it "handles concurrent clears and writes without raising" do
      threads = []
      10.times { |i| threads << Thread.new { store.write(i, i) } }
      5.times { threads << Thread.new { store.clear } }
      expect { threads.each(&:join) }.not_to raise_error
    end

    it "allows multiple concurrent readers" do
      store.write(:shared, "value")
      mu = Mutex.new
      reads = []
      threads = 20.times.map do
        Thread.new do
          v = store.read(:shared)
          mu.synchronize { reads << v }
        end
      end
      threads.each(&:join)
      expect(reads).to all(eq("value"))
    end
  end

  describe "integration with SafeMemoize" do
    around { |ex| ex.run.tap { SafeMemoize.reset_configuration! } }

    let(:klass) do
      Class.new do
        prepend SafeMemoize

        self.safe_memoize_store = SafeMemoize::Adapters::ConcurrentRuby.new

        def self.name = "ConcurrentService"

        def work(x)
          x * 2
        end
        memoize :work
      end
    end

    it "caches method results" do
      obj = klass.new
      expect(obj.work(5)).to eq 10
      expect(obj.work(5)).to eq 10
    end

    it "caches nil and false correctly" do
      k = Class.new do
        prepend SafeMemoize

        self.safe_memoize_store = SafeMemoize::Adapters::ConcurrentRuby.new

        attr_reader :calls

        def initialize
          @calls = 0
        end

        def nilval
          @calls += 1
          nil
        end
        memoize :nilval
      end
      obj = k.new
      3.times { obj.nilval }
      expect(obj.calls).to eq 1
    end

    it "supports TTL via the store" do
      k = Class.new do
        prepend SafeMemoize

        self.safe_memoize_store = SafeMemoize::Adapters::ConcurrentRuby.new

        def fetch
          "result"
        end
        memoize :fetch, ttl: 0.01
      end
      obj = k.new
      expect(obj.fetch).to eq "result"
      sleep 0.02
      expect(obj.fetch).to eq "result"
    end

    it "works as a global default_store" do
      SafeMemoize.configure { |c| c.default_store = SafeMemoize::Adapters::ConcurrentRuby.new }
      k = Class.new do
        prepend SafeMemoize

        def self.name = "GlobalStoreService"

        def val = 42
        memoize :val
      end
      expect(k.new.val).to eq 42
    end

    it "raises ArgumentError when assigning a non-store object" do
      k = Class.new { prepend SafeMemoize }
      expect { k.safe_memoize_store = "not a store" }
        .to raise_error(ArgumentError, /Stores::Base/)
    end
  end

  describe "when concurrent-ruby is not available" do
    it "raises LoadError with an actionable message" do
      allow_any_instance_of(described_class).to receive(:require).and_raise(LoadError, "cannot load")
      expect { described_class.new }.to raise_error(LoadError, /concurrent-ruby/)
    end
  end
end
