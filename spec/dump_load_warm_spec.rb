# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize do
  let(:test_class) do
    Class.new do
      prepend SafeMemoize

      def current_user
        rand
      end

      def find(id)
        rand + id
      end

      def search(query, page: 1)
        rand
      end

      memoize :current_user
      memoize :find
      memoize :search
    end
  end

  describe "#warm_memo" do
    it "pre-populates the cache without calling the method" do
      call_count = 0
      klass = Class.new do
        prepend SafeMemoize

        define_method(:value) { call_count += 1 }
        memoize :value
      end

      instance = klass.new
      instance.warm_memo(:value) { 42 }

      expect(instance.value).to eq(42)
      expect(call_count).to eq(0)
    end

    it "returns the value from the block" do
      instance = test_class.new
      result = instance.warm_memo(:current_user) { 99 }
      expect(result).to eq(99)
    end

    it "warms per unique argument combination" do
      instance = test_class.new
      instance.warm_memo(:find, 1) { "user_1" }
      instance.warm_memo(:find, 2) { "user_2" }

      expect(instance.find(1)).to eq("user_1")
      expect(instance.find(2)).to eq("user_2")
    end

    it "warms entries with keyword arguments" do
      instance = test_class.new
      instance.warm_memo(:search, "ruby", page: 2) { "page 2 results" }

      expect(instance.search("ruby", page: 2)).to eq("page 2 results")
      expect(instance.search("ruby", page: 1)).not_to eq("page 2 results")
    end

    it "overwrites an existing cached entry" do
      instance = test_class.new
      instance.current_user
      instance.warm_memo(:current_user) { "override" }

      expect(instance.current_user).to eq("override")
    end

    it "raises ArgumentError without a block" do
      instance = test_class.new
      expect { instance.warm_memo(:current_user) }.to raise_error(ArgumentError, /block required/)
    end

    it "marks the entry as memoized" do
      instance = test_class.new
      expect(instance.memoized?(:current_user)).to be false
      instance.warm_memo(:current_user) { "warmed" }
      expect(instance.memoized?(:current_user)).to be true
    end
  end

  describe "#dump_memo" do
    it "returns an empty hash when nothing is cached" do
      instance = test_class.new
      expect(instance.dump_memo).to eq({})
    end

    it "exports all cached entries as {cache_key => value}" do
      instance = test_class.new
      instance.find(1)
      instance.find(2)

      dump = instance.dump_memo
      expect(dump.size).to eq(2)
      expect(dump.keys).to all(be_a(Array))
      dump.each_key { |key| expect(key[0]).to eq(:find) }
    end

    it "exports the actual cached values, not record wrappers" do
      instance = test_class.new
      instance.warm_memo(:current_user) { "expected_value" }

      dump = instance.dump_memo
      expect(dump.values).to include("expected_value")
      dump.each_value { |v| expect(v).not_to be_a(Hash) }
    end

    it "scopes the dump to a single method when given a method name" do
      instance = test_class.new
      instance.current_user
      instance.find(1)
      instance.find(2)

      dump = instance.dump_memo(:find)
      expect(dump.size).to eq(2)
      dump.each_key { |key| expect(key[0]).to eq(:find) }
    end

    it "returns an empty hash for a method with no cached entries" do
      instance = test_class.new
      instance.current_user
      expect(instance.dump_memo(:find)).to eq({})
    end

    it "excludes expired entries" do
      klass = Class.new do
        prepend SafeMemoize

        def value = rand
        memoize :value, ttl: 0.1
      end

      instance = klass.new
      instance.value
      sleep(0.15)

      expect(instance.dump_memo).to eq({})
    end
  end

  describe "#load_memo" do
    it "restores cached entries from a dump" do
      source = test_class.new
      source.warm_memo(:find, 1) { "user_1" }
      source.warm_memo(:find, 2) { "user_2" }

      target = test_class.new
      call_count = 0
      allow(target).to receive(:find).and_wrap_original do |original, *args|
        call_count += 1
        original.call(*args)
      end

      target.load_memo(source.dump_memo)

      expect(target.find(1)).to eq("user_1")
      expect(target.find(2)).to eq("user_2")
    end

    it "does not overwrite entries not present in the snapshot" do
      instance = test_class.new
      instance.warm_memo(:current_user) { "existing" }

      instance.load_memo({[:find, [1], {}] => "loaded_user"})

      expect(instance.current_user).to eq("existing")
      expect(instance.find(1)).to eq("loaded_user")
    end

    it "overwrites existing entries with snapshot values" do
      instance = test_class.new
      instance.warm_memo(:current_user) { "old" }

      instance.load_memo({[:current_user, [], {}] => "new"})

      expect(instance.current_user).to eq("new")
    end

    it "returns nil" do
      instance = test_class.new
      expect(instance.load_memo({})).to be_nil
    end

    it "raises ArgumentError when given a non-Hash" do
      instance = test_class.new
      expect { instance.load_memo("not a hash") }.to raise_error(ArgumentError, /Hash/)
    end

    it "round-trips through dump and load" do
      source = test_class.new
      source.warm_memo(:find, 1) { "user_1" }
      source.warm_memo(:find, 2) { "user_2" }
      source.warm_memo(:current_user) { "me" }

      target = test_class.new
      target.load_memo(source.dump_memo)

      expect(target.find(1)).to eq("user_1")
      expect(target.find(2)).to eq("user_2")
      expect(target.current_user).to eq("me")
    end

    it "loaded entries are visible via memoized? and memo_count" do
      instance = test_class.new
      instance.load_memo({[:find, [42], {}] => "loaded"})

      expect(instance.memoized?(:find, 42)).to be true
      expect(instance.memo_count(:find)).to eq(1)
    end
  end
end
