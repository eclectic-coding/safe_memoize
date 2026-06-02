# frozen_string_literal: true

module SafeMemoize
  module Stores
    # Wraps any {Base} store adapter with probabilistic early expiry (the
    # XFetch algorithm) to prevent cache stampedes — the thundering-herd
    # problem where many processes simultaneously recompute a value the moment
    # it expires under high load.
    #
    # Instead of waiting until {#read} returns {MISS} at the hard expiry
    # deadline, the wrapper stochastically returns {MISS} slightly before
    # expiry, giving one process a head start on recomputation while everyone
    # else still gets the cached value. The probability of early expiry rises
    # as the entry approaches its deadline.
    #
    # === XFetch formula
    #
    #   early_expire = now − (delta × beta × log(rand)) ≥ expires_at
    #
    # * +delta+ — estimated computation time in seconds (default 0.1 s).
    #   Configure this to the typical duration of the underlying computation.
    # * +beta+  — aggressiveness scalar (default 1.0); higher values trigger
    #   early recomputation more eagerly.
    #
    # Values are stored internally as an envelope +{value:, expires_at:}+ so
    # the wrapper always knows the hard deadline regardless of what the inner
    # store exposes on read. The envelope survives standard Ruby Marshal
    # serialization (Redis via the +redis-store+ or +redis-client+ gems,
    # Rails.cache, etc.). Values that cannot be serialized alongside a small
    # hash are not supported.
    #
    # @example Wrap a Redis store
    #   store = SafeMemoize::Stores::XFetch.new(
    #     MyRedisStore.new,
    #     delta: 0.2,   # typical computation time in seconds
    #     beta:  1.5    # slightly aggressive early expiry
    #   )
    #   memoize :fetch, store: store, ttl: 300
    #
    # @example Compose with CircuitBreaker
    #   store = SafeMemoize::Stores::XFetch.new(
    #     SafeMemoize::Stores::CircuitBreaker.new(MyRedisStore.new),
    #     delta: 0.1
    #   )
    #   memoize :fetch, store: store, ttl: 60
    class XFetch < Base
      ENVELOPE_KEY = :__sm_xfetch_v1__

      DEFAULT_BETA = 1.0
      DEFAULT_DELTA = 0.1

      # @return [Stores::Base] the wrapped inner store
      attr_reader :wrapped_store
      # @return [Float] aggressiveness scalar
      attr_reader :beta
      # @return [Float] estimated computation time in seconds
      attr_reader :delta

      # @param store [Stores::Base] the backing store to wrap
      # @param beta  [Numeric] aggressiveness scalar (default 1.0)
      # @param delta [Numeric] estimated computation time in seconds (default 0.1)
      # @raise [ArgumentError] if +store+ is not a {Stores::Base} instance, or
      #   if +beta+/+delta+ are not positive numbers
      def initialize(store, beta: DEFAULT_BETA, delta: DEFAULT_DELTA)
        unless store.is_a?(Base)
          raise ArgumentError, "XFetch requires a Stores::Base instance (got #{store.class})"
        end

        @wrapped_store = store
        @beta = Float(beta)
        @delta = Float(delta)

        raise ArgumentError, "beta must be positive" unless @beta > 0
        raise ArgumentError, "delta must be positive" unless @delta > 0
      end

      # Read from the wrapped store and apply the XFetch probabilistic check.
      #
      # Returns {MISS} when:
      # * the inner store has no entry for +key+
      # * the stored value is not an XFetch envelope (possibly written by an
      #   older version or a different store wrapper)
      # * the XFetch formula triggers early expiry
      def read(key)
        raw = @wrapped_store.read(key)
        return MISS if raw.equal?(MISS)
        return MISS unless envelope?(raw)

        expires_at = raw[:expires_at]

        if expires_at
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          early = now - @delta * @beta * Math.log(rand) >= expires_at
          return MISS if early
        end

        raw[:value]
      end

      # Write the value to the wrapped store inside an XFetch envelope.
      def write(key, value, expires_in: nil)
        expires_at = expires_in ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + expires_in.to_f : nil
        envelope = {ENVELOPE_KEY => true, :value => value, :expires_at => expires_at}
        @wrapped_store.write(key, envelope, expires_in: expires_in)
      end

      # Delete from the wrapped store.
      def delete(key)
        @wrapped_store.delete(key)
      end

      # Clear the wrapped store.
      def clear
        @wrapped_store.clear
      end

      # Returns live keys from the wrapped store.
      def keys
        @wrapped_store.keys
      end

      private

      def envelope?(value)
        value.is_a?(Hash) && value[ENVELOPE_KEY]
      end
    end
  end
end
