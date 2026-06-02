# frozen_string_literal: true

module SafeMemoize
  module Stores
    # Wraps any {Base} store adapter with a circuit breaker that silently falls
    # back to the per-instance in-process cache when the external store is
    # unavailable, rather than propagating exceptions to callers.
    #
    # === States
    #
    # * +:closed+    — normal; every call goes through to the wrapped store;
    #                  consecutive errors are counted
    # * +:open+      — tripped; reads return {MISS} and writes are no-ops so the
    #                  memoize wrapper falls back to the per-instance hash; no
    #                  calls reach the wrapped store until the probe interval elapses
    # * +:half_open+ — probe period (probe interval elapsed); calls are let
    #                  through to the wrapped store; the first success closes the
    #                  circuit, any failure re-opens it and resets the timer
    #
    # Any successful call while the circuit is +:closed+ resets the consecutive
    # error counter, so transient blips do not accumulate toward the threshold.
    #
    # @example Wrap a custom Redis store
    #   store = SafeMemoize::Stores::CircuitBreaker.new(
    #     MyRedisStore.new,
    #     error_threshold: 5,
    #     probe_interval:  30
    #   )
    #   memoize :fetch, store: store
    #
    # @example Via the circuit_breaker: option (auto-wraps the configured store)
    #   memoize :fetch, store: MyRedisStore.new, circuit_breaker: true
    #   memoize :fetch, store: MyRedisStore.new,
    #                   circuit_breaker: { error_threshold: 3, probe_interval: 60 }
    class CircuitBreaker < Base
      DEFAULT_ERROR_THRESHOLD = 5
      DEFAULT_PROBE_INTERVAL = 30.0

      # @return [Stores::Base] the wrapped inner store
      attr_reader :wrapped_store
      # @return [Integer] number of consecutive errors that trip the circuit
      attr_reader :error_threshold
      # @return [Float] seconds after tripping before a probe is attempted
      attr_reader :probe_interval

      # @param store [Stores::Base] the backing store to protect
      # @param error_threshold [Integer] consecutive errors that trip the circuit (default 5)
      # @param probe_interval [Numeric] seconds to wait before probing (default 30)
      # @raise [ArgumentError] if +store+ is not a {Stores::Base} instance, or
      #   if threshold / interval are invalid
      def initialize(store, error_threshold: DEFAULT_ERROR_THRESHOLD, probe_interval: DEFAULT_PROBE_INTERVAL)
        unless store.is_a?(Base)
          raise ArgumentError, "CircuitBreaker requires a Stores::Base instance (got #{store.class})"
        end

        @wrapped_store = store
        @error_threshold = Integer(error_threshold)
        @probe_interval = Float(probe_interval)

        raise ArgumentError, "error_threshold must be positive" unless @error_threshold > 0
        raise ArgumentError, "probe_interval must be positive" unless @probe_interval > 0

        @mutex = Mutex.new
        @error_count = 0
        @opened_at = nil
      end

      # Read from the wrapped store, returning {MISS} on error or when the
      # circuit is open instead of raising.
      def read(key)
        st = current_state
        return MISS if st == :open

        result = @wrapped_store.read(key)
        record_success(st)
        result
      rescue
        record_failure
        MISS
      end

      # Write to the wrapped store, silently swallowing errors so the caller's
      # return value is unaffected. A no-op when the circuit is open.
      def write(key, value, expires_in: nil)
        st = current_state
        return if st == :open

        @wrapped_store.write(key, value, expires_in: expires_in)
        record_success(st)
      rescue
        record_failure
      end

      # Delete from the wrapped store. A no-op when the circuit is open.
      def delete(key)
        return if current_state == :open

        @wrapped_store.delete(key)
      rescue
        record_failure
      end

      # Clear the wrapped store. Errors are recorded but not re-raised.
      def clear
        @wrapped_store.clear
      rescue
        record_failure
      end

      # Returns live keys from the wrapped store, or an empty array when the
      # circuit is open or the store raises.
      def keys
        return [] if current_state == :open

        @wrapped_store.keys
      rescue
        record_failure
        []
      end

      # Returns the current circuit state: +:closed+, +:open+, or +:half_open+.
      # @return [Symbol]
      def state
        current_state
      end

      # Returns +true+ when the circuit is not fully closed (i.e. open or half-open).
      # @return [Boolean]
      def open?
        current_state != :closed
      end

      # Returns the current consecutive error count.
      # @return [Integer]
      def error_count
        @mutex.synchronize { @error_count }
      end

      # Manually resets the circuit to +:closed+, clearing the error counter.
      # @return [void]
      def reset!
        @mutex.synchronize do
          @error_count = 0
          @opened_at = nil
        end
      end

      private

      def current_state
        @mutex.synchronize do
          next :closed if @opened_at.nil?

          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @opened_at
          (elapsed >= @probe_interval) ? :half_open : :open
        end
      end

      def record_success(prior_state)
        return unless prior_state == :half_open || @error_count > 0

        @mutex.synchronize do
          @error_count = 0
          @opened_at = nil
        end
      end

      def record_failure
        @mutex.synchronize do
          @error_count += 1
          if @error_count >= @error_threshold || !@opened_at.nil?
            @opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end
      end
    end
  end
end
