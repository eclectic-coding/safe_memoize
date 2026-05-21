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

    def memo_ttl_remaining(method_name, *args, **kwargs)
      cache_key = safe_memo_cache_key(method_name, args, kwargs)

      with_memo_lock do
        record = memo_cache_record(cache_key)
        return 0 unless record

        expires_at = record[:expires_at]
        return nil unless expires_at

        remaining = expires_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        (remaining > 0) ? remaining.round(6) : 0
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

    def on_memo_expire(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_expire, &block)
    end

    def on_memo_evict(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_evict, &block)
    end

    def on_memo_hit(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_hit, &block)
    end

    def on_memo_miss(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_miss, &block)
    end

    def on_memo_store(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_store, &block)
    end

    def clear_memo_hooks(hook_type = nil)
      with_memo_lock do
        _clear_memo_hooks(hook_type)
      end
    end

    def warm_memo(method_name, *args, ttl: nil, **kwargs, &block)
      raise ArgumentError, "block required" unless block

      method_name = method_name.to_sym
      cache_key = compute_cache_key(method_name, args, kwargs)
      value = block.call

      with_memo_lock do
        @__safe_memo_cache__ ||= {}
        record = memo_record(value, expires_at: memo_expires_at(ttl))
        @__safe_memo_cache__[cache_key] = record
        call_memo_hooks(:on_store, cache_key, record)
      end

      value
    end

    def memo_preload(method_name, *arg_sets)
      method_name = method_name.to_sym
      arg_sets.map do |args|
        send(method_name, *Array(args))
      end
    end

    def dump_memo(method_name = nil)
      method_name = method_name&.to_sym

      with_memo_lock do
        cache = memo_cache_or_nil || {}
        entries = method_name ? cache.select { |key, _| key[0] == method_name } : cache.dup
        entries.select! { |_, record| memo_record_live?(record) }
        entries.transform_values { |record| memo_record_value(record) }
      end
    end

    def load_memo(snapshot)
      raise ArgumentError, "snapshot must be a Hash" unless snapshot.is_a?(Hash)

      with_memo_lock do
        @__safe_memo_cache__ ||= {}
        snapshot.each do |cache_key, value|
          record = memo_record(value, expires_at: nil)
          @__safe_memo_cache__[cache_key] = record
          call_memo_hooks(:on_store, cache_key, record)
        end
      end

      nil
    end

    def memo_touch(method_name, *args, ttl: nil, **kwargs)
      method_name = method_name.to_sym
      cache_key = safe_memo_cache_key(method_name, args, kwargs)

      with_memo_lock do
        cache = memo_cache_or_nil
        return false unless cache

        record = cache[cache_key]
        return false unless record && memo_record_live?(record)

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        effective_ttl = if ttl
          ttl
        elsif record[:expires_at] && record[:cached_at]
          record[:expires_at] - record[:cached_at]
        end

        record[:expires_at] = effective_ttl ? now + effective_ttl : nil
        record[:cached_at] = now
        true
      end
    end

    def memo_refresh(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      reset_memo(method_name, *args, **kwargs)
      send(method_name, *args, **kwargs)
    end

    def memo_age(method_name, *args, **kwargs)
      cache_key = safe_memo_cache_key(method_name, args, kwargs)

      with_memo_lock do
        record = memo_cache_record(cache_key)
        return nil unless record

        cached_at = record[:cached_at]
        return nil unless cached_at

        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - cached_at).round(6)
      end
    end

    def memo_stale?(method_name, *args, **kwargs)
      cache_key = safe_memo_cache_key(method_name, args, kwargs)

      with_memo_lock do
        cache = memo_cache_or_nil
        return false unless cache

        record = cache[cache_key]
        return false unless record

        !memo_record_live?(record)
      end
    end

    def reset_memo(method_name, *args, **kwargs)
      method_name = method_name.to_sym

      matcher = memo_matcher_for(method_name, args, kwargs)

      with_memo_lock do
        with_memo_cache do |cache|
          cache.delete_if do |key, record|
            if matcher.call(key)
              call_memo_hooks(:on_evict, key, record)
              true
            else
              false
            end
          end
        end
      end
    end

    def reset_all_memos
      with_memo_lock do
        if defined?(@__safe_memo_cache__) && @__safe_memo_cache__
          @__safe_memo_cache__.each do |key, record|
            call_memo_hooks(:on_evict, key, record)
          end
        end
        @__safe_memo_cache__ = {}
        lru_clear_all
      end
    end

    def memo_inspect(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      cache_key = compute_cache_key(method_name, args, kwargs)

      with_memo_lock do
        record = memo_cache_record(cache_key)
        return nil unless record

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        ttl_remaining = if record[:expires_at]
          remaining = record[:expires_at] - now
          (remaining > 0) ? remaining.round(6) : 0
        end

        age = (now - record[:cached_at]).round(6) if record[:cached_at]

        metrics_key = safe_memo_cache_key(method_name, args, kwargs)
        entry_metrics = memo_metrics_store[metrics_key] || {hits: 0, misses: 0}

        custom_key = (cache_key.length == 2) ? cache_key[1] : nil

        lru_position = begin
          method_lru = lru_order_store[method_name]
          if method_lru&.key?(cache_key)
            keys = method_lru.keys
            keys.length - keys.index(cache_key)
          end
        end

        {
          cached: true,
          value: memo_record_value(record),
          hits: entry_metrics[:hits],
          misses: entry_metrics[:misses],
          ttl_remaining: ttl_remaining,
          age: age,
          custom_key: custom_key,
          lru_position: lru_position
        }
      end
    end
  end
end
