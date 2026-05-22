# frozen_string_literal: true

require "spec_helper"

# Ractor Compatibility Audit
#
# SafeMemoize is NOT Ractor-compatible in its current form. This spec
# documents the specific failure modes so regressions are visible if
# Ruby's Ractor semantics change or SafeMemoize is later redesigned.
#
# Root causes:
#
# 1. ClassMethods#memoize builds anonymous modules with define_method
#    blocks that close over local variables (ttl, max_size, condition,
#    klass, shared_mutex, …). Ruby marks those Procs as non-shareable,
#    so passing the host class into a Ractor raises RuntimeError
#    "defined with an un-shareable Proc in a different Ractor".
#
# 2. SafeMemoize.configuration reads @configuration from the SafeMemoize
#    module — a mutable ivar on a shared constant — which raises
#    Ractor::IsolationError from a non-main Ractor.
#
# 3. shared: true stores a class-level Mutex in the host class's ivar.
#    Mutexes are not Ractor-shareable.
#
# Workaround for users who need Ractor parallelism: perform all
# computation outside Ractors and send frozen results in via Ractor#send,
# or use Ruby Threads (which SafeMemoize fully supports).

# Ruby 4.0 redesigned the Ractor API and removed Ractor#take; the failure
# modes documented here are specific to the Ruby 3.x Ractor model.
RACTOR_SUPPORTED =
  defined?(Ractor) &&
  RUBY_VERSION >= "3.0.0" &&
  Ractor.method_defined?(:take)

RSpec.describe "SafeMemoize Ractor compatibility" do
  before { skip "Ractor not available on this Ruby" unless RACTOR_SUPPORTED }

  # Helper — run a block in a Ractor and return the error it raises,
  # or nil if it unexpectedly succeeds.
  def ractor_error(shareable_args, &block)
    Ractor.new(shareable_args, &block).take
    nil
  rescue Ractor::RemoteError => e
    e.cause
  rescue => e
    e
  end

  describe "per-instance memoization (fast path)" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        def compute = 42
        memoize :compute
      end
    end

    it "raises when the host class is passed into a Ractor" do
      err = ractor_error(klass) { |k| k.new.compute }
      expect(err).to be_a(RuntimeError)
      expect(err.message).to match(/un-shareable Proc/)
    end

    it "does not silently corrupt data — the error is explicit" do
      err = ractor_error(klass) { |k| k.new.compute }
      expect(err).not_to be_nil
    end
  end

  describe "locked path (max_size:)" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        def fetch(n) = n * 2
        memoize :fetch, max_size: 5
      end
    end

    it "raises when the host class is passed into a Ractor" do
      err = ractor_error(klass) { |k| k.new.fetch(1) }
      expect(err).to be_a(RuntimeError)
      expect(err.message).to match(/un-shareable Proc/)
    end
  end

  describe "SafeMemoize.configuration" do
    it "raises Ractor::IsolationError when read from a non-main Ractor" do
      err = ractor_error(nil) { SafeMemoize.configuration.active_support_notifications }
      expect(err).to be_a(Ractor::IsolationError)
    end
  end

  describe "shared: true" do
    let(:klass) do
      Class.new do
        prepend SafeMemoize

        def compute = 42
        memoize :compute, shared: true
      end
    end

    after {
      begin
        klass.reset_all_shared_memos
      rescue
        nil
      end
    }

    it "raises when the host class is passed into a Ractor" do
      err = ractor_error(klass) { |k| k.new.compute }
      expect(err).to be_a(RuntimeError)
      expect(err.message).to match(/un-shareable Proc/)
    end
  end
end
