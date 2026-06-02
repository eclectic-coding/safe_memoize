# frozen_string_literal: true

module SafeMemoize
  module Stores
    # Multi-level (L1/L2/…) cache store that checks faster layers first and
    # promotes values up on a miss, reducing latency and load on slower backends.
    #
    # Reads walk the store list from first (fastest) to last (slowest). On a
    # miss at level N the value is read from level N+1 and written back into
    # all preceding levels ("read-through promotion"). Writes always go to every
    # level so all layers stay consistent.
    #
    # @example In-process L1 + Redis L2
    #   l1 = SafeMemoize::Stores::Memory.new
    #   l2 = MyRedisStore.new
    #
    #   memoize :fetch, store: SafeMemoize::Stores::Multilevel.new(l1, l2)
    #
    # @example Via the store: Array shorthand
    #   memoize :fetch, store: [l1, l2], ttl: 300
    #
    # @example With a short promote_expires_in for the L1 layer
    #   memoize :fetch, store: SafeMemoize::Stores::Multilevel.new(l1, l2, promote_expires_in: 60)
    class Multilevel < Base
      # @return [Array<Stores::Base>] the ordered store layers (fastest first)
      attr_reader :stores

      # @param stores [Array<Stores::Base>] two or more store instances, ordered
      #   from fastest (L1) to slowest (last)
      # @param promote_expires_in [Numeric, nil] TTL applied when promoting a
      #   value from a deeper layer into a shallower one; +nil+ means no expiry
      #   on the promoted entry (the L1 store's own eviction — e.g. LRU — handles
      #   memory bounds instead)
      # @raise [ArgumentError] if fewer than two stores are supplied, or any
      #   element is not a {Stores::Base} instance
      def initialize(*stores, promote_expires_in: nil)
        raise ArgumentError, "Multilevel requires at least 2 stores" if stores.size < 2

        stores.each_with_index do |s, i|
          unless s.is_a?(Base)
            raise ArgumentError,
              "Multilevel store[#{i}] must be a Stores::Base instance (got #{s.class})"
          end
        end

        @stores = stores.freeze
        @promote_expires_in = promote_expires_in ? Float(promote_expires_in) : nil
      end

      # Walk levels from fastest to slowest; return the first hit, promoting
      # the value into all shallower layers.
      def read(key)
        @stores.each_with_index do |store, i|
          result = store.read(key)
          next if result.equal?(MISS)

          # Promote into every shallower level
          @stores.first(i).each { |s| s.write(key, result, expires_in: @promote_expires_in) }
          return result
        end

        MISS
      end

      # Write to every level simultaneously.
      def write(key, value, expires_in: nil)
        @stores.each { |s| s.write(key, value, expires_in: expires_in) }
      end

      # Delete from every level.
      def delete(key)
        @stores.each { |s| s.delete(key) }
      end

      # Clear every level.
      def clear
        @stores.each(&:clear)
      end

      # Union of live keys across all levels.
      def keys
        @stores.flat_map(&:keys).uniq
      end
    end
  end
end
