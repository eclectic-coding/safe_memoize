# frozen_string_literal: true

module SafeMemoize
  module PublicCustomKeyMethods
    def memoize_with_custom_key(method_name, &key_generator)
      raise ArgumentError, "block required for key generation" unless key_generator

      register_custom_key(method_name, &key_generator)
    end

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
