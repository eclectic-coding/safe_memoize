# frozen_string_literal: true

module SafeMemoize
  # Class-level DSL added to any class that does +prepend SafeMemoize+.
  module ClassMethods
    # Wraps an existing instance method with a thread-safe per-instance cache.
    #
    # Must be called *after* the method is defined. Raises +ArgumentError+ immediately
    # at class-definition time if no such method exists.
    #
    # @param method_name [Symbol, String] name of the instance method to memoize
    # @param ttl [Numeric, nil] seconds until the cached value expires; +nil+ means
    #   the entry never expires. Falls back to {Configuration#default_ttl} when +nil+.
    # @param max_size [Integer, nil] maximum number of cached entries per instance
    #   for this method; the least-recently-used entry is evicted when the limit is
    #   reached. Falls back to {Configuration#default_max_size} when +nil+.
    # @param ttl_refresh [Boolean] when +true+, every cache *hit* resets the expiry
    #   clock (sliding-window TTL). Requires +ttl:+ to be set.
    # @param if [Proc, nil] callable predicate; the result is cached only when the
    #   predicate returns truthy. Receives the computed return value as its argument.
    # @param unless [Proc, nil] inverse of +:if+; the result is *not* cached when the
    #   predicate returns truthy.
    # @param shared [Boolean] when +true+, results are stored on the class rather than
    #   per instance — all instances share one cache.
    # @param key [Proc, nil] class-level custom cache key generator. Receives the same
    #   arguments as the method and should return a single comparable value. Instance-level
    #   keys set via {PublicCustomKeyMethods#memoize_with_custom_key} take priority.
    # @param store [Stores::Base, nil] custom cache store adapter. Must be a
    #   {Stores::Base} subclass instance. The store is shared across all instances of the
    #   class. When +nil+, the default per-instance in-process hash is used.
    #   Cannot be combined with +max_size:+ or +shared:+.
    # @return [void]
    # @raise [ArgumentError] if the method does not exist, or option values are invalid
    #
    # @example Zero-argument method
    #   def expensive_query = db.run("SELECT …")
    #   memoize :expensive_query
    #
    # @example With TTL and LRU cap
    #   def fetch(id) = http_get(id)
    #   memoize :fetch, ttl: 60, max_size: 500
    #
    # @example Conditional — only cache successful responses
    #   memoize :fetch, if: ->(v) { v[:status] == 200 }
    #
    # @example With a custom store
    #   STORE = SafeMemoize::Stores::Memory.new
    #   memoize :fetch, store: STORE, ttl: 300
    def memoize(method_name, ttl: nil, max_size: nil, ttl_refresh: false, if: nil, unless: nil, shared: false, key: nil, store: nil)
      method_name = method_name.to_sym

      unless method_defined?(method_name) || private_method_defined?(method_name) || protected_method_defined?(method_name)
        raise ArgumentError, "cannot memoize :#{method_name} — no instance method with that name is defined on #{self}"
      end

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

      if store
        unless store.is_a?(SafeMemoize::Stores::Base)
          raise ArgumentError, "store: must be a SafeMemoize::Stores::Base instance (got #{store.class})"
        end
        raise ArgumentError, "max_size: is not supported with store: — use the store adapter's own eviction" if max_size
        raise ArgumentError, "shared: and store: cannot be combined" if shared
      end

      __safe_memo_class_key_generators__[method_name] = key if key

      # Normalize to a single "should cache?" predicate
      condition = if cond_if
        cond_if
      elsif cond_unless
        ->(result) { !cond_unless.call(result) }
      end

      if store
        miss = SafeMemoize::Stores::Base::MISS

        mod = Module.new do
          define_method(method_name) do |*args, **kwargs, &block|
            return super(*args, **kwargs, &block) if block

            cache_key = compute_cache_key(method_name, args, kwargs)
            cached = store.read(cache_key)

            unless cached.equal?(miss)
              store.write(cache_key, cached, expires_in: ttl) if ttl_refresh
              record_cache_hit(method_name, args, kwargs)
              call_memo_hooks(:on_hit, cache_key, {value: cached, expires_at: nil, cached_at: nil})
              return cached
            end

            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            value = Adapters::OpenTelemetry.trace(
              SafeMemoize.configuration.opentelemetry_tracer, method_name, self.class.name
            ) { super(*args, **kwargs) }
            elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if !condition || condition.call(value)
              store.write(cache_key, value, expires_in: ttl)
              call_memo_hooks(:on_store, cache_key, {value: value, expires_at: nil, cached_at: now})
            end

            record_cache_miss(method_name, args, kwargs, elapsed_time)
            call_memo_hooks(:on_miss, cache_key, {value: value, expires_at: nil, cached_at: now})

            value
          end

          send(visibility, method_name)
        end

        prepend mod

        return
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
                value = Adapters::OpenTelemetry.trace(SafeMemoize.configuration.opentelemetry_tracer, method_name, klass.name) { super(*args, **kwargs) }
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
                  call_memo_hooks(:on_store, cache_key, new_record)
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
                value = Adapters::OpenTelemetry.trace(SafeMemoize.configuration.opentelemetry_tracer, method_name, self.class.name) { super(*args, **kwargs) }
                elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

                new_record = memo_record(value, expires_at: memo_expires_at(ttl))
                if !condition || condition.call(value)
                  lru_evict_if_over_limit(method_name, max_size) if max_size
                  @__safe_memo_cache__ ||= {}
                  @__safe_memo_cache__[cache_key] = new_record
                  lru_touch(method_name, cache_key) if max_size
                  call_memo_hooks(:on_store, cache_key, new_record)
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
            result = memo_fetch_or_store(cache_key, ttl: ttl) do
              Adapters::OpenTelemetry.trace(SafeMemoize.configuration.opentelemetry_tracer, method_name, self.class.name) { super(*args, **kwargs) }
            end
            elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

            with_memo_lock do
              record_cache_miss(method_name, args, kwargs, elapsed_time)
              new_record = memo_cache_record(cache_key)
              call_memo_hooks(:on_store, cache_key, new_record)
              call_memo_hooks(:on_miss, cache_key, new_record)
            end

            result
          end
        end

        send(visibility, method_name)
      end

      prepend mod
    end

    # Memoizes every eligible public instance method defined directly on the class.
    #
    # Accepts all options that {#memoize} accepts, plus +:except:+ and +:only:+.
    # Raises +ArgumentError+ when both +:only:+ and +:except:+ are given.
    #
    # @param except [Array<Symbol, String>] method names to skip
    # @param only [Array<Symbol, String>] when non-empty, only these methods are memoized
    # @param include_protected [Boolean] also memoize +protected+ methods
    # @param include_private [Boolean] also memoize +private+ methods
    # @param options [Hash] any additional options forwarded to {#memoize}
    # @return [void]
    # @raise [ArgumentError] if both +:only:+ and +:except:+ are given
    def memoize_all(except: [], only: [], include_protected: false, include_private: false, **options)
      raise ArgumentError, "cannot specify both :only and :except" if only.any? && except.any?

      excluded = Array(except).map(&:to_sym)
      included = Array(only).map(&:to_sym)

      methods = public_instance_methods(false)
      methods |= protected_instance_methods(false) if include_protected
      methods |= private_instance_methods(false) if include_private

      methods.each do |method_name|
        next if excluded.include?(method_name)
        next if included.any? && !included.include?(method_name)

        memoize(method_name, **options)
      end
    end

    # Clears one or all entries from the class-level shared cache.
    #
    # With no positional args after +method_name+, clears *all* shared entries for
    # that method. With args/kwargs, clears only the matching entry.
    #
    # @param method_name [Symbol, String] the memoized method
    # @param args [Array] positional arguments identifying the entry to clear
    # @param kwargs [Hash] keyword arguments identifying the entry to clear
    # @return [void]
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

    # Clears the entire class-level shared cache for this class.
    # @return [void]
    def reset_all_shared_memos
      __safe_memo_shared_mutex__.synchronize do
        @__safe_memo_shared_cache__ = {}
        @__safe_memo_shared_lru_order__ = {}
      end
    end

    # Returns +true+ if a live shared cache entry exists for the given call signature.
    #
    # @param method_name [Symbol, String]
    # @param args [Array] positional arguments
    # @param kwargs [Hash] keyword arguments
    # @return [Boolean]
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

    # Returns the number of live entries in the class-level shared cache.
    #
    # @param method_name [Symbol, String, nil] when given, counts only entries for
    #   that method; when +nil+, counts all methods.
    # @return [Integer]
    def shared_memo_count(method_name = nil)
      __safe_memo_shared_mutex__.synchronize do
        cache = @__safe_memo_shared_cache__ || {}
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        live = cache.reject { |_, r| r[:expires_at] && r[:expires_at] <= now }
        method_name ? live.count { |key, _| key[0] == method_name.to_sym } : live.count
      end
    end

    # Returns how many seconds ago the shared entry was cached, or +nil+ if not cached
    # or already expired.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Float, nil]
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

    # Returns +true+ if the shared entry exists but its TTL has elapsed.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Boolean]
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
