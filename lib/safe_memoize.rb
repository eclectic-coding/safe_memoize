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

          # Fast path: check without lock
          return memo_cache_read(cache_key) if memo_cache_hit?(cache_key)

          memo_fetch_or_store(cache_key) { super(*args, **kwargs) }
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

    cache_key = safe_memo_cache_key(method_name, args, kwargs)

    with_memo_lock do
      with_memo_cache { |cache| cache.key?(cache_key) } || false
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

  def reset_memo(method_name, *args, **kwargs)
    method_name = method_name.to_sym

    matcher = memo_matcher_for(method_name, args, kwargs)

    with_memo_lock do
      with_memo_cache do |cache|
        cache.delete_if { |key, _| matcher.call(key) }
      end
    end
  end

  def reset_all_memos
    with_memo_lock do
      @__safe_memo_cache__ = {}
    end
  end

  private

  def safe_memo_scoped_method(method_name)
    raise ArgumentError, "expected 0 or 1 arguments" if method_name.length > 1

    method_name.first&.to_sym
  end

  def with_memo_lock
    if defined?(@__safe_memo_mutex__) && @__safe_memo_mutex__
      @__safe_memo_mutex__.synchronize { yield }
    else
      yield
    end
  end

  def memo_cache_or_nil
    return nil unless defined?(@__safe_memo_cache__)

    @__safe_memo_cache__
  end

  def memo_cache_hit?(cache_key)
    cache = memo_cache_or_nil
    cache&.key?(cache_key)
  end

  def memo_cache_read(cache_key)
    cache = memo_cache_or_nil
    cache && cache[cache_key]
  end

  def memo_fetch_or_store(cache_key)
    memo_mutex!.synchronize do
      @__safe_memo_cache__ ||= {}

      if @__safe_memo_cache__.key?(cache_key)
        @__safe_memo_cache__[cache_key]
      else
        @__safe_memo_cache__[cache_key] = yield
      end
    end
  end

  def memo_mutex!
    @__safe_memo_mutex__ ||= Mutex.new
  end

  def with_memo_cache
    cache = memo_cache_or_nil
    return nil unless cache

    yield cache
  end

  def memo_matcher_for(method_name, args, kwargs)
    if args.empty? && kwargs.empty?
      ->(key) { key[0] == method_name }
    else
      cache_key = safe_memo_cache_key(method_name, args, kwargs)
      ->(key) { key == cache_key }
    end
  end

  def memo_entries_for(method_name)
    cache = memo_cache_or_nil
    return [] unless cache

    entries = cache.to_a
    return entries unless method_name

    entries.select { |(cache_key, _)| cache_key[0] == method_name }
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
    method_name, args, kwargs = cache_key

    payload = {args: args, kwargs: kwargs}
    payload[:method] = method_name if include_method
    payload[:value] = value if include_value
    payload
  end

  def safe_memo_cache_key(method_name, args, kwargs)
    [method_name.to_sym, args, kwargs]
  end
end
