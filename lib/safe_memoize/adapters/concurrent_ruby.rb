# frozen_string_literal: true

module SafeMemoize
  module Adapters
    # Optional store adapter backed by +concurrent-ruby+.
    #
    # Replaces the default +Mutex+-guarded +Hash+ with +Concurrent::Map+ and
    # +Concurrent::ReentrantReadWriteLock+. Multiple readers proceed in parallel;
    # writers still get exclusive access. For hot paths with many concurrent readers
    # this can meaningfully reduce lock contention compared to {Stores::Memory}.
    #
    # Opt in per class:
    #
    #   class MyService
    #     prepend SafeMemoize
    #     self.safe_memoize_store = SafeMemoize::Adapters::ConcurrentRuby.new
    #   end
    #
    # Or globally via {SafeMemoize.configure}:
    #
    #   SafeMemoize.configure do |c|
    #     c.default_store = SafeMemoize::Adapters::ConcurrentRuby.new
    #   end
    #
    # Requires the +concurrent-ruby+ gem, which is *not* a runtime dependency of
    # +safe_memoize+. Add it to your own Gemfile or gemspec:
    #
    #   gem "concurrent-ruby"
    #
    # A {LoadError} with an actionable message is raised at instantiation time if
    # the gem is not available.
    class ConcurrentRuby < Stores::Base
      def initialize
        require "concurrent/map"
        require "concurrent/atomic/reentrant_read_write_lock"
        @data = Concurrent::Map.new
        @lock = Concurrent::ReentrantReadWriteLock.new
      rescue LoadError
        raise LoadError,
          "SafeMemoize::Adapters::ConcurrentRuby requires the concurrent-ruby gem. " \
          "Add `gem 'concurrent-ruby'` to your Gemfile."
      end

      # @param key [Object]
      # @return [Object] the stored value, or {MISS} if absent or expired
      def read(key)
        @lock.with_read_lock do
          entry = @data[key]
          return MISS unless entry
          return MISS if expired?(entry)

          entry[:value]
        end
      end

      # @param key [Object]
      # @param value [Object]
      # @param expires_in [Numeric, nil] seconds until expiry; +nil+ means no expiry
      # @return [void]
      def write(key, value, expires_in: nil)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expires_at = expires_in ? now + expires_in.to_f : nil
        @lock.with_write_lock do
          @data[key] = {value: value, expires_at: expires_at, cached_at: now}
        end
      end

      # @param key [Object]
      # @return [void]
      def delete(key)
        @lock.with_write_lock { @data.delete(key) }
      end

      # @return [void]
      def clear
        @lock.with_write_lock { @data.clear }
      end

      # Returns all live (non-expired) keys.
      # @return [Array<Object>]
      def keys
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @lock.with_read_lock do
          result = []
          @data.each_pair { |k, entry| result << k unless entry[:expires_at] && entry[:expires_at] <= now }
          result
        end
      end

      private

      def expired?(entry)
        expires_at = entry[:expires_at]
        expires_at && expires_at <= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
