# frozen_string_literal: true

require "safe_memoize"

module SafeMemoize
  module Stores
    # Cache store adapter backed by Redis.
    #
    # Not auto-required. Add to your application:
    #   require "safe_memoize/stores/redis"
    #
    # Requires a Redis-compatible client that responds to +#get+, +#set+,
    # +#del+, and +#scan_each+. Compatible with the +redis+ gem (v4+) and
    # any drop-in replacement.
    #
    # Values and keys are serialized with +Marshal+ (Base64-encoded via
    # +Array#pack("m0")+) so that any Ruby object, including +nil+ and
    # +false+, can be stored and retrieved faithfully. TTL is forwarded to
    # Redis as the +PX+ option (milliseconds, rounded up to the nearest
    # millisecond; minimum 1 ms) to preserve sub-second precision.
    #
    # @example Basic setup
    #   require "redis"
    #   require "safe_memoize/stores/redis"
    #
    #   REDIS_STORE = SafeMemoize::Stores::Redis.new(::Redis.new)
    #
    #   class MyService
    #     prepend SafeMemoize
    #     def fetch(id) = http_get(id)
    #     memoize :fetch, store: REDIS_STORE, ttl: 300
    #   end
    #
    # @example With a custom namespace
    #   STORE = SafeMemoize::Stores::Redis.new(::Redis.new, namespace: "myapp:memo")
    class Redis < Base
      # @param client [Object] a Redis-compatible client responding to
      #   +#get+, +#set+, +#del+, and +#scan_each+
      # @param namespace [String] key prefix used to scope all entries in Redis;
      #   defaults to +"safe_memoize"+
      def initialize(client, namespace: "safe_memoize")
        @client = client
        @namespace = namespace
      end

      # @param key [Object] cache key (serialized with Marshal + Base64)
      # @return [Object] the stored value, or {MISS} if absent
      def read(key)
        raw = @client.get(redis_key(key))
        return MISS if raw.nil?

        Marshal.load(raw) # rubocop:disable Security/MarshalLoad
      rescue TypeError, ArgumentError
        MISS
      end

      # @param key [Object] cache key
      # @param value [Object] value to store (may be +nil+ or +false+)
      # @param expires_in [Numeric, nil] TTL in seconds forwarded to Redis as +PX+
      #   (milliseconds, rounded up; minimum 1 ms); +nil+ means no expiry
      # @return [void]
      def write(key, value, expires_in: nil)
        raw = Marshal.dump(value)
        if expires_in
          @client.set(redis_key(key), raw, px: [(expires_in * 1000).ceil, 1].max)
        else
          @client.set(redis_key(key), raw)
        end
      end

      # @param key [Object]
      # @return [void]
      def delete(key)
        @client.del(redis_key(key))
      end

      # Removes all entries written by this adapter (scoped to the namespace).
      # Uses +SCAN+ internally to avoid blocking Redis.
      # @return [void]
      def clear
        to_delete = []
        @client.scan_each(match: "#{@namespace}:*") { |k| to_delete << k }
        @client.del(*to_delete) unless to_delete.empty?
      end

      # Returns all live keys in the namespace, deserialized back to their
      # original Ruby form. Entries that cannot be deserialized are silently
      # skipped. Because Redis handles TTL natively, every key returned by
      # +SCAN+ is live.
      #
      # @return [Array<Object>]
      def keys
        prefix = "#{@namespace}:"
        result = []
        @client.scan_each(match: "#{@namespace}:*") do |rk|
          encoded = rk.delete_prefix(prefix)
          result << Marshal.load(encoded.unpack1("m0")) # rubocop:disable Security/MarshalLoad
        rescue ArgumentError, TypeError
          # skip keys that cannot be deserialized (e.g. written by another serializer)
        end
        result
      end

      private

      def redis_key(key)
        "#{@namespace}:#{[Marshal.dump(key)].pack("m0")}"
      end
    end
  end
end
