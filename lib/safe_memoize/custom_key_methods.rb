# frozen_string_literal: true

module SafeMemoize
  module CustomKeyMethods
    private

    def custom_key_store
      @__safe_memo_custom_keys__ ||= {}
    end

    def register_custom_key(method_name, &block)
      raise ArgumentError, "block required" unless block

      method_name = method_name.to_sym
      custom_key_store[method_name] = block
    end

    def compute_cache_key(method_name, args, kwargs)
      method_name = method_name.to_sym

      # Check if a custom key generator is registered
      custom_key_block = custom_key_store[method_name]

      if custom_key_block
        # Call the custom key generator with args and kwargs
        custom_key = custom_key_block.call(*args, **kwargs)
        # Wrap in a standard format: [method, custom_key]
        [method_name, custom_key]
      else
        # Use default key generation
        safe_memo_cache_key(method_name, args, kwargs)
      end
    end

    def _clear_custom_keys
      @__safe_memo_custom_keys__ = {}
    end
  end
end
