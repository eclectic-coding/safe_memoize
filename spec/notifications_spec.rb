# frozen_string_literal: true

require "spec_helper"

# Minimal stub — avoids a hard activesupport dev dependency while allowing
# the integration to be exercised via RSpec message expectations.
unless defined?(ActiveSupport)
  module ActiveSupport
    module Notifications
      def self.instrument(event, payload = {})
        # no-op stub; individual examples override via allow(...).to receive
      end
    end
  end
end

RSpec.describe "SafeMemoize ActiveSupport::Notifications integration" do
  around do |example|
    example.run
  ensure
    SafeMemoize.reset_configuration!
  end

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

  context "when active_support_notifications is false (default)" do
    it "does not instrument any events" do
      expect(ActiveSupport::Notifications).not_to receive(:instrument)
      obj = klass.new
      obj.fetch(1)
      obj.fetch(1)
      obj.reset_memo(:fetch)
    end

    it "defaults to false" do
      expect(SafeMemoize.configuration.active_support_notifications).to be false
    end
  end

  context "when active_support_notifications is true" do
    before { SafeMemoize.configure { |c| c.active_support_notifications = true } }

    it "instruments cache_miss.safe_memoize on first call" do
      allow(ActiveSupport::Notifications).to receive(:instrument)
      klass.new.fetch(1)
      expect(ActiveSupport::Notifications).to have_received(:instrument)
        .with("cache_miss.safe_memoize", hash_including(method: :fetch))
    end

    it "instruments cache_store.safe_memoize on first call" do
      allow(ActiveSupport::Notifications).to receive(:instrument)
      klass.new.fetch(1)
      expect(ActiveSupport::Notifications).to have_received(:instrument)
        .with("cache_store.safe_memoize", hash_including(method: :fetch))
    end

    it "instruments cache_hit.safe_memoize on subsequent calls" do
      obj = klass.new
      obj.fetch(1)
      allow(ActiveSupport::Notifications).to receive(:instrument)
      obj.fetch(1)
      expect(ActiveSupport::Notifications).to have_received(:instrument)
        .with("cache_hit.safe_memoize", hash_including(method: :fetch))
    end

    it "instruments cache_evict.safe_memoize on reset_memo" do
      obj = klass.new
      obj.fetch(1)
      allow(ActiveSupport::Notifications).to receive(:instrument)
      obj.reset_memo(:fetch, 1)
      expect(ActiveSupport::Notifications).to have_received(:instrument)
        .with("cache_evict.safe_memoize", hash_including(method: :fetch))
    end

    it "instruments cache_expire.safe_memoize when a TTL entry is pruned" do
      ttl_klass = Class.new do
        prepend SafeMemoize

        def self.name = "TTLService"
        def fetch(id) = "value"
        memoize :fetch, ttl: 0.05
      end

      obj = ttl_klass.new
      obj.fetch(1)
      sleep(0.07)

      allow(ActiveSupport::Notifications).to receive(:instrument)
      obj.memo_count  # triggers memo_prune_expired_entries! which fires on_expire
      expect(ActiveSupport::Notifications).to have_received(:instrument)
        .with("cache_expire.safe_memoize", hash_including(method: :fetch))
    end

    it "instruments cache_store.safe_memoize on warm_memo" do
      obj = klass.new
      allow(ActiveSupport::Notifications).to receive(:instrument)
      obj.warm_memo(:fetch, 1) { "warm_value" }
      expect(ActiveSupport::Notifications).to have_received(:instrument)
        .with("cache_store.safe_memoize", hash_including(method: :fetch))
    end

    it "includes method, key, and class in the payload" do
      captured = {}
      allow(ActiveSupport::Notifications).to receive(:instrument) do |event, payload|
        captured[event] = payload
      end
      klass.new.fetch(42)

      miss_payload = captured["cache_miss.safe_memoize"]
      expect(miss_payload[:method]).to eq(:fetch)
      expect(miss_payload[:key]).to be_an(Array)
      expect(miss_payload[:class]).to eq("TestService")
    end

    it "does not fire when ActiveSupport::Notifications is not defined" do
      # Hide the constant to simulate the gem being absent
      stub_const("ActiveSupport::Notifications", nil)
      # Should not raise — the guard handles nil gracefully
      expect { klass.new.fetch(1) }.not_to raise_error
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

      it "instruments cache_miss.safe_memoize on first call" do
        allow(ActiveSupport::Notifications).to receive(:instrument)
        shared_klass.new.fetch(1)
        expect(ActiveSupport::Notifications).to have_received(:instrument)
          .with("cache_miss.safe_memoize", hash_including(method: :fetch))
      end

      it "instruments cache_hit.safe_memoize on subsequent calls" do
        obj = shared_klass.new
        obj.fetch(1)
        allow(ActiveSupport::Notifications).to receive(:instrument)
        obj.fetch(1)
        expect(ActiveSupport::Notifications).to have_received(:instrument)
          .with("cache_hit.safe_memoize", hash_including(method: :fetch))
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

      it "instruments cache_hit.safe_memoize on hit" do
        obj = sized_klass.new
        obj.fetch(1)
        allow(ActiveSupport::Notifications).to receive(:instrument)
        obj.fetch(1)
        expect(ActiveSupport::Notifications).to have_received(:instrument)
          .with("cache_hit.safe_memoize", hash_including(method: :fetch))
      end

      it "instruments cache_evict.safe_memoize when LRU limit is exceeded" do
        obj = sized_klass.new
        obj.fetch(1)
        obj.fetch(2)
        allow(ActiveSupport::Notifications).to receive(:instrument)
        obj.fetch(3)  # evicts entry for 1
        expect(ActiveSupport::Notifications).to have_received(:instrument)
          .with("cache_evict.safe_memoize", hash_including(method: :fetch))
      end
    end
  end
end
