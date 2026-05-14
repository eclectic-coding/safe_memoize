# frozen_string_literal: true

module SafeMemoize
  module ClassMethods
    def memoize(method_name, ttl: nil)
      method_name = method_name.to_sym
      visibility = memoized_method_visibility(method_name)

      ttl = if ttl.nil?
        nil
      else
        ttl = Float(ttl)
        raise ArgumentError, "ttl must be non-negative" if ttl < 0

        ttl
      end

      expires_at = ttl && Process.clock_gettime(Process::CLOCK_MONOTONIC) + ttl

      mod = Module.new do
        define_method(method_name) do |*args, **kwargs, &block|
          # Blocks bypass cache entirely — they aren't comparable
          return super(*args, **kwargs, &block) if block

          cache_key = safe_memo_cache_key(method_name, args, kwargs)

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
