# frozen_string_literal: true

module SafeMemoize
  module PublicMethods
    def memoized?(method_name, *args, **kwargs, &block)
      return false if block

      cache_key = safe_memo_cache_key(method_name, args, kwargs)

      with_memo_lock do
        memo_cache_hit?(cache_key)
      end
    end

    def memo_count(*method_name)
      scoped_method = safe_memo_scoped_method(method_name)

      with_memo_lock do
        safe_memo_count_for(scoped_method)
      end
    end

    def memo_keys(*method_name)
      scoped_method = safe_memo_scoped_method(method_name)

      with_memo_lock do
        safe_memo_keys_for(scoped_method)
      end
    end

    def memo_values(*method_name)
      scoped_method = safe_memo_scoped_method(method_name)

      with_memo_lock do
        safe_memo_values_for(scoped_method)
      end
    end

    def reset_memo(method_name, *args, **kwargs)
      method_name = method_name.to_sym

      matcher = memo_matcher_for(method_name, args, kwargs)

      with_memo_lock do
        with_memo_cache do |cache|
          cache.delete_if { |key, _| matcher.call(key) }
        end
      end
    end

    def reset_all_memos
      with_memo_lock do
        @__safe_memo_cache__ = {}
      end
    end
  end
end
