# frozen_string_literal: true

module SafeMemoize
  # Public instance methods mixed into every class that prepends {SafeMemoize}.
  module PublicMethods
    # Returns +true+ if the given call is currently cached (and not expired).
    #
    # Always returns +false+ when a block is provided, because block-taking methods
    # cannot be safely keyed by arguments alone.
    #
    # @param method_name [Symbol, String]
    # @param args [Array] positional arguments used to look up the entry
    # @param kwargs [Hash] keyword arguments used to look up the entry
    # @return [Boolean]
    def memoized?(method_name, *args, **kwargs, &block)
      return false if block

      cache_key = compute_cache_key(method_name, args, kwargs)

      with_memo_lock do
        memo_cache_hit?(cache_key)
      end
    end

    # Returns the number of seconds until the cached entry expires.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Float] seconds remaining (may be 0 if already expired)
    # @return [nil] if the entry has no TTL or is not cached
    def memo_ttl_remaining(method_name, *args, **kwargs)
      cache_key = compute_cache_key(method_name, args, kwargs)

      with_memo_lock do
        record = memo_cache_record(cache_key)
        return 0 unless record

        expires_at = record[:expires_at]
        return nil unless expires_at

        remaining = expires_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        (remaining > 0) ? remaining.round(6) : 0
      end
    end

    # Returns the number of live cached entries for a method (or all methods).
    #
    # @param method_name [Symbol, String, nil] when omitted, counts all methods
    # @return [Integer]
    def memo_count(*method_name)
      scoped_method = safe_memo_scoped_method(method_name)

      with_memo_lock do
        safe_memo_count_for(scoped_method)
      end
    end

    # Returns metadata hashes describing each cached entry.
    #
    # Each hash contains +:args+, +:kwargs+ (or +:custom_key+ for custom-keyed entries),
    # and +:method+ when no +method_name+ filter is applied.
    #
    # @param method_name [Symbol, String, nil] when omitted, returns entries for all methods
    # @return [Array<Hash>]
    def memo_keys(*method_name)
      scoped_method = safe_memo_scoped_method(method_name)

      with_memo_lock do
        safe_memo_keys_for(scoped_method)
      end
    end

    # Returns metadata hashes including the cached value for each entry.
    #
    # Each hash contains all fields from {#memo_keys} plus +:value+.
    #
    # @param method_name [Symbol, String, nil] when omitted, returns entries for all methods
    # @return [Array<Hash>]
    def memo_values(*method_name)
      scoped_method = safe_memo_scoped_method(method_name)

      with_memo_lock do
        safe_memo_values_for(scoped_method)
      end
    end

    # Registers a hook that fires on every cache hit.
    #
    # @yield [cache_key, record] called synchronously inside the cache lock
    # @yieldparam cache_key [Array] the internal cache key
    # @yieldparam record [Hash] the cache record (+:value+, +:expires_at+, +:cached_at+)
    # @return [void]
    # @raise [ArgumentError] if no block is given
    def on_memo_expire(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_expire, &block)
    end

    # Registers a hook that fires when an LRU eviction occurs.
    #
    # @yield [cache_key, record]
    # @return [void]
    # @raise [ArgumentError] if no block is given
    def on_memo_evict(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_evict, &block)
    end

    # Registers a hook that fires on every cache hit.
    #
    # @yield [cache_key, record]
    # @return [void]
    # @raise [ArgumentError] if no block is given
    def on_memo_hit(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_hit, &block)
    end

    # Registers a hook that fires on every cache miss (before the value is stored).
    #
    # @yield [cache_key, record]
    # @return [void]
    # @raise [ArgumentError] if no block is given
    def on_memo_miss(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_miss, &block)
    end

    # Registers a hook that fires whenever a value is written to the cache
    # (miss, {#warm_memo}, or {#load_memo}).
    #
    # @yield [cache_key, record]
    # @return [void]
    # @raise [ArgumentError] if no block is given
    def on_memo_store(&block)
      raise ArgumentError, "block required" unless block

      register_memo_hook(:on_store, &block)
    end

    # Removes all registered hooks, or only hooks of a specific type.
    #
    # @param hook_type [Symbol, nil] one of +:on_hit+, +:on_miss+, +:on_store+,
    #   +:on_expire+, +:on_evict+; when +nil+ all hooks are cleared
    # @return [void]
    def clear_memo_hooks(hook_type = nil)
      with_memo_lock do
        _clear_memo_hooks(hook_type)
      end
    end

    # Pre-populates a cache entry with the value returned by the block without
    # calling the memoized method itself.
    #
    # Useful for warming caches from a serialized snapshot or an external source.
    #
    # @param method_name [Symbol, String]
    # @param args [Array] positional arguments that identify the cache slot
    # @param ttl [Numeric, nil] optional expiry for the warmed entry
    # @param kwargs [Hash] keyword arguments that identify the cache slot
    # @yield [] must return the value to store
    # @return [Object] the value returned by the block
    # @raise [ArgumentError] if no block is given
    #
    # @example
    #   obj.warm_memo(:find, 42) { User.new(id: 42, name: "cached") }
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

    # Calls the memoized method for each argument set and caches all results.
    #
    # Equivalent to calling the method for each arg set individually, but expressed
    # as a single call for clarity.
    #
    # @param method_name [Symbol, String]
    # @param arg_sets [Array<Array>] each element is an argument list for one call
    # @return [Array] cached values in input order
    #
    # @example
    #   obj.memo_preload(:find, [1], [2], [3])
    def memo_preload(method_name, *arg_sets)
      method_name = method_name.to_sym
      arg_sets.map do |args|
        send(method_name, *Array(args))
      end
    end

    # Exports live cache entries as a plain hash suitable for serialization.
    #
    # @param method_name [Symbol, String, nil] when given, exports only entries for
    #   that method; when +nil+, exports all methods
    # @return [Hash] mapping cache keys to their cached values (expired entries excluded)
    def dump_memo(method_name = nil)
      method_name = method_name&.to_sym

      with_memo_lock do
        cache = memo_cache_or_nil || {}
        entries = method_name ? cache.select { |key, _| key[0] == method_name } : cache.dup
        entries.select! { |_, record| memo_record_live?(record) }
        entries.transform_values { |record| memo_record_value(record) }
      end
    end

    # Restores cache entries from a snapshot produced by {#dump_memo}.
    #
    # Existing entries are not cleared; snapshot keys are merged in.
    # Each restored entry fires the +:on_store+ hook.
    #
    # @param snapshot [Hash] a hash previously returned by {#dump_memo}
    # @return [nil]
    # @raise [ArgumentError] if +snapshot+ is not a +Hash+
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

    # Resets the expiry clock on a live cached entry without recomputing its value.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param ttl [Numeric, nil] new TTL to apply; when +nil+, uses the original TTL
    #   derived from the entry's +cached_at+ and +expires_at+ timestamps
    # @param kwargs [Hash]
    # @return [Boolean] +true+ if the entry existed and was touched; +false+ otherwise
    def memo_touch(method_name, *args, ttl: nil, **kwargs)
      method_name = method_name.to_sym
      cache_key = compute_cache_key(method_name, args, kwargs)

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

    # Clears the cached entry and immediately re-calls the method to populate a
    # fresh value.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Object] the freshly computed and cached value
    def memo_refresh(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      reset_memo(method_name, *args, **kwargs)
      send(method_name, *args, **kwargs)
    end

    # Returns how many seconds ago the entry was cached, or +nil+ if not cached.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Float, nil]
    def memo_age(method_name, *args, **kwargs)
      cache_key = compute_cache_key(method_name, args, kwargs)

      with_memo_lock do
        record = memo_cache_record(cache_key)
        return nil unless record

        cached_at = record[:cached_at]
        return nil unless cached_at

        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - cached_at).round(6)
      end
    end

    # Returns +true+ if the entry exists but its TTL has elapsed.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Boolean]
    def memo_stale?(method_name, *args, **kwargs)
      cache_key = compute_cache_key(method_name, args, kwargs)

      with_memo_lock do
        cache = memo_cache_or_nil
        return false unless cache

        record = cache[cache_key]
        return false unless record

        !memo_record_live?(record)
      end
    end

    # Removes one or all cached entries for a method.
    #
    # When called with only +method_name+, all entries for that method are cleared.
    # When called with +method_name+ *and* arguments, only the exact matching entry
    # is cleared. Each evicted entry fires the +:on_evict+ hook.
    #
    # @param method_name [Symbol, String]
    # @param args [Array] positional arguments identifying a specific entry
    # @param kwargs [Hash] keyword arguments identifying a specific entry
    # @return [void]
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

    # Clears all cached entries for every method on this instance.
    # Each evicted entry fires the +:on_evict+ hook.
    #
    # @return [void]
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

    # Returns a detailed snapshot of a single cached entry, or +nil+ if not cached.
    #
    # All reads are performed inside a single mutex hold.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Hash, nil] hash with keys +:cached+, +:value+, +:hits+, +:misses+,
    #   +:ttl_remaining+, +:age+, +:custom_key+, +:lru_position+; or +nil+ when
    #   the entry is not present
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
