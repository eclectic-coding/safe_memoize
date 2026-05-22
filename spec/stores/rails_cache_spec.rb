# frozen_string_literal: true

require "spec_helper"
require "safe_memoize/stores/rails_cache"

# Minimal ActiveSupport::Cache::Store stand-in for unit tests.
# Supports read, write (with expires_in:), delete, exist?, and delete_matched.
class FakeRailsCache
  def initialize
    @store = {}
    @expiries = {}
  end

  def read(key)
    return nil if expired?(key)

    @store.key?(key) ? @store[key] : nil
  end

  def write(key, value, expires_in: nil, **)
    @store[key] = value
    if expires_in
      @expiries[key] = Process.clock_gettime(Process::CLOCK_MONOTONIC) + expires_in
    else
      @expiries.delete(key)
    end
    true
  end

  def delete(key)
    @expiries.delete(key)
    @store.delete(key)
    true
  end

  def exist?(key)
    return false if expired?(key)

    @store.key?(key)
  end

  def delete_matched(pattern)
    keys_to_delete = @store.keys.select { |k| k.match?(pattern) }
    keys_to_delete.each { |k| delete(k) }
  end

  private

  def expired?(key)
    exp = @expiries[key]
    exp && exp <= Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

RSpec.describe SafeMemoize::Stores::RailsCache do
  subject(:store) { described_class.new(fake_cache) }

  let(:fake_cache) { FakeRailsCache.new }
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
      value = {a: [1, :sym, "str"], nested: {b: true}}
      store.write(:key, value)
      expect(store.read(:key)).to eq value
    end

    it "returns MISS for raw (untagged) data written directly to the cache" do
      fake_cache.write("tampered", "raw value")
      expect(store.read("tampered")).to be miss
    end
  end

  describe "#write" do
    it "makes the value retrievable" do
      store.write(:key, 42)
      expect(store.read(:key)).to eq 42
    end

    it "overwrites an existing entry" do
      store.write(:key, 1)
      store.write(:key, 2)
      expect(store.read(:key)).to eq 2
    end

    it "passes expires_in to the cache" do
      received_opts = {}
      allow(fake_cache).to receive(:write) { |_k, _v, **opts|
        received_opts = opts
        true
      }
      store.write(:key, 1, expires_in: 60)
      expect(received_opts[:expires_in]).to eq 60
    end

    it "does not pass expires_in when nil" do
      received_opts = nil
      allow(fake_cache).to receive(:write) { |_k, _v, **opts|
        received_opts = opts
        true
      }
      store.write(:key, 1, expires_in: nil)
      expect(received_opts).not_to have_key(:expires_in)
    end

    it "wraps the value in the sentinel envelope before writing" do
      tag = SafeMemoize::Stores::RailsCache::VALUE_TAG
      written_value = nil
      allow(fake_cache).to receive(:write) { |_k, v, **|
        written_value = v
        true
      }
      store.write(:key, 99)
      expect(written_value).to eq [tag, 99]
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

    it "does not remove entries in a different namespace" do
      other = described_class.new(fake_cache, namespace: "other")
      other.write(:x, 10)
      store.write(:y, 20)
      store.clear
      expect(other.read(:x)).to eq 10
    end

    it "is safe when the store is already empty" do
      expect { store.clear }.not_to raise_error
    end

    it "raises NotImplementedError when the backing store does not support delete_matched" do
      limited_cache = Object.new
      s = described_class.new(limited_cache)
      expect { s.clear }.to raise_error(NotImplementedError, /delete_matched/)
    end
  end

  # ---------------------------------------------------------------------------
  # keys / exist?
  # ---------------------------------------------------------------------------

  describe "#keys" do
    it "always returns an empty array" do
      store.write(:a, 1)
      store.write(:b, 2)
      expect(store.keys).to eq []
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

    it "returns true when the cached value is nil" do
      store.write(:key, nil)
      expect(store.exist?(:key)).to be true
    end

    it "returns true when the cached value is false" do
      store.write(:key, false)
      expect(store.exist?(:key)).to be true
    end

    it "returns false after the entry expires" do
      store.write(:key, 42, expires_in: 0.01)
      sleep 0.02
      expect(store.exist?(:key)).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # TTL (via FakeRailsCache's expires_in simulation)
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

    it "scopes keys so two stores on the same cache do not collide" do
      store_a = described_class.new(fake_cache, namespace: "ns_a")
      store_b = described_class.new(fake_cache, namespace: "ns_b")
      store_a.write(:x, 1)
      expect(store_b.read(:x)).to be miss
      expect(store_a.read(:x)).to eq 1
    end
  end

  # ---------------------------------------------------------------------------
  # End-to-end: integration with memoize store: option
  # ---------------------------------------------------------------------------

  describe "integration with memoize store:" do
    it "caches and retrieves values through the adapter" do
      s = described_class.new(fake_cache)
      klass = Class.new do
        prepend SafeMemoize

        def work(x) = x * 3
        memoize :work, store: s
      end
      obj = klass.new
      expect(obj.work(4)).to eq 12
      expect(obj.work(4)).to eq 12
    end

    it "computes only once when the same arguments are used" do
      s = described_class.new(fake_cache)
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

    it "caches nil correctly end-to-end" do
      s = described_class.new(fake_cache)
      calls = 0
      klass = Class.new do
        prepend SafeMemoize

        define_method(:nullable) do
          calls += 1
          nil
        end
        memoize :nullable, store: s
      end
      obj = klass.new
      expect(obj.nullable).to be_nil
      expect(obj.nullable).to be_nil
      expect(calls).to eq 1
    end

    it "respects TTL passed through memoize" do
      s = described_class.new(fake_cache)
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
