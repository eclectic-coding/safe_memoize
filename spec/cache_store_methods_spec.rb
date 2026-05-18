# frozen_string_literal: true

RSpec.describe SafeMemoize::CacheStoreMethods do
  let(:klass) do
    Class.new do
      prepend SafeMemoize

      def value
        42
      end

      memoize :value
    end
  end

  describe "#memo_cache_read (private)" do
    it "returns nil when the entry has not been cached yet" do
      obj = klass.new
      key = [:value, [], {}]
      expect(obj.send(:memo_cache_read, key)).to be_nil
    end

    it "returns the cached value when the entry is present and live" do
      obj = klass.new
      obj.value
      key = [:value, [], {}]
      expect(obj.send(:memo_cache_read, key)).to eq(42)
    end

    it "returns nil after the entry expires" do
      expired_klass = Class.new do
        prepend SafeMemoize

        def value
          99
        end

        memoize :value, ttl: 0.01
      end

      obj = expired_klass.new
      obj.value
      sleep(0.02)

      key = [:value, [], {}]
      expect(obj.send(:memo_cache_read, key)).to be_nil
    end
  end
end
