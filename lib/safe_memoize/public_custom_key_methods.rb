# frozen_string_literal: true

module SafeMemoize
  # Instance-level custom cache key registration.
  module PublicCustomKeyMethods
    # Registers a per-instance custom key generator for a memoized method.
    #
    # The block receives the same arguments as the method and should return a
    # single value used as the cache key. Two calls that produce the same key
    # value share one cached result, regardless of their raw arguments.
    #
    # Instance-level keys take priority over the class-level +key:+ option set
    # in {ClassMethods#memoize}.
    #
    # @param method_name [Symbol, String]
    # @yield [*args, **kwargs] called with the method's arguments on each invocation
    # @yieldreturn [Object] the key value (must be comparable with +==+)
    # @return [void]
    # @raise [ArgumentError] if no block is given
    #
    # @example Collapse all option hashes that share the same user ID
    #   obj.memoize_with_custom_key(:fetch) { |user_id, _options| user_id }
    def memoize_with_custom_key(method_name, &key_generator)
      raise ArgumentError, "block required for key generation" unless key_generator

      register_custom_key(method_name, &key_generator)
    end

    # Removes the custom key generator for one method, or all generators.
    #
    # @param method_name [Symbol, String, nil] when given, removes only that method's
    #   generator; when +nil+, removes all generators on this instance
    # @return [void]
    def clear_custom_keys(method_name = nil)
      if method_name
        with_memo_lock do
          custom_key_store.delete(method_name.to_sym)
        end
      else
        with_memo_lock do
          _clear_custom_keys
        end
      end
    end
  end
end
