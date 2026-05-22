# frozen_string_literal: true

require "spec_helper"
require "safe_memoize/rails"

RSpec.describe SafeMemoize::Rails::Middleware do
  def memoized_class
    Class.new do
      prepend SafeMemoize

      def data
        "computed"
      end
      memoize :data
    end
  end

  let(:ok_app) { ->(_env) { [200, {}, ["OK"]] } }
  let(:middleware) { described_class.new(ok_app) }

  around do |example|
    example.run
  ensure
    Thread.current[:safe_memoize_tracked] = nil
  end

  it "passes the call through to the inner app" do
    result = middleware.call({})
    expect(result).to eq([200, {}, ["OK"]])
  end

  it "resets a tracked instance after the request" do
    instance = memoized_class.new
    instance.data
    SafeMemoize::Rails.track(instance)
    expect(instance.memoized?(:data)).to be true

    middleware.call({})

    expect(instance.memoized?(:data)).to be false
  end

  it "clears the tracked list after the request" do
    SafeMemoize::Rails.track(memoized_class.new)

    middleware.call({})

    expect(Thread.current[:safe_memoize_tracked]).to eq([])
  end

  it "resets tracked instances even when the app raises" do
    raising_app = ->(_env) { raise "boom" }
    mid = described_class.new(raising_app)

    instance = memoized_class.new
    instance.data
    SafeMemoize::Rails.track(instance)

    expect { mid.call({}) }.to raise_error("boom")
    expect(instance.memoized?(:data)).to be false
  end

  it "resets multiple tracked instances" do
    klass = memoized_class
    a = klass.new
    b = klass.new
    a.data
    b.data
    SafeMemoize::Rails.track(a)
    SafeMemoize::Rails.track(b)

    middleware.call({})

    expect(a.memoized?(:data)).to be false
    expect(b.memoized?(:data)).to be false
  end

  it "is a no-op when nothing is tracked" do
    expect { middleware.call({}) }.not_to raise_error
  end
end

RSpec.describe SafeMemoize::Rails do
  def memoized_class
    Class.new do
      prepend SafeMemoize

      def data
        "computed"
      end
      memoize :data
    end
  end

  around do |example|
    example.run
  ensure
    Thread.current[:safe_memoize_tracked] = nil
  end

  describe ".track" do
    it "adds the instance to the thread-local list" do
      instance = memoized_class.new
      described_class.track(instance)
      expect(Thread.current[:safe_memoize_tracked]).to include(instance)
    end

    it "accumulates multiple instances" do
      klass = memoized_class
      a = klass.new
      b = klass.new
      described_class.track(a)
      described_class.track(b)
      expect(Thread.current[:safe_memoize_tracked]).to eq([a, b])
    end
  end

  describe ".reset_tracked!" do
    it "calls reset_all_memos on each tracked instance" do
      instance = memoized_class.new
      instance.data
      described_class.track(instance)

      described_class.reset_tracked!

      expect(instance.memoized?(:data)).to be false
    end

    it "clears the tracked list after reset" do
      described_class.track(memoized_class.new)

      described_class.reset_tracked!

      expect(Thread.current[:safe_memoize_tracked]).to eq([])
    end

    it "is safe to call with no tracked instances" do
      expect { described_class.reset_tracked! }.not_to raise_error
    end

    it "skips instances that do not respond to reset_all_memos" do
      described_class.track(Object.new)
      expect { described_class.reset_tracked! }.not_to raise_error
    end

    it "is thread-local — other threads' tracked instances are not reset" do
      klass = memoized_class
      instance = klass.new
      instance.data

      other_thread = Thread.new { described_class.track(instance) }
      other_thread.join

      described_class.reset_tracked!

      expect(instance.memoized?(:data)).to be true
    end
  end
end
