# frozen_string_literal: true

require "spec_helper"

RSpec.describe SafeMemoize::Adapters::OpenTelemetry do
  around do |example|
    example.run
  ensure
    SafeMemoize.reset_configuration!
  end

  def stub_tracer
    t = instance_double("OpenTelemetry::Tracer")
    allow(t).to receive(:in_span) do |_name, **_opts, &block|
      block.call
    end
    t
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

  context "when opentelemetry_tracer is nil (default)" do
    it "does not call in_span" do
      tracer = stub_tracer
      expect(tracer).not_to receive(:in_span)
      klass.new.fetch(1)
    end
  end

  context "when opentelemetry_tracer is configured" do
    let(:tracer) { stub_tracer }

    before do
      SafeMemoize.configure { |c| c.opentelemetry_tracer = tracer }
    end

    it "calls in_span on a cache miss" do
      klass.new.fetch(1)
      expect(tracer).to have_received(:in_span)
    end

    it "does not call in_span on a cache hit" do
      obj = klass.new
      obj.fetch(1)
      expect(tracer).to have_received(:in_span).once
      obj.fetch(1)
      expect(tracer).to have_received(:in_span).once
    end

    it "uses the correct span name" do
      klass.new.fetch(1)
      expect(tracer).to have_received(:in_span).with("safe_memoize.compute", anything)
    end

    it "includes safe_memoize.method in attributes" do
      klass.new.fetch(1)
      expect(tracer).to have_received(:in_span).with(
        anything,
        hash_including(attributes: hash_including("safe_memoize.method" => "fetch"))
      )
    end

    it "includes safe_memoize.class in attributes" do
      klass.new.fetch(1)
      expect(tracer).to have_received(:in_span).with(
        anything,
        hash_including(attributes: hash_including("safe_memoize.class" => "TestService"))
      )
    end

    it "includes safe_memoize.cache_hit => false in attributes" do
      klass.new.fetch(1)
      expect(tracer).to have_received(:in_span).with(
        anything,
        hash_including(attributes: hash_including("safe_memoize.cache_hit" => false))
      )
    end

    it "returns the correct result through the span" do
      expect(klass.new.fetch(42)).to eq("result_42")
    end

    it "calls in_span once per unique argument combination" do
      obj = klass.new
      obj.fetch(1)
      obj.fetch(2)
      expect(tracer).to have_received(:in_span).twice
    end

    context "with the locked path (max_size:)" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          def self.name = "TestService"

          def compute(n)
            n * 2
          end
          memoize :compute, max_size: 5
        end
      end

      it "calls in_span on each unique cache miss" do
        obj = klass.new
        obj.compute(1)
        obj.compute(2)
        expect(tracer).to have_received(:in_span).twice
      end

      it "does not call in_span on a hit" do
        obj = klass.new
        obj.compute(1)
        obj.compute(1)
        expect(tracer).to have_received(:in_span).once
      end
    end

    context "with shared: true" do
      let(:klass) do
        Class.new do
          prepend SafeMemoize

          def self.name = "SharedService"

          def lookup(key)
            "value_#{key}"
          end
          memoize :lookup, shared: true
        end
      end

      after { klass.reset_all_shared_memos }

      it "calls in_span on a shared cache miss" do
        klass.new.lookup("a")
        expect(tracer).to have_received(:in_span)
      end

      it "does not call in_span on a shared cache hit" do
        klass.new.lookup("a")
        expect(tracer).to have_received(:in_span).once
        klass.new.lookup("a")
        expect(tracer).to have_received(:in_span).once
      end

      it "includes the class name in shared-path attributes" do
        klass.new.lookup("a")
        expect(tracer).to have_received(:in_span).with(
          anything,
          hash_including(attributes: hash_including("safe_memoize.class" => "SharedService"))
        )
      end
    end

    context "when the tracer does not respond to in_span" do
      let(:tracer) { Object.new }

      it "falls back to untraced execution and returns the correct result" do
        expect(klass.new.fetch(7)).to eq("result_7")
      end
    end
  end

  describe ".trace (unit)" do
    it "yields without tracing when tracer is nil" do
      called = false
      described_class.trace(nil, :fetch, "MyClass") { called = true }
      expect(called).to be true
    end

    it "yields through the span when tracer is present" do
      tracer = stub_tracer
      result = described_class.trace(tracer, :fetch, "MyClass") { 42 }
      expect(result).to eq(42)
    end

    it "propagates exceptions raised by the computation" do
      tracer = stub_tracer
      expect {
        described_class.trace(tracer, :fetch, "MyClass") { raise "boom" }
      }.to raise_error("boom")
    end
  end
end
