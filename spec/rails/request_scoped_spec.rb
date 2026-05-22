# frozen_string_literal: true

require "spec_helper"
require "safe_memoize/rails"

RSpec.describe SafeMemoize::Rails::RequestScoped do
  def memoized_class
    Class.new do
      prepend SafeMemoize

      def data
        "computed"
      end
      memoize :data
    end
  end

  describe "included in a controller-like class (responds to after_action)" do
    let(:klass) do
      k = memoized_class
      after_actions = []
      k.define_singleton_method(:after_action) { |sym| after_actions << sym }
      k.define_singleton_method(:registered_after_actions) { after_actions }
      k.include(described_class)
      k
    end

    it "registers :reset_all_memos as an after_action" do
      expect(klass.registered_after_actions).to include(:reset_all_memos)
    end

    it "provides reset_request_memos on instances" do
      expect(klass.new).to respond_to(:reset_request_memos)
    end

    it "reset_request_memos clears the instance cache" do
      instance = klass.new
      instance.data
      expect(instance.memoized?(:data)).to be true
      instance.reset_request_memos
      expect(instance.memoized?(:data)).to be false
    end
  end

  describe "included in a plain class (no after_action)" do
    let(:klass) do
      k = memoized_class
      k.include(described_class)
      k
    end

    it "does not raise during inclusion" do
      expect { klass }.not_to raise_error
    end

    it "still provides reset_request_memos" do
      expect(klass.new).to respond_to(:reset_request_memos)
    end

    it "reset_request_memos clears the instance cache" do
      instance = klass.new
      instance.data
      expect(instance.memoized?(:data)).to be true
      instance.reset_request_memos
      expect(instance.memoized?(:data)).to be false
    end

    it "does not add after_action to the class" do
      expect(klass).not_to respond_to(:after_action)
    end
  end
end
