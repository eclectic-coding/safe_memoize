# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize::Stores::Base do
  subject(:store) { described_class.new }

  describe "abstract methods" do
    it "raises NotImplementedError on #read" do
      expect { store.read(:key) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on #write" do
      expect { store.write(:key, :value) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on #delete" do
      expect { store.delete(:key) }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on #clear" do
      expect { store.clear }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError on #keys" do
      expect { store.keys }.to raise_error(NotImplementedError)
    end
  end

  describe "#exist?" do
    it "returns false when read returns MISS" do
      allow(store).to receive(:read).and_return(SafeMemoize::Stores::Base::MISS)
      expect(store.exist?(:key)).to be false
    end

    it "returns true when read returns a value" do
      allow(store).to receive(:read).and_return(42)
      expect(store.exist?(:key)).to be true
    end

    it "returns true when read returns nil (a cacheable value)" do
      allow(store).to receive(:read).and_return(nil)
      expect(store.exist?(:key)).to be true
    end

    it "returns true when read returns false (a cacheable value)" do
      allow(store).to receive(:read).and_return(false)
      expect(store.exist?(:key)).to be true
    end
  end

  describe "MISS sentinel" do
    subject(:miss) { SafeMemoize::Stores::Base::MISS }

    it "is frozen" do
      expect(miss).to be_frozen
    end

    it "is distinct from nil" do
      expect(miss).not_to be_nil
    end

    it "is distinct from false" do
      expect(miss).not_to eq false
    end

    it "is distinct from zero" do
      expect(miss).not_to eq 0
    end

    it "is the same object every time (identity)" do
      expect(SafeMemoize::Stores::Base::MISS).to equal(miss)
    end
  end

  describe "concrete subclass inheriting from Base" do
    let(:simple_store) do
      miss = SafeMemoize::Stores::Base::MISS
      Class.new(described_class) do
        define_method(:initialize) { @h = {} }
        define_method(:read) { |key| @h.fetch(key, miss) }
        define_method(:write) { |key, value, expires_in: nil| @h[key] = value }
        define_method(:delete) { |key| @h.delete(key) }
        define_method(:clear) { @h.clear }
        define_method(:keys) { @h.keys }
      end.new
    end

    it "can write and read back a value" do
      simple_store.write(:x, 99)
      expect(simple_store.read(:x)).to eq 99
    end

    it "inherits #exist? from Base" do
      expect(simple_store.exist?(:x)).to be false
      simple_store.write(:x, "hello")
      expect(simple_store.exist?(:x)).to be true
    end

    it "correctly caches nil" do
      simple_store.write(:n, nil)
      expect(simple_store.read(:n)).to be_nil
      expect(simple_store.exist?(:n)).to be true
    end

    it "correctly caches false" do
      simple_store.write(:f, false)
      expect(simple_store.read(:f)).to be false
      expect(simple_store.exist?(:f)).to be true
    end
  end
end
