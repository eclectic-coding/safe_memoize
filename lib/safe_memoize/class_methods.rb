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
    # @param fiber_local [Boolean] when +true+, results are stored in
    #   +Fiber[:__safe_memoize__]+ rather than instance variables. Each fiber gets its
    #   own isolated cache that is automatically discarded when the fiber terminates. No
    #   mutex is acquired. Cannot be combined with +shared:+ or +store:+.
    # @param ractor_safe [Boolean] when +true+, the class-level shared cache is owned by
    #   a supervisor +Ractor+ rather than a +Mutex+-protected ivar, making it accessible
    #   from worker Ractors. Requires +shared: true+. Cached values are deep-frozen via
    #   +Ractor.make_shareable+. Incompatible with +if:+, +unless:+, +max_size:+,
    #   +ttl_refresh:+, +key:+, and +store:+.
    # @param namespace [String, nil] prefix prepended to every cache key for this method,
    #   scoping it to a logical partition. Takes precedence over both the class-level
    #   {#safe_memoize_namespace} and the global {SafeMemoize::Configuration#namespace}.
    #   Useful for versioning a single method independently of its peers. Must not contain
    #   the character +:+.
    # @param cache_bust [Proc, Symbol, nil] callable invoked on the instance (via
    #   +instance_exec+) on every cache lookup to obtain a version token. The token is
    #   folded into the cache key alongside the normal arguments, so when the token
    #   changes (e.g. an ActiveRecord +updated_at+ timestamp advances after a +save+)
    #   the old key no longer matches any entry — the method is recomputed and the result
    #   stored under the new key. Accepts any callable (+Proc+, +lambda+, +Method+) that
    #   takes no arguments, or a +Symbol+ naming an instance method. Cannot be combined
    #   with +key:+.
    # @param shared_cache [String, nil] name of a globally-registered shared cache store
    #   (see {SafeMemoize.shared_cache} and {SafeMemoize.register_shared_cache}). All
    #   instances of any class that memoizes a method with the same +shared_cache:+ name
    #   read and write the same backing store, enabling cross-class cache sharing.
    #   The store is resolved at +memoize+ definition time; call
    #   {SafeMemoize.register_shared_cache} before the class is loaded to supply a custom
    #   adapter. Incompatible with +shared:+, +store:+, +fiber_local:+, +ractor_safe:+,
    #   and +max_size:+. Composes naturally with +namespace:+, +ttl:+, +if:+, and +key:+.
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
    def memoize(method_name, ttl: nil, max_size: nil, ttl_refresh: false, if: nil, unless: nil, shared: false, key: nil, store: nil, fiber_local: false, ractor_safe: false, namespace: nil, shared_cache: nil, cache_bust: nil, **extension_options)
      method_name = method_name.to_sym

      unless method_defined?(method_name) || private_method_defined?(method_name) || protected_method_defined?(method_name)
        raise ArgumentError, "cannot memoize :#{method_name} — no instance method with that name is defined on #{self}"
      end

      unless extension_options.empty?
        extension_options.each_key do |opt|
          raise ArgumentError, "unknown memoize option :#{opt} — no registered extension handles it" unless SafeMemoize.extension_for_option(opt)
        end

        injected = {}
        extension_options.each do |opt, val|
          result = SafeMemoize.extension_for_option(opt).process_memoize_option(opt, val, method_name, extension_options)
          injected.merge!(result)
        end

        ttl = injected[:ttl] if injected.key?(:ttl)
        max_size = injected[:max_size] if injected.key?(:max_size)
        namespace = injected[:namespace] if injected.key?(:namespace)
        store = injected[:store] if injected.key?(:store)
        shared_cache = injected[:shared_cache] if injected.key?(:shared_cache)
        cache_bust = injected[:cache_bust] if injected.key?(:cache_bust)
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

      if cache_bust
        unless cache_bust.respond_to?(:call) || cache_bust.is_a?(Symbol)
          raise ArgumentError, "cache_bust: must be a callable or Symbol (got #{cache_bust.class})"
        end
        raise ArgumentError, "cache_bust: and key: cannot be combined" if key
      end

      if store
        raise ArgumentError, "store: must be a SafeMemoize::Stores::Base instance (got #{store.class})" unless store.is_a?(SafeMemoize::Stores::Base)
        raise ArgumentError, "max_size: is not supported with store: — use the store adapter's own eviction" if max_size
        raise ArgumentError, "shared: and store: cannot be combined" if shared
      end

      if fiber_local
        raise ArgumentError, "fiber_local: and shared: cannot be combined" if shared
        raise ArgumentError, "fiber_local: and store: cannot be combined" if store
      end

      if ractor_safe
        raise ArgumentError, "ractor_safe: requires shared: true" unless shared
        raise ArgumentError, "ractor_safe: is incompatible with if:/unless:" if cond_if || cond_unless
        raise ArgumentError, "ractor_safe: is incompatible with max_size:" if max_size
        raise ArgumentError, "ractor_safe: is incompatible with ttl_refresh:" if ttl_refresh
        raise ArgumentError, "ractor_safe: is incompatible with key:" if key
        raise ArgumentError, "ractor_safe: is incompatible with store:" if store
      end

      if namespace
        raise ArgumentError, "namespace: must be a String (got #{namespace.class})" unless namespace.is_a?(String)
        raise ArgumentError, "namespace: must not be empty" if namespace.empty?
        raise ArgumentError, "namespace: must not contain ':'" if namespace.include?(":")
        __safe_memo_method_namespaces__[method_name] = namespace
      end

      if shared_cache
        raise ArgumentError, "shared_cache: must be a String (got #{shared_cache.class})" unless shared_cache.is_a?(String)
        raise ArgumentError, "shared_cache: must not be empty" if shared_cache.empty?
        raise ArgumentError, "shared_cache: and shared: cannot be combined" if shared
        raise ArgumentError, "shared_cache: and store: cannot be combined" if store
        raise ArgumentError, "shared_cache: and fiber_local: cannot be combined" if fiber_local
        raise ArgumentError, "shared_cache: and ractor_safe: cannot be combined" if ractor_safe
        raise ArgumentError, "max_size: is not supported with shared_cache: — use the store adapter's own eviction" if max_size
        store = SafeMemoize.shared_cache(shared_cache)
      end

      # Resolve effective store: per-method store: wins; then class-level
      # safe_memoize_store; then global default_store. max_size: and shared:
      # are incompatible with external stores — fall back silently.
      effective_store = store
      if effective_store.nil? && !max_size && !shared
        class_store = safe_memoize_store
        if class_store
          effective_store = class_store
        else
          global_default = SafeMemoize.configuration.default_store
          if global_default
            unless global_default.is_a?(SafeMemoize::Stores::Base)
              raise ArgumentError,
                "SafeMemoize.configuration.default_store must be a Stores::Base instance (got #{global_default.class})"
            end
            effective_store = global_default
          end
        end
      end

      __safe_memo_class_key_generators__[method_name] = key if key
      __safe_memo_class_cache_bust_generators__[method_name] = cache_bust if cache_bust

      # Normalize to a single "should cache?" predicate
      condition = if cond_if
        cond_if
      elsif cond_unless
        ->(result) { !cond_unless.call(result) }
      end

      if effective_store
        miss = SafeMemoize::Stores::Base::MISS

        mod = Module.new do
          define_method(method_name) do |*args, **kwargs, &block|
            return super(*args, **kwargs, &block) if block

            cache_key = compute_cache_key(method_name, args, kwargs)
            cached = effective_store.read(cache_key)

            unless cached.equal?(miss)
              effective_store.write(cache_key, cached, expires_in: ttl) if ttl_refresh
              record_cache_hit(cache_key)
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
              effective_store.write(cache_key, value, expires_in: ttl)
              call_memo_hooks(:on_store, cache_key, {value: value, expires_at: nil, cached_at: now})
            end

            record_cache_miss(cache_key, elapsed_time)
            call_memo_hooks(:on_miss, cache_key, {value: value, expires_at: nil, cached_at: now})

            value
          end

          send(visibility, method_name)
        end

        prepend mod

        return
      end

      if fiber_local
        mod = Module.new do
          define_method(method_name) do |*args, **kwargs, &block|
            return super(*args, **kwargs, &block) if block

            cache_key = compute_cache_key(method_name, args, kwargs)
            fiber_cache = fiber_memo_cache!
            record = fiber_cache[cache_key]

            if memo_record_live?(record)
              if max_size
                lru = fiber_memo_lru![method_name] ||= {}
                lru.delete(cache_key)
                lru[cache_key] = true
              end
              record[:expires_at] = memo_expires_at(ttl) if ttl_refresh
              record_cache_hit(cache_key)
              call_memo_hooks(:on_hit, cache_key, record)
              memo_record_value(record)
            else
              call_memo_hooks(:on_expire, cache_key, record) if record

              start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              value = Adapters::OpenTelemetry.trace(
                SafeMemoize.configuration.opentelemetry_tracer, method_name, self.class.name
              ) { super(*args, **kwargs) }
              elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

              new_record = memo_record(value, expires_at: memo_expires_at(ttl))

              if !condition || condition.call(value)
                if max_size
                  lru = fiber_memo_lru![method_name] ||= {}
                  if lru.size >= max_size
                    evict_key = lru.keys.first
                    lru.delete(evict_key)
                    evicted = fiber_cache.delete(evict_key)
                    call_memo_hooks(:on_evict, evict_key, evicted) if evicted
                  end
                end
                fiber_cache[cache_key] = new_record
                if max_size
                  lru = fiber_memo_lru![method_name] ||= {}
                  lru.delete(cache_key)
                  lru[cache_key] = true
                end
                call_memo_hooks(:on_store, cache_key, new_record)
              end

              record_cache_miss(cache_key, elapsed_time)
              call_memo_hooks(:on_miss, cache_key, new_record)

              value
            end
          end

          send(visibility, method_name)
        end

        prepend mod

        return
      end

      if ractor_safe
        extend(RactorSharedMethods) unless is_a?(RactorSharedMethods)
        supervisor = __safe_memo_ractor_supervisor__
        __memoize_ractor_safe__(method_name, ttl, visibility, supervisor)
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
                record_cache_hit(cache_key)
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

                record_cache_miss(cache_key, elapsed_time)
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
                record_cache_hit(cache_key)
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
                record_cache_miss(cache_key, elapsed_time)
                call_memo_hooks(:on_miss, cache_key, new_record)

                value
              end
            end
          else
            # Fast path: check without lock
            if (record = memo_cache_record(cache_key))
              record_cache_hit(cache_key)
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
              record_cache_miss(cache_key, elapsed_time)
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

    # Returns the class-level default cache store, or +nil+ if not set.
    #
    # Set this to any {Stores::Base} instance to route every +memoize+ call on
    # this class through that store, without needing to pass +store:+ to each
    # individual +memoize+ call.  A per-method +store:+ option still takes
    # precedence, and the global {SafeMemoize::Configuration#default_store} is
    # the final fallback.
    #
    # @return [Stores::Base, nil]
    def safe_memoize_store
      @__safe_memoize_store__
    end

    # Sets the class-level default cache store.
    #
    # @param store [Stores::Base, nil] a store instance, or +nil+ to clear
    # @return [Stores::Base, nil]
    # @raise [ArgumentError] if +store+ is not a {Stores::Base} instance (and not +nil+)
    def safe_memoize_store=(store)
      if store && !store.is_a?(SafeMemoize::Stores::Base)
        raise ArgumentError,
          "safe_memoize_store= must be a SafeMemoize::Stores::Base instance (got #{store.class})"
      end
      @__safe_memoize_store__ = store
    end

    # Returns the class-level namespace prefix, or +nil+ if not set.
    #
    # When set, this prefix is prepended to every cache key produced by +memoize+
    # calls on this class that do not specify their own +namespace:+ option.
    # The global {SafeMemoize::Configuration#namespace} is the final fallback.
    #
    # @return [String, nil]
    def safe_memoize_namespace
      @__safe_memoize_namespace__
    end

    # Sets the class-level namespace prefix.
    #
    # @param ns [String, nil] a non-empty string without +:+, or +nil+ to clear
    # @return [String, nil]
    # @raise [ArgumentError] if +ns+ is not a valid namespace string
    def safe_memoize_namespace=(ns)
      if ns
        raise ArgumentError, "safe_memoize_namespace= must be a String (got #{ns.class})" unless ns.is_a?(String)
        raise ArgumentError, "safe_memoize_namespace= must not be empty" if ns.empty?
        raise ArgumentError, "safe_memoize_namespace= must not contain ':'" if ns.include?(":")
      end
      @__safe_memoize_namespace__ = ns
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
      effective = __safe_memo_effective_key_name__(method_name)
      specific_key = (args.empty? && kwargs.empty?) ? nil : [effective, args, kwargs]

      __safe_memo_shared_mutex__.synchronize do
        if specific_key
          __safe_memo_shared_cache__.delete(specific_key)
          __safe_memo_shared_lru_order__[method_name]&.delete(specific_key)
        else
          __safe_memo_shared_cache__.delete_if { |key, _| key[0] == effective }
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
      effective = __safe_memo_effective_key_name__(method_name)
      cache_key = [effective, args, kwargs]

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
        if method_name
          effective = __safe_memo_effective_key_name__(method_name.to_sym)
          live.count { |key, _| key[0] == effective }
        else
          live.count
        end
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
      effective = __safe_memo_effective_key_name__(method_name)
      cache_key = [effective, args, kwargs]

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
      effective = __safe_memo_effective_key_name__(method_name)
      cache_key = [effective, args, kwargs]

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

    def __safe_memo_method_namespaces__
      @__safe_memo_method_namespaces__ ||= {}
    end

    def __safe_memo_class_cache_bust_generators__
      @__safe_memo_class_cache_bust_generators__ ||= {}
    end

    # Resolves the effective first-element key sym for a given bare method name,
    # applying the active namespace. Used by class-level cache operations where
    # instance methods (compute_cache_key) are unavailable.
    def __safe_memo_effective_key_name__(method_name)
      ns_map = @__safe_memo_method_namespaces__
      ns = (ns_map && ns_map[method_name]) ||
        @__safe_memoize_namespace__ ||
        SafeMemoize.configuration.namespace
      ns ? :"#{ns}:#{method_name}" : method_name
    end

    def memoized_method_visibility(method_name)
      return :private if private_method_defined?(method_name)
      return :protected if protected_method_defined?(method_name)

      :public
    end

    # Builds and prepends the ractor_safe memoize wrapper in its own method so
    # the Proc only closes over the four Ractor-shareable locals (method_name,
    # ttl, visibility, supervisor) rather than the full memoize binding, which
    # contains non-shareable objects like SafeMemoize.configuration.
    #
    # The Proc is created inside module_eval so its self is the anonymous
    # module (a shareable object), then frozen via Ractor.make_shareable before
    # being passed to define_method. Without that step, ANY define_method Proc
    # is considered non-shareable by Ruby 3.x even when it captures nothing.
    def __memoize_ractor_safe__(method_name, ttl, visibility, supervisor)
      mod = Module.new
      wrapper = mod.module_eval do
        Ractor.make_shareable(
          proc do |*args, **kwargs, &block|
            return super(*args, **kwargs, &block) if block

            cache_key = Ractor.make_shareable([method_name, deep_freeze_copy(args), deep_freeze_copy(kwargs)])

            tag = Thread.current.object_id
            supervisor.send(Ractor.make_shareable([Ractor.current, tag, :fetch, cache_key]))
            response = Ractor.receive_if { |m| m.is_a?(Array) && m[0] == tag }[1]

            if response[:hit]
              record_cache_hit(cache_key)
              call_memo_hooks(:on_hit, cache_key, response[:record])
              return response[:record][:value]
            end

            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            value = super(*args, **kwargs)
            elapsed_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

            begin
              shareable_value = Ractor.make_shareable(value)
            rescue => e
              raise ArgumentError, "ractor_safe: memoized values must be Ractor-shareable (#{e.message})"
            end

            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            record = Ractor.make_shareable({
              value: shareable_value,
              expires_at: ttl ? now + ttl : nil,
              cached_at: now
            })

            supervisor.send(Ractor.make_shareable([Ractor.current, tag, :store, cache_key, record]))
            stored = Ractor.receive_if { |m| m.is_a?(Array) && m[0] == tag }[1]
            stored_record = stored[:stored]

            record_cache_miss(cache_key, elapsed_time)
            call_memo_hooks(:on_store, cache_key, stored_record)
            call_memo_hooks(:on_miss, cache_key, stored_record)

            stored_record[:value]
          end
        )
      end
      mod.define_method(method_name, wrapper)
      mod.send(visibility, method_name)
      prepend mod
    end
  end
end
