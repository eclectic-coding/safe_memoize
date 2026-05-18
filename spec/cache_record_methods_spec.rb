# frozen_string_literal: true

RSpec.describe SafeMemoize::CacheRecordMethods do
  let(:helper) do
    Class.new do
      include SafeMemoize::CacheRecordMethods

      public :memo_ttl
    end.new
  end

  describe "#memo_ttl" do
    context "when ttl is nil" do
      it "returns nil" do
        expect(helper.memo_ttl(nil)).to be_nil
      end
    end

    context "when ttl is a valid non-negative number" do
      it "returns a Float for an integer" do
        expect(helper.memo_ttl(10)).to eq(10.0)
      end

      it "returns the same Float for a float" do
        expect(helper.memo_ttl(1.5)).to eq(1.5)
      end

      it "returns 0.0 for zero" do
        expect(helper.memo_ttl(0)).to eq(0.0)
      end

      it "returns a Float for a numeric string" do
        expect(helper.memo_ttl("3.14")).to eq(3.14)
      end

      it "always returns a Float" do
        expect(helper.memo_ttl(5)).to be_a(Float)
      end
    end

    context "when ttl is negative" do
      it "raises ArgumentError for a negative integer" do
        expect { helper.memo_ttl(-1) }.to raise_error(ArgumentError, "ttl must be a non-negative number")
      end

      it "raises ArgumentError for a negative float" do
        expect { helper.memo_ttl(-0.1) }.to raise_error(ArgumentError, "ttl must be a non-negative number")
      end
    end

    context "when ttl is non-numeric" do
      it "raises ArgumentError for a non-numeric string" do
        expect { helper.memo_ttl("fast") }.to raise_error(ArgumentError, "ttl must be a non-negative number")
      end

      it "raises ArgumentError for an array" do
        expect { helper.memo_ttl([]) }.to raise_error(ArgumentError, "ttl must be a non-negative number")
      end

      it "raises ArgumentError for a symbol" do
        expect { helper.memo_ttl(:fast) }.to raise_error(ArgumentError, "ttl must be a non-negative number")
      end

      it "raises ArgumentError for a hash" do
        expect { helper.memo_ttl({}) }.to raise_error(ArgumentError, "ttl must be a non-negative number")
      end
    end
  end
end
