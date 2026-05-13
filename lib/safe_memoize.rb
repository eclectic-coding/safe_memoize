# frozen_string_literal: true

require_relative "safe_memoize/version"

module SafeMemoize
  class Error < StandardError; end

  def self.prepended(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def memoize(method_name)
      method_name = method_name.to_sym
      visibility = memoized_method_visibility(method_name)

      mod = Module.new do
        define_method(method_name) do |*args, **kwargs, &block|
          # Blocks bypass cache entirely — they aren't comparable
          return super(*args, **kwargs, &block) if block

          cache_key = safe_memo_cache_key(method_name, args, kwargs)

          @__safe_memo_mutex__ ||= Mutex.new

          # Fast path: check without lock
          if defined?(@__safe_memo_cache__) && @__safe_memo_cache__.key?(cache_key)
            return @__safe_memo_cache__[cache_key]
          end

          # Slow path: lock and double-check
          @__safe_memo_mutex__.synchronize do
            @__safe_memo_cache__ ||= {}

            if @__safe_memo_cache__.key?(cache_key)
              @__safe_memo_cache__[cache_key]
            else
              @__safe_memo_cache__[cache_key] = super(*args, **kwargs)
            end
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

  def memoized?(method_name, *args, **kwargs, &block)
    return false if block
    return false unless defined?(@__safe_memo_cache__)

    cache_key = safe_memo_cache_key(method_name, args, kwargs)

    if defined?(@__safe_memo_mutex__) && @__safe_memo_mutex__
      @__safe_memo_mutex__.synchronize do
        @__safe_memo_cache__.key?(cache_key)
      end
    else
      @__safe_memo_cache__.key?(cache_key)
    end
  end

  def memo_count(*method_name)
    return 0 unless defined?(@__safe_memo_cache__)

    scoped_method = safe_memo_scoped_method(method_name)

    if defined?(@__safe_memo_mutex__) && @__safe_memo_mutex__
      @__safe_memo_mutex__.synchronize do
        safe_memo_count_for(scoped_method)
      end
    else
      safe_memo_count_for(scoped_method)
    end
  end

  def memo_keys(*method_name)
    return [] unless defined?(@__safe_memo_cache__)

    scoped_method = safe_memo_scoped_method(method_name)

    if defined?(@__safe_memo_mutex__) && @__safe_memo_mutex__
      @__safe_memo_mutex__.synchronize do
        safe_memo_keys_for(scoped_method)
      end
    else
      safe_memo_keys_for(scoped_method)
    end
  end

  def memo_values(*method_name)
    return [] unless defined?(@__safe_memo_cache__)

    scoped_method = safe_memo_scoped_method(method_name)

    if defined?(@__safe_memo_mutex__) && @__safe_memo_mutex__
      @__safe_memo_mutex__.synchronize do
        safe_memo_values_for(scoped_method)
      end
    else
      safe_memo_values_for(scoped_method)
    end
  end

  def reset_memo(method_name, *args, **kwargs)
    method_name = method_name.to_sym

    return unless defined?(@__safe_memo_cache__)

    matcher =
      if args.empty? && kwargs.empty?
        ->(key) { key[0] == method_name }
      else
        cache_key = safe_memo_cache_key(method_name, args, kwargs)
        ->(key) { key == cache_key }
      end

    if defined?(@__safe_memo_mutex__) && @__safe_memo_mutex__
      @__safe_memo_mutex__.synchronize do
        @__safe_memo_cache__.delete_if { |key, _| matcher.call(key) }
      end
    else
      @__safe_memo_cache__.delete_if { |key, _| matcher.call(key) }
    end
  end

  def reset_all_memos
    if defined?(@__safe_memo_mutex__) && @__safe_memo_mutex__
      @__safe_memo_mutex__.synchronize do
        @__safe_memo_cache__ = {}
      end
    else
      @__safe_memo_cache__ = {}
    end
  end

  private

  def safe_memo_scoped_method(method_name)
    raise ArgumentError, "expected 0 or 1 arguments" if method_name.length > 1

    method_name.first&.to_sym
  end

  def safe_memo_count_for(method_name)
    cache = @__safe_memo_cache__
    return 0 unless cache
    return cache.length unless method_name

    cache.count { |key, _| key[0] == method_name }
  end

  def safe_memo_keys_for(method_name)
    cache = @__safe_memo_cache__
    return [] unless cache

    keys = cache.keys

    if method_name
      keys
        .select { |key| key[0] == method_name }
        .map { |(_, args, kwargs)| {args: args, kwargs: kwargs} }
    else
      keys.map { |(name, args, kwargs)| {method: name, args: args, kwargs: kwargs} }
    end
  end

  def safe_memo_values_for(method_name)
    cache = @__safe_memo_cache__
    return [] unless cache

    entries = cache.to_a

    if method_name
      entries
        .select { |(cache_key, _)| cache_key[0] == method_name }
        .map do |(cache_key, value)|
          _, args, kwargs = cache_key
          {args: args, kwargs: kwargs, value: value}
        end
    else
      entries.map do |(cache_key, value)|
        name, args, kwargs = cache_key
        {method: name, args: args, kwargs: kwargs, value: value}
      end
    end
  end

  def safe_memo_cache_key(method_name, args, kwargs)
    [method_name.to_sym, args, kwargs]
  end
end
