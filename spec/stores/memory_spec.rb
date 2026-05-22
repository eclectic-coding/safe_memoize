# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize::Stores::Memory do
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
  end
end
