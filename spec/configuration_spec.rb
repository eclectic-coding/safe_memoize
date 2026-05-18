# frozen_string_literal: true

RSpec.describe SafeMemoize do
  around do |example|
    example.run
  ensure
    SafeMemoize.reset_configuration!
  end

  describe ".configure" do
    it "yields the configuration object" do
      SafeMemoize.configure do |c|
        expect(c).to be_a(SafeMemoize::Configuration)
      end
    end

    it "applies default_ttl to memoized methods" do
      SafeMemoize.configure { |c| c.default_ttl = 0.05 }

      klass = Class.new do
        prepend SafeMemoize

        def value = rand

        memoize :value
      end

      obj = klass.new
      first = obj.value
      expect(obj.value).to eq(first)
      sleep(0.07)
      expect(obj.value).not_to eq(first)
    end

    it "applies default_max_size to memoized methods" do
      SafeMemoize.configure { |c| c.default_max_size = 2 }

      klass = Class.new do
        prepend SafeMemoize

        def find(id) = rand + id

        memoize :find
      end

      obj = klass.new
      obj.find(1)
      obj.find(2)
      obj.find(3)
      expect(obj.memo_count(:find)).to eq(2)
    end

    it "allows per-call options to override defaults" do
      SafeMemoize.configure { |c| c.default_ttl = 60 }

      klass = Class.new do
        prepend SafeMemoize

        def value = rand

        memoize :value, ttl: 0.05
      end

      obj = klass.new
      first = obj.value
      sleep(0.07)
      expect(obj.value).not_to eq(first)
    end

    it "does not affect classes defined before configure was called" do
      klass = Class.new do
        prepend SafeMemoize

        def value = rand

        memoize :value
      end

      SafeMemoize.configure { |c| c.default_ttl = 0.01 }

      obj = klass.new
      first = obj.value
      sleep(0.02)
      expect(obj.value).to eq(first)
    end
  end

  describe ".configuration" do
    it "returns the same object on repeated calls" do
      expect(SafeMemoize.configuration).to equal(SafeMemoize.configuration)
    end
  end

  describe ".reset_configuration!" do
    it "restores defaults to nil" do
      SafeMemoize.configure { |c| c.default_ttl = 30 }
      SafeMemoize.reset_configuration!
      expect(SafeMemoize.configuration.default_ttl).to be_nil
      expect(SafeMemoize.configuration.default_max_size).to be_nil
    end
  end
end
