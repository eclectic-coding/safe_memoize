# frozen_string_literal: true

module SafeMemoize
  # @api private
  module InspectionMethods
    private

    def safe_memo_scoped_method(method_name)
      raise ArgumentError, "expected 0 or 1 arguments" if method_name.length > 1

      method_name.first&.to_sym
    end

    def memo_matcher_for(method_name, args, kwargs)
      if args.empty? && kwargs.empty?
        effective = resolve_memo_key_name(method_name)
        ->(key) { key[0] == effective }
      else
        cache_key = compute_cache_key(method_name, args, kwargs)
        ->(key) { key == cache_key }
      end
    end

    def memo_entries_for(method_name)
      cache = memo_cache_or_nil
      return [] unless cache

      memo_prune_expired_entries!(cache)
      entries = cache.to_a
      return entries unless method_name

      effective = resolve_memo_key_name(method_name)
      entries.select { |(cache_key, _)| cache_key[0] == effective }
    end

    def safe_memo_count_for(method_name)
      memo_entries_for(method_name).length
    end

    def safe_memo_keys_for(method_name)
      entries = memo_entries_for(method_name)
      include_method = method_name.nil?

      entries.map do |(cache_key, value)|
        memo_projection(cache_key, value, include_method: include_method, include_value: false)
      end
    end

    def safe_memo_values_for(method_name)
      entries = memo_entries_for(method_name)
      include_method = method_name.nil?

      entries.map do |(cache_key, value)|
        memo_projection(cache_key, value, include_method: include_method, include_value: true)
      end
    end

    def memo_projection(cache_key, value, include_method:, include_value:)
      # Custom keys are [method, custom_key] (2 elements); default keys are
      # [method, args, kwargs] (3 elements). Detect and surface accordingly.
      if cache_key.length == 2
        effective_name, custom_key = cache_key
        payload = {custom_key: custom_key}
      else
        effective_name, args, kwargs = cache_key
        payload = {args: args, kwargs: kwargs}
      end

      payload[:method] = safe_memo_bare_method_name(effective_name) if include_method
      payload[:value] = memo_record_value(value) if include_value
      payload
    end

    def safe_memo_cache_key(method_name, args, kwargs)
      [method_name.to_sym, deep_freeze_copy(args), deep_freeze_copy(kwargs)]
    end

    # Returns the active namespace string for a bare method name, or nil.
    # Priority: per-method namespace: option > class safe_memoize_namespace > global.
    #
    # Uses instance_variable_get throughout so this is safe to call from worker
    # Ractors (reads only; lazy-init ivars must not be triggered in that context).
    def __safe_memo_resolve_namespace__(method_name)
      ns_map = self.class.instance_variable_get(:@__safe_memo_method_namespaces__)
      (ns_map && ns_map[method_name]) ||
        self.class.instance_variable_get(:@__safe_memoize_namespace__) ||
        SafeMemoize.instance_variable_get(:@configuration)&.namespace
    end

    # Returns the effective cache key sym for a bare method name, applying any
    # active namespace (per-method > class-level > global).
    def resolve_memo_key_name(method_name)
      ns = __safe_memo_resolve_namespace__(method_name)
      ns ? :"#{ns}:#{method_name}" : method_name
    end

    # Strips the namespace prefix from an effective key sym, returning the bare
    # method name. When no namespace is present the sym is returned unchanged.
    def safe_memo_bare_method_name(key_sym)
      s = key_sym.to_s
      colon_idx = s.index(":")
      colon_idx ? s[(colon_idx + 1)..].to_sym : key_sym
    end

    def deep_freeze_copy(obj)
      case obj
      when Array
        obj.map { |e| deep_freeze_copy(e) }.freeze
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[deep_freeze_copy(k)] = deep_freeze_copy(v) }.freeze
      when String
        -obj
      else
        obj
      end
    end
  end
end
