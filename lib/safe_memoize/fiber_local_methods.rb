# frozen_string_literal: true

module SafeMemoize
  # Public and private helpers for fiber-local memoization.
  #
  # When a method is memoized with +fiber_local: true+, its cached values are
  # stored in +Fiber[:__safe_memoize__]+ rather than instance variables, giving
  # each fiber an isolated cache that is automatically discarded when the fiber
  # terminates. No mutex is required because fibers are cooperative: only one
  # fiber runs at a time within a thread.
  module FiberLocalMethods
    FIBER_STORE_KEY = :__safe_memoize__

    # Returns +true+ if the given call is currently cached in the current fiber.
    #
    # @note In Ruby, +Fiber.new+ inherits the parent fiber's local storage. SafeMemoize
    #   detects inherited stores via an +:__owner__+ sentinel and creates a fresh
    #   isolated store for each fiber on first write.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Boolean]
    def fiber_local_memoized?(method_name, *args, **kwargs, &block)
      return false if block

      method_name = method_name.to_sym
      cache_key = compute_cache_key(method_name, args, kwargs)
      record = fiber_memo_cache_or_nil&.[](cache_key)
      memo_record_live?(record)
    end

    # Removes one or all fiber-local cached entries for a method in the current fiber.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [void]
    def reset_fiber_memo(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      cache = fiber_memo_cache_or_nil
      return unless cache

      if args.empty? && kwargs.empty?
        cache.delete_if { |key, _| key[0] == method_name }
        fiber_memo_lru_or_nil&.delete(method_name)
      else
        cache_key = compute_cache_key(method_name, args, kwargs)
        cache.delete(cache_key)
        fiber_memo_lru_or_nil&.[](method_name)&.delete(cache_key)
      end
    end

    # Clears all fiber-local cached entries for this instance in the current fiber.
    #
    # @return [void]
    def reset_all_fiber_memos
      store = Fiber[FIBER_STORE_KEY]
      return unless store&.[](:__owner__) == Fiber.current.object_id

      store.delete(object_id)
    end

    private

    # Returns the per-fiber top-level store hash, creating a fresh one for
    # this fiber if the current store was inherited from a parent fiber.
    def fiber_root_store!
      store = Fiber[FIBER_STORE_KEY]
      unless store&.[](:__owner__) == Fiber.current.object_id
        store = {__owner__: Fiber.current.object_id}
        Fiber[FIBER_STORE_KEY] = store
      end
      store
    end

    def fiber_memo_store!
      fiber_root_store![object_id] ||= {cache: {}, lru: {}}
    end

    def fiber_memo_cache!
      fiber_memo_store![:cache]
    end

    def fiber_memo_lru!
      fiber_memo_store![:lru]
    end

    def fiber_root_store_or_nil
      store = Fiber[FIBER_STORE_KEY]
      return nil unless store&.[](:__owner__) == Fiber.current.object_id

      store
    end

    def fiber_memo_store_or_nil
      fiber_root_store_or_nil&.[](object_id)
    end

    def fiber_memo_cache_or_nil
      fiber_memo_store_or_nil&.[](:cache)
    end

    def fiber_memo_lru_or_nil
      fiber_memo_store_or_nil&.[](:lru)
    end
  end
end
