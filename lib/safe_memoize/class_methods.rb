# frozen_string_literal: true

module SafeMemoize
  module ClassMethods
    def memoize(method_name, ttl: nil, max_size: nil, if: nil, unless: nil, shared: false)
      method_name = method_name.to_sym
      visibility = memoized_method_visibility(method_name)

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

      raise ArgumentError, "max_size: is not supported with shared: true" if shared && max_size

      if cond_if && cond_unless
        raise ArgumentError, "cannot specify both :if and :unless"
      end
      raise ArgumentError, ":if must be callable" if cond_if && !cond_if.respond_to?(:call)
      raise ArgumentError, ":unless must be callable" if cond_unless && !cond_unless.respond_to?(:call)

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
                record_cache_hit(method_name, args, kwargs)
                call_memo_hooks(:on_hit, cache_key, record)
                record[:value]
              else
                call_memo_hooks(:on_expire, cache_key, record) if record && !record_live

                start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                value = super(*args, **kwargs)
                elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

                new_record = {value: value, expires_at: memo_expires_at(ttl)}
                shared_cache[cache_key] = new_record unless condition && !condition.call(value)

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

          if max_size || condition
            # Locked path: used when LRU tracking or conditional storage is needed.
            memo_mutex!.synchronize do
              record = memo_cache_record(cache_key)
              if record
                lru_touch(method_name, cache_key) if max_size
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
      matcher = if args.empty? && kwargs.empty?
        ->(key) { key[0] == method_name }
      else
        cache_key = [method_name, args, kwargs]
        ->(key) { key == cache_key }
      end

      __safe_memo_shared_mutex__.synchronize do
        __safe_memo_shared_cache__.delete_if { |key, _| matcher.call(key) }
      end
    end

    def reset_all_shared_memos
      __safe_memo_shared_mutex__.synchronize do
        @__safe_memo_shared_cache__ = {}
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

    def memoize_all(except: [], **options)
      excluded = Array(except).map(&:to_sym)
      public_instance_methods(false).each do |method_name|
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

    def memoized_method_visibility(method_name)
      return :private if private_method_defined?(method_name)
      return :protected if protected_method_defined?(method_name)

      :public
    end
  end
end
