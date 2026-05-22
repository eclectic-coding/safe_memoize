# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize::Adapters::StatsD do
  around do |example|
    example.run
  ensure
    SafeMemoize.reset_configuration!
  end

  let(:client) { instance_double("StatsD", increment: nil) }

  let(:klass) do
    Class.new do
      prepend SafeMemoize

      def self.name = "TestService"

      def fetch(id)
        "result_#{id}"
      end
      memoize :fetch
    end
  end

  context "when statsd_client is nil (default)" do
    it "does not call increment" do
      expect(client).not_to receive(:increment)
      obj = klass.new
      obj.fetch(1)
      obj.fetch(1)
      obj.reset_memo(:fetch)
    end

    it "defaults to nil" do
      expect(SafeMemoize.configuration.statsd_client).to be_nil
    end
  end

  context "when statsd_client is configured" do
    before { SafeMemoize.configure { |c| c.statsd_client = client } }

    it "increments safe_memoize.miss on first call" do
      klass.new.fetch(1)
      expect(client).to have_received(:increment)
        .with("safe_memoize.miss", tags: ["method:fetch", "class:TestService"])
    end

    it "increments safe_memoize.store on first call" do
      klass.new.fetch(1)
      expect(client).to have_received(:increment)
        .with("safe_memoize.store", tags: ["method:fetch", "class:TestService"])
    end

    it "increments safe_memoize.hit on subsequent calls" do
      obj = klass.new
      obj.fetch(1)
      allow(client).to receive(:increment)
      obj.fetch(1)
      expect(client).to have_received(:increment)
        .with("safe_memoize.hit", tags: ["method:fetch", "class:TestService"])
    end

    it "increments safe_memoize.evict on reset_memo" do
      obj = klass.new
      obj.fetch(1)
      allow(client).to receive(:increment)
      obj.reset_memo(:fetch, 1)
      expect(client).to have_received(:increment)
        .with("safe_memoize.evict", tags: ["method:fetch", "class:TestService"])
    end

    it "increments safe_memoize.expire when a TTL entry is pruned" do
      ttl_klass = Class.new do
        prepend SafeMemoize

        def self.name = "TTLService"
        def fetch(id) = "value"
        memoize :fetch, ttl: 0.05
      end

      obj = ttl_klass.new
      obj.fetch(1)
      sleep(0.07)

      allow(client).to receive(:increment)
      obj.memo_count
      expect(client).to have_received(:increment)
        .with("safe_memoize.expire", tags: ["method:fetch", "class:TTLService"])
    end

    it "increments safe_memoize.store on warm_memo" do
      obj = klass.new
      allow(client).to receive(:increment)
      obj.warm_memo(:fetch, 1) { "warm" }
      expect(client).to have_received(:increment)
        .with("safe_memoize.store", tags: ["method:fetch", "class:TestService"])
    end

    it "includes the correct class name in tags" do
      named_klass = Class.new do
        prepend SafeMemoize

        def self.name = "MyNamedService"
        def compute = "val"
        memoize :compute
      end

      allow(client).to receive(:increment)
      named_klass.new.compute
      expect(client).to have_received(:increment)
        .with("safe_memoize.miss", tags: ["method:compute", "class:MyNamedService"])
    end

    it "emits a warning and does not raise when increment fails" do
      allow(client).to receive(:increment).and_raise(RuntimeError, "connection refused")
      expect { klass.new.fetch(1) }.to output(/StatsD dispatch error/).to_stderr
    end

    context "with shared: true memoization" do
      let(:shared_klass) do
        Class.new do
          prepend SafeMemoize

          def self.name = "SharedService"
          def fetch(id) = "shared_#{id}"
          memoize :fetch, shared: true
        end
      end

      after { shared_klass.reset_all_shared_memos }

      it "increments safe_memoize.miss on first call" do
        shared_klass.new.fetch(1)
        expect(client).to have_received(:increment)
          .with("safe_memoize.miss", tags: ["method:fetch", "class:SharedService"])
      end

      it "increments safe_memoize.hit on subsequent calls" do
        obj = shared_klass.new
        obj.fetch(1)
        allow(client).to receive(:increment)
        obj.fetch(1)
        expect(client).to have_received(:increment)
          .with("safe_memoize.hit", tags: ["method:fetch", "class:SharedService"])
      end
    end

    context "with the locked path (max_size:)" do
      let(:sized_klass) do
        Class.new do
          prepend SafeMemoize

          def self.name = "SizedService"
          def fetch(id) = "result_#{id}"
          memoize :fetch, max_size: 2
        end
      end

      it "increments safe_memoize.evict when LRU limit is exceeded" do
        obj = sized_klass.new
        obj.fetch(1)
        obj.fetch(2)
        allow(client).to receive(:increment)
        obj.fetch(3)
        expect(client).to have_received(:increment)
          .with("safe_memoize.evict", tags: ["method:fetch", "class:SizedService"])
      end
    end
  end

  describe ".dispatch" do
    it "is a no-op for unknown hook types" do
      expect { described_class.dispatch(client, :unknown_hook, [:fetch, [], {}], "Foo") }.not_to raise_error
      expect(client).not_to have_received(:increment)
    end
  end
end
