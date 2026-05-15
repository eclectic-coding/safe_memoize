# frozen_string_literal: true

module SafeMemoize
  module ClassMethods
    def memoize(method_name, ttl: nil, max_size: nil)
      method_name = method_name.to_sym
      visibility = memoized_method_visibility(method_name)

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

      expires_at = ttl && Process.clock_gettime(Process::CLOCK_MONOTONIC) + ttl

      mod = Module.new do
        define_method(method_name) do |*args, **kwargs, &block|
          # Blocks bypass cache entirely — they aren't comparable
          return super(*args, **kwargs, &block) if block

          cache_key = compute_cache_key(method_name, args, kwargs)

          if max_size
            # LRU path: hold the lock for reads too so access order stays consistent.
            memo_mutex!.synchronize do
              record = memo_cache_record(cache_key)
              if record
                lru_touch(method_name, cache_key)
                record_cache_hit(method_name, args)
                memo_record_value(record)
              else
                start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                value = super(*args, **kwargs)
                elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

                lru_evict_if_over_limit(method_name, max_size)
                @__safe_memo_cache__ ||= {}
                @__safe_memo_cache__[cache_key] = memo_record(value, expires_at: expires_at)
                lru_touch(method_name, cache_key)
                record_cache_miss(method_name, args, elapsed_time)

                value
              end
            end
          else
            # Fast path: check without lock
            if (record = memo_cache_record(cache_key))
              record_cache_hit(method_name, args)
              return memo_record_value(record)
            end

            # Cache miss - compute and store
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            result = memo_fetch_or_store(cache_key, expires_at: expires_at) { super(*args, **kwargs) }
            elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

            with_memo_lock do
              record_cache_miss(method_name, args, elapsed_time)
            end

            result
          end
        end

        send(visibility, method_name)
      end

      prepend mod
    end

    private

    def memoized_method_visibility(method_name)
      return :private if private_method_defined?(method_name)
      return :protected if protected_method_defined?(method_name)

      :public
    end
  end
end
