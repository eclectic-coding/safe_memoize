# frozen_string_literal: true

require_relative "safe_memoize/version"
require_relative "safe_memoize/class_methods"

module SafeMemoize
  class Error < StandardError; end

  def self.prepended(base)
    base.extend(ClassMethods)
  end


  def memoized?(method_name, *args, **kwargs, &block)
    return false if block

    cache_key = safe_memo_cache_key(method_name, args, kwargs)

    with_memo_lock do
      memo_cache_hit?(cache_key)
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
    !!memo_cache_record(cache_key)
  end

  def memo_cache_record(cache_key)
    cache = memo_cache_or_nil
    return nil unless cache

    record = cache[cache_key]
    return nil unless memo_record_live?(record)

    record
  end

  def memo_cache_read(cache_key)
    record = memo_cache_record(cache_key)
    return nil unless record

    memo_record_value(record)
  end

  def memo_fetch_or_store(cache_key, expires_at: nil)
    memo_mutex!.synchronize do
      @__safe_memo_cache__ ||= {}

      record = @__safe_memo_cache__[cache_key]

      if memo_record_live?(record)
        memo_record_value(record)
      else
        value = yield
        @__safe_memo_cache__[cache_key] = memo_record(value, expires_at: expires_at)
        value
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

  def memo_ttl(ttl)
    return nil if ttl.nil?

    ttl = Float(ttl)
    raise ArgumentError, "ttl must be non-negative" if ttl < 0

    ttl
  rescue ArgumentError, TypeError
    raise ArgumentError, "ttl must be a non-negative number"
  end

  def memo_expires_at(ttl)
    return nil unless ttl

    Process.clock_gettime(Process::CLOCK_MONOTONIC) + ttl
  end

  def memo_record(value, expires_at:)
    { value: value, expires_at: expires_at }
  end

  def memo_record_value(record)
    record[:value]
  end

  def memo_record_live?(record)
    return false unless record

    expires_at = record[:expires_at]
    return true unless expires_at

    expires_at > Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def memo_prune_expired_entries!(cache)
    cache.delete_if { |_, record| !memo_record_live?(record) }
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

    memo_prune_expired_entries!(cache)
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

    payload = { args: args, kwargs: kwargs }
    payload[:method] = method_name if include_method
    payload[:value] = memo_record_value(value) if include_value
    payload
  end

  def safe_memo_cache_key(method_name, args, kwargs)
    [method_name.to_sym, args, kwargs]
  end
end
