# frozen_string_literal: true

module SafeMemoize
  module ClassMethods
    def memoize(method_name, ttl: nil, max_size: nil, ttl_refresh: false, if: nil, unless: nil, shared: false, key: nil)
      method_name = method_name.to_sym
      visibility = memoized_method_visibility(method_name)

      config = SafeMemoize.configuration
      ttl = config.default_ttl if ttl.nil?
      max_size = config.default_max_size if max_size.nil?

      # :if and :unless are reserved Ruby keywords, so they can't be referenced
      # as local variables directly. binding.local_variable_get is the only way
      # to read keyword arguments with those names inside the method body.
      cond_if = binding.local_variable_get(:if)
      cond_unless = binding.local_variable_get(:unless)

      ttl = if ttl.nil?
        nil
      else

        ttl = Float(ttl)
        raise ArgumentError, "ttl must be non-negative" if ttl < 0

        ttl
      end

      max_size = if max_size.nil?
        nil
      else
        raise ArgumentError, "max_size must be a positive integer" unless max_size.is_a?(Integer)
        raise ArgumentError, "max_size must be positive" unless max_size > 0

        max_size
      end

      raise ArgumentError, "ttl_refresh: requires a ttl: to be set" if ttl_refresh && ttl.nil?

      if cond_if && cond_unless
        raise ArgumentError, "cannot specify both :if and :unless"
      end
      raise ArgumentError, ":if must be callable" if cond_if && !cond_if.respond_to?(:call)
      raise ArgumentError, ":unless must be callable" if cond_unless && !cond_unless.respond_to?(:call)
      raise ArgumentError, ":key must be callable" if key && !key.respond_to?(:call)

      __safe_memo_class_key_generators__[method_name] = key if key

      # Normalize to a single "should cache?" predicate
      condition = if cond_if
        cond_if
      elsif cond_unless
        ->(result) { !cond_unless.call(result) }
      end

      if shared
        klass = self
        shared_mutex = klass.send(:__safe_memo_shared_mutex__)

        mod = Module.new do
          define_method(method_name) do |*args, **kwargs, &block|
            return super(*args, **kwargs, &block) if block

            cache_key = compute_cache_key(method_name, args, kwargs)

            shared_mutex.synchronize do
              shared_cache = klass.send(:__safe_memo_shared_cache__)
              record = shared_cache[cache_key]
              now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              record_live = record && (record[:expires_at].nil? || record[:expires_at] > now)

              if record_live
                if max_size
                  lru = klass.send(:__safe_memo_shared_lru_order__)[method_name] ||= {}
                  lru.delete(cache_key)
                  lru[cache_key] = true
                end
                record[:expires_at] = memo_expires_at(ttl) if ttl_refresh
                record_cache_hit(method_name, args, kwargs)
                call_memo_hooks(:on_hit, cache_key, record)
                record[:value]
              else
                call_memo_hooks(:on_expire, cache_key, record) if record && !record_live

                start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                value = super(*args, **kwargs)
                elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

                new_record = memo_record(value, expires_at: memo_expires_at(ttl))

                if !condition || condition.call(value)
                  if max_size
                    lru = klass.send(:__safe_memo_shared_lru_order__)[method_name] ||= {}
                    lru.delete_if { |key, _| !shared_cache.key?(key) }
                    if lru.size >= max_size
                      lru_key = lru.keys.first
                      lru.delete(lru_key)
                      evicted = shared_cache.delete(lru_key)
                      call_memo_hooks(:on_evict, lru_key, evicted) if evicted
                    end
                  end
                  shared_cache[cache_key] = new_record
                  if max_size
                    lru = klass.send(:__safe_memo_shared_lru_order__)[method_name] ||= {}
                    lru[cache_key] = true
                  end
                end

                record_cache_miss(method_name, args, kwargs, elapsed_time)
                call_memo_hooks(:on_miss, cache_key, new_record)

                value
              end
            end
          end

          send(visibility, method_name)
        end

        prepend mod

        return
      end

      mod = Module.new do
        define_method(method_name) do |*args, **kwargs, &block|
          # Blocks bypass cache entirely — they aren't comparable
          return super(*args, **kwargs, &block) if block

          cache_key = compute_cache_key(method_name, args, kwargs)

          if max_size || condition || ttl_refresh
            # Locked path: used when LRU tracking, conditional storage, or TTL refresh is needed.
            memo_mutex!.synchronize do
              record = memo_cache_record(cache_key)
              if record
                lru_touch(method_name, cache_key) if max_size
                record[:expires_at] = memo_expires_at(ttl) if ttl_refresh
                record_cache_hit(method_name, args, kwargs)
                call_memo_hooks(:on_hit, cache_key, record)
                memo_record_value(record)
              else
                start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                value = super(*args, **kwargs)
                elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

                new_record = memo_record(value, expires_at: memo_expires_at(ttl))
                if !condition || condition.call(value)
                  lru_evict_if_over_limit(method_name, max_size) if max_size
                  @__safe_memo_cache__ ||= {}
                  @__safe_memo_cache__[cache_key] = new_record
                  lru_touch(method_name, cache_key) if max_size
                end
                record_cache_miss(method_name, args, kwargs, elapsed_time)
                call_memo_hooks(:on_miss, cache_key, new_record)

                value
              end
            end
          else
            # Fast path: check without lock
            if (record = memo_cache_record(cache_key))
              record_cache_hit(method_name, args, kwargs)
              call_memo_hooks(:on_hit, cache_key, record)
              return memo_record_value(record)
            end

            # Cache miss - compute and store
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            result = memo_fetch_or_store(cache_key, ttl: ttl) { super(*args, **kwargs) }
            elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

            with_memo_lock do
              record_cache_miss(method_name, args, kwargs, elapsed_time)
              new_record = memo_cache_record(cache_key)
              call_memo_hooks(:on_miss, cache_key, new_record)
            end

            result
          end
        end

        send(visibility, method_name)
      end

      prepend mod
    end

    def reset_shared_memo(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      specific_key = (args.empty? && kwargs.empty?) ? nil : [method_name, args, kwargs]

      __safe_memo_shared_mutex__.synchronize do
        if specific_key
          __safe_memo_shared_cache__.delete(specific_key)
          __safe_memo_shared_lru_order__[method_name]&.delete(specific_key)
        else
          __safe_memo_shared_cache__.delete_if { |key, _| key[0] == method_name }
          __safe_memo_shared_lru_order__.delete(method_name)
        end
      end
    end

    def reset_all_shared_memos
      __safe_memo_shared_mutex__.synchronize do
        @__safe_memo_shared_cache__ = {}
        @__safe_memo_shared_lru_order__ = {}
      end
    end

    def shared_memoized?(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      cache_key = [method_name, args, kwargs]

      __safe_memo_shared_mutex__.synchronize do
        cache = @__safe_memo_shared_cache__
        return false unless cache

        record = cache[cache_key]
        return false unless record

        record[:expires_at].nil? || record[:expires_at] > Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    def shared_memo_count(method_name = nil)
      __safe_memo_shared_mutex__.synchronize do
        cache = @__safe_memo_shared_cache__ || {}
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        live = cache.reject { |_, r| r[:expires_at] && r[:expires_at] <= now }
        method_name ? live.count { |key, _| key[0] == method_name.to_sym } : live.count
      end
    end

    def shared_memo_age(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      cache_key = [method_name, args, kwargs]

      __safe_memo_shared_mutex__.synchronize do
        cache = @__safe_memo_shared_cache__
        return nil unless cache

        record = cache[cache_key]
        return nil unless record

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if record[:expires_at] && record[:expires_at] <= now

        cached_at = record[:cached_at]
        return nil unless cached_at

        (now - cached_at).round(6)
      end
    end

    def shared_memo_stale?(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      cache_key = [method_name, args, kwargs]

      __safe_memo_shared_mutex__.synchronize do
        cache = @__safe_memo_shared_cache__
        return false unless cache

        record = cache[cache_key]
        return false unless record

        expires_at = record[:expires_at]
        return false unless expires_at

        expires_at <= Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    def memoize_all(except: [], include_protected: false, include_private: false, **options)
      excluded = Array(except).map(&:to_sym)

      methods = public_instance_methods(false)
      methods |= protected_instance_methods(false) if include_protected
      methods |= private_instance_methods(false) if include_private

      methods.each do |method_name|
        next if excluded.include?(method_name)

        memoize(method_name, **options)
      end
    end

    private

    def __safe_memo_shared_cache__
      @__safe_memo_shared_cache__ ||= {}
    end

    def __safe_memo_shared_mutex__
      @__safe_memo_shared_mutex__ ||= Mutex.new
    end

    def __safe_memo_shared_lru_order__
      @__safe_memo_shared_lru_order__ ||= {}
    end

    def __safe_memo_class_key_generators__
      @__safe_memo_class_key_generators__ ||= {}
    end

    def memoized_method_visibility(method_name)
      return :private if private_method_defined?(method_name)
      return :protected if protected_method_defined?(method_name)

      :public
    end
  end
end
