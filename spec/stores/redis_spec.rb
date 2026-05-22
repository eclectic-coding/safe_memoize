# frozen_string_literal: true

require "spec_helper"
require "safe_memoize/stores/redis"

# Minimal in-memory Redis stand-in. Supports get, set (with EX), del, and
# scan_each — the only four methods the adapter calls.
class FakeRedis
  def initialize
    @store = {}
    @expiries = {}
  end

  def get(key)
    return nil if expired?(key)

    @store[key]
  end

  def set(key, value, px: nil, ex: nil, **)
    @store[key] = value
    ttl_seconds = if px
      px / 1000.0
    elsif ex
      ex.to_f
    end
    @expiries[key] = Process.clock_gettime(Process::CLOCK_MONOTONIC) + ttl_seconds if ttl_seconds
    "OK"
  end

  def del(*keys)
    keys.flatten.sum do |k|
      @expiries.delete(k)
      @store.delete(k) ? 1 : 0
    end
  end

  def scan_each(match: "*", &block)
    pattern = Regexp.new("\\A#{Regexp.escape(match).gsub("\\*", ".*")}\\z")
    @store.each_key do |k|
      next if expired?(k)
      next unless k.match?(pattern)

      block.call(k)
    end
  end

  private

  def expired?(key)
    exp = @expiries[key]
    exp && exp <= Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

RSpec.describe SafeMemoize::Stores::Redis do
  subject(:store) { described_class.new(fake_redis) }

  let(:fake_redis) { FakeRedis.new }
  let(:miss) { SafeMemoize::Stores::Base::MISS }

  # ---------------------------------------------------------------------------
  # read / write round-trip
  # ---------------------------------------------------------------------------

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

    it "handles complex Ruby objects" do
      value = {a: [1, :sym, "str"], b: 3.14}
      store.write(:key, value)
      expect(store.read(:key)).to eq value
    end
  end

  describe "#write" do
    it "makes the value readable" do
      store.write(:key, 42)
      expect(store.read(:key)).to eq 42
    end

    it "overwrites an existing entry" do
      store.write(:key, 1)
      store.write(:key, 2)
      expect(store.read(:key)).to eq 2
    end

    it "passes expires_in as PX (milliseconds, rounded up) to Redis" do
      received_opts = {}
      allow(fake_redis).to receive(:set) { |_k, _v, **opts| received_opts = opts }
      store.write(:key, 1, expires_in: 30)
      expect(received_opts[:px]).to eq 30_000
    end

    it "rounds sub-millisecond TTLs up to at least 1 ms" do
      received_opts = {}
      allow(fake_redis).to receive(:set) { |_k, _v, **opts| received_opts = opts }
      store.write(:key, 1, expires_in: 0.0001)
      expect(received_opts[:px]).to eq 1
    end

    it "does not send PX when expires_in is nil" do
      received_opts = nil
      allow(fake_redis).to receive(:set) { |_k, _v, **opts| received_opts = opts }
      store.write(:key, 1, expires_in: nil)
      expect(received_opts).not_to have_key(:px)
    end
  end

  # ---------------------------------------------------------------------------
  # delete / clear
  # ---------------------------------------------------------------------------

  describe "#delete" do
    it "removes a stored entry" do
      store.write(:key, 99)
      store.delete(:key)
      expect(store.read(:key)).to be miss
    end

    it "is a no-op for a missing key" do
      expect { store.delete(:absent) }.not_to raise_error
    end
  end

  describe "#clear" do
    it "removes all entries in the namespace" do
      store.write(:a, 1)
      store.write(:b, 2)
      store.clear
      expect(store.read(:a)).to be miss
      expect(store.read(:b)).to be miss
    end

    it "does not remove keys in a different namespace" do
      other = described_class.new(fake_redis, namespace: "other")
      other.write(:x, 10)
      store.write(:y, 20)
      store.clear
      expect(other.read(:x)).to eq 10
    end

    it "is safe when the store is already empty" do
      expect { store.clear }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # keys / exist?
  # ---------------------------------------------------------------------------

  describe "#keys" do
    it "returns an empty array for an empty store" do
      expect(store.keys).to eq []
    end

    it "returns all stored keys deserialized back to Ruby objects" do
      store.write(:a, 1)
      store.write(:b, 2)
      expect(store.keys).to contain_exactly(:a, :b)
    end

    it "handles the standard SafeMemoize key format (3-element array)" do
      key = [:compute, [1, 2], {opt: true}]
      store.write(key, 3)
      expect(store.keys).to contain_exactly(key)
    end

    it "excludes keys from other namespaces" do
      other = described_class.new(fake_redis, namespace: "other")
      other.write(:foreign, 0)
      store.write(:local, 1)
      expect(store.keys).to contain_exactly(:local)
    end
  end

  describe "#exist?" do
    it "returns false for a missing key" do
      expect(store.exist?(:missing)).to be false
    end

    it "returns true for a stored key" do
      store.write(:key, 42)
      expect(store.exist?(:key)).to be true
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

  # ---------------------------------------------------------------------------
  # TTL (via FakeRedis's EX simulation)
  # ---------------------------------------------------------------------------

  describe "TTL expiry" do
    it "expires entries after the TTL" do
      store.write(:key, "gone", expires_in: 0.01)
      sleep 0.02
      expect(store.read(:key)).to be miss
    end

    it "does not expire entries with no TTL" do
      store.write(:key, "forever")
      expect(store.read(:key)).to eq "forever"
    end
  end

  # ---------------------------------------------------------------------------
  # Namespace
  # ---------------------------------------------------------------------------

  describe "namespace" do
    it "defaults to 'safe_memoize'" do
      expect(store.instance_variable_get(:@namespace)).to eq "safe_memoize"
    end

    it "accepts a custom namespace" do
      custom = described_class.new(fake_redis, namespace: "myapp:cache")
      custom.write(:k, 1)
      expect(store.read(:k)).to be miss
      expect(custom.read(:k)).to eq 1
    end
  end

  # ---------------------------------------------------------------------------
  # End-to-end: integration with memoize store: option
  # ---------------------------------------------------------------------------

  describe "integration with memoize store:" do
    it "caches and retrieves values through the adapter" do
      s = described_class.new(fake_redis)
      klass = Class.new do
        prepend SafeMemoize

        def work(x) = x * 2
        memoize :work, store: s
      end
      obj = klass.new
      expect(obj.work(5)).to eq 10
      expect(obj.work(5)).to eq 10
      expect(s.read([:work, [5], {}])).to eq 10
    end

    it "computes only once when the same arguments are used" do
      s = described_class.new(fake_redis)
      count = 0
      klass = Class.new do
        prepend SafeMemoize

        define_method(:work) do
          count += 1
          count
        end
        memoize :work, store: s
      end
      klass.new.work
      klass.new.work
      expect(count).to eq 1
    end

    it "respects TTL passed through memoize" do
      s = described_class.new(fake_redis)
      klass = Class.new do
        prepend SafeMemoize

        def slow = "result"
        memoize :slow, store: s, ttl: 0.01
      end
      obj = klass.new
      obj.slow
      sleep 0.02
      expect(s.read([:slow, [], {}])).to be miss
    end
  end
end
