# frozen_string_literal: true

module SafeMemoize
  module Stores
    # Default in-process cache store backed by a plain +Hash+.
    #
    # Thread-safe via an internal +Mutex+. Supports per-entry TTL with lazy
    # expiry: stale entries are not proactively removed but are treated as
    # misses on read and excluded from {#keys}.
    class Memory < Base
      def initialize
        @data = {}
        @mutex = Mutex.new
      end

      # @param key [Object]
      # @return [Object] stored value, or {MISS} if absent or expired
      def read(key)
        @mutex.synchronize do
          entry = @data[key]
          return MISS unless entry
          return MISS if expired?(entry)

          entry[:value]
        end
      end

      # @param key [Object]
      # @param value [Object]
      # @param expires_in [Numeric, nil] seconds until expiry
      # @return [void]
      def write(key, value, expires_in: nil)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        expires_at = expires_in ? now + expires_in.to_f : nil

        @mutex.synchronize do
          @data[key] = {value: value, expires_at: expires_at, cached_at: now}
        end
      end

      # @param key [Object]
      # @return [void]
      def delete(key)
        @mutex.synchronize { @data.delete(key) }
      end

      # Removes all entries.
      # @return [void]
      def clear
        @mutex.synchronize { @data.clear }
      end

      # Returns all live (non-expired) keys.
      # @return [Array<Object>]
      def keys
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @mutex.synchronize do
          @data.filter_map { |k, entry| k unless entry[:expires_at] && entry[:expires_at] <= now }
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
