# frozen_string_literal: true

require "safe_memoize"

module SafeMemoize
  module Stores
    # Cache store adapter backed by any +ActiveSupport::Cache::Store+.
    #
    # Not auto-required. Add to your Rails initializer:
    #   require "safe_memoize/stores/rails_cache"
    #
    # Compatible with any +ActiveSupport::Cache::Store+ implementation
    # (+MemoryStore+, +FileStore+, +MemCacheStore+, +RedisCacheStore+, etc.)
    # and with +Rails.cache+ directly.
    #
    # Because +ActiveSupport::Cache+ returns +nil+ for both a cache miss and
    # a cached +nil+ value, this adapter wraps every value in a two-element
    # sentinel envelope before writing. The envelope is transparent to callers.
    #
    # TTL is forwarded as +expires_in:+ to the cache, so the underlying store
    # manages expiry natively — there is no lazy-expiry overhead on read.
    #
    # {#clear} uses +delete_matched+ scoped to the adapter's namespace, so it
    # never clears entries belonging to other parts of the application. The
    # backend must respond to +delete_matched+ (all standard Rails cache stores
    # do); a +NotImplementedError+ is raised if it does not.
    #
    # {#keys} returns an empty array — +ActiveSupport::Cache::Store+ does not
    # expose a standard key enumeration API. Override the method if your
    # backend supports it.
    #
    # @example Basic setup
    #   # config/initializers/safe_memoize.rb
    #   require "safe_memoize/stores/rails_cache"
    #
    #   MEMO_STORE = SafeMemoize::Stores::RailsCache.new(Rails.cache)
    #
    #   class MyService
    #     prepend SafeMemoize
    #     def fetch(id) = http_get(id)
    #     memoize :fetch, store: MEMO_STORE, ttl: 300
    #   end
    #
    # @example Dedicated cache store (recommended for production)
    #   MEMO_STORE = SafeMemoize::Stores::RailsCache.new(
    #     ActiveSupport::Cache::RedisCacheStore.new(url: ENV["REDIS_URL"]),
    #     namespace: "myapp:memo"
    #   )
    class RailsCache < Base
      # Tag prepended to every stored value so cached +nil+/+false+ are
      # distinguishable from a cache miss.
      VALUE_TAG = "safe_memoize:v1"

      # @param cache [ActiveSupport::Cache::Store] the cache store to use;
      #   typically +Rails.cache+ or a dedicated store instance
      # @param namespace [String] key prefix used to scope all entries;
      #   defaults to +"safe_memoize"+
      def initialize(cache, namespace: "safe_memoize")
        @cache = cache
        @namespace = namespace
      end

      # @param key [Object] cache key (serialized with Marshal + Base64)
      # @return [Object] the stored value, or {MISS} if absent or unrecognised
      def read(key)
        raw = @cache.read(cache_key(key))
        return MISS unless raw.is_a?(Array) && raw.length == 2 && raw[0] == VALUE_TAG

        raw[1]
      end

      # @param key [Object] cache key
      # @param value [Object] value to store (may be +nil+ or +false+)
      # @param expires_in [Numeric, nil] TTL in seconds forwarded to the cache
      #   as +expires_in:+; +nil+ means no expiry
      # @return [void]
      def write(key, value, expires_in: nil)
        opts = expires_in ? {expires_in: expires_in} : {}
        @cache.write(cache_key(key), [VALUE_TAG, value], **opts)
      end

      # @param key [Object]
      # @return [void]
      def delete(key)
        @cache.delete(cache_key(key))
      end

      # Removes all entries written by this adapter (scoped to the namespace).
      #
      # Delegates to +delete_matched+ on the underlying store; raises
      # +NotImplementedError+ if the store does not support it.
      #
      # @return [void]
      # @raise [NotImplementedError] if the backing store does not respond to
      #   +delete_matched+
      def clear
        unless @cache.respond_to?(:delete_matched)
          raise NotImplementedError,
            "#{@cache.class} does not support delete_matched — " \
            "implement clear manually or use a store that supports it (e.g. MemoryStore, RedisCacheStore)"
        end
        @cache.delete_matched(/\A#{Regexp.escape(@namespace)}:/)
      end

      # Returns an empty array.
      #
      # +ActiveSupport::Cache::Store+ does not expose a key enumeration API.
      # Override this method if your backend supports key listing.
      #
      # @return [Array]
      def keys
        []
      end

      # @param key [Object]
      # @return [Boolean]
      def exist?(key)
        @cache.exist?(cache_key(key))
      end

      private

      def cache_key(key)
        "#{@namespace}:#{[Marshal.dump(key)].pack("m0")}"
      end
    end
  end
end
