# frozen_string_literal: true

module SafeMemoize
  module Stores
    # Abstract base class for SafeMemoize cache store adapters.
    #
    # Subclass this and implement all abstract methods to plug in a custom backend
    # (Redis, Memcached, Rails.cache, etc.). The {Stores::Memory} class is the
    # built-in reference implementation.
    #
    # @abstract
    #
    # @example Minimal inline implementation
    #   class MyStore < SafeMemoize::Stores::Base
    #     def initialize = (@h = {})
    #     def read(key) = @h.fetch(key, MISS)
    #     def write(key, value, expires_in: nil) = (@h[key] = value)
    #     def delete(key) = @h.delete(key)
    #     def clear = @h.clear
    #     def keys = @h.keys
    #   end
    class Base
      # Sentinel returned by {#read} to signal a cache miss.
      #
      # Distinct from +nil+ and +false+, which are valid cached values.
      MISS = Object.new.freeze

      # Read a value from the store.
      #
      # @param key [Object] cache key
      # @return [Object] the stored value, or {MISS} if absent or expired
      # @abstract
      def read(key)
        raise NotImplementedError, "#{self.class}#read must be implemented"
      end

      # Write a value to the store.
      #
      # @param key [Object] cache key
      # @param value [Object] value to cache (may be +nil+ or +false+)
      # @param expires_in [Numeric, nil] seconds until expiry; +nil+ means no expiry
      # @return [void]
      # @abstract
      def write(key, value, expires_in: nil)
        raise NotImplementedError, "#{self.class}#write must be implemented"
      end

      # Delete a single entry.
      #
      # @param key [Object] cache key
      # @return [void]
      # @abstract
      def delete(key)
        raise NotImplementedError, "#{self.class}#delete must be implemented"
      end

      # Remove all entries from the store.
      #
      # @return [void]
      # @abstract
      def clear
        raise NotImplementedError, "#{self.class}#clear must be implemented"
      end

      # Return all live (non-expired) keys.
      #
      # @return [Array<Object>]
      # @abstract
      def keys
        raise NotImplementedError, "#{self.class}#keys must be implemented"
      end

      # Check whether a live entry exists for the given key.
      #
      # The default delegates to {#read}; subclasses may override for stores
      # with a native existence check.
      #
      # @param key [Object]
      # @return [Boolean]
      def exist?(key)
        read(key) != MISS
      end
    end
  end
end
