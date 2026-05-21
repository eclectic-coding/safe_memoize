# frozen_string_literal: true

RSpec.describe "Key serialization safety" do
  let(:klass) do
    Class.new do
      prepend SafeMemoize

      attr_reader :call_count

      def initialize
        @call_count = 0
      end

      def greet(name)
        @call_count += 1
        "hello #{name}"
      end

      def lookup(options)
        @call_count += 1
        options[:value]
      end

      def join(items)
        @call_count += 1
        items.join(", ")
      end

      memoize :greet
      memoize :lookup
      memoize :join
    end
  end

  describe "string argument mutation" do
    it "still hits the cache after the caller mutates the string argument" do
      obj = klass.new
      name = +"alice"
      obj.greet(name)

      name << " (modified)"

      expect(obj.greet("alice")).to eq("hello alice")
      expect(obj.call_count).to eq(1)
    end

    it "treats a mutated string as a distinct cache key" do
      obj = klass.new
      name = +"alice"
      obj.greet(name)

      name.replace("bob")

      expect(obj.greet("bob")).to eq("hello bob")
      expect(obj.call_count).to eq(2)
    end
  end

  describe "hash argument mutation" do
    it "still hits the cache after the caller mutates a hash value" do
      obj = klass.new
      opts = {value: 42}
      obj.lookup(opts)

      opts[:value] = 99

      expect(obj.lookup({value: 42})).to eq(42)
      expect(obj.call_count).to eq(1)
    end
  end

  describe "array argument mutation" do
    it "still hits the cache after the caller mutates the array" do
      obj = klass.new
      items = %w[a b]
      obj.join(items)

      items << "c"

      expect(obj.join(%w[a b])).to eq("a, b")
      expect(obj.call_count).to eq(1)
    end
  end

  describe "frozen arguments" do
    it "handles frozen strings without error" do
      obj = klass.new
      expect(obj.greet("alice")).to eq("hello alice")
      expect(obj.greet("alice")).to eq("hello alice")
      expect(obj.call_count).to eq(1)
    end

    it "handles frozen hashes without error" do
      obj = klass.new
      opts = {value: 1}.freeze
      expect(obj.lookup(opts)).to eq(1)
      expect(obj.lookup(opts)).to eq(1)
      expect(obj.call_count).to eq(1)
    end
  end

  describe "cache keys are frozen" do
    it "stores a frozen args copy in the cache key" do
      obj = klass.new
      obj.greet("alice")

      cache_key = obj.send(:safe_memo_cache_key, :greet, ["alice"], {})
      expect(cache_key[1]).to be_frozen
    end

    it "stores a frozen kwargs copy in the cache key" do
      obj = klass.new
      obj.greet("alice")

      cache_key = obj.send(:safe_memo_cache_key, :greet, ["alice"], {})
      expect(cache_key[2]).to be_frozen
    end

    it "deep-freezes nested strings inside args" do
      obj = klass.new
      cache_key = obj.send(:safe_memo_cache_key, :join, [%w[a b]], {})
      expect(cache_key[1].first).to be_an(Array)
      expect(cache_key[1].first).to be_frozen
      cache_key[1].first.each { |s| expect(s).to be_frozen }
    end
  end

  describe "original arguments are not mutated" do
    it "does not freeze the caller's original string" do
      obj = klass.new
      name = +"alice"
      obj.greet(name)
      expect(name).not_to be_frozen
    end

    it "does not freeze the caller's original array" do
      obj = klass.new
      items = %w[a b]
      obj.join(items)
      expect(items).not_to be_frozen
    end

    it "does not freeze the caller's original hash argument" do
      obj = klass.new
      opts = {value: 1}
      obj.lookup(opts)
      expect(opts).not_to be_frozen
    end
  end
end
