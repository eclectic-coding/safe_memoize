# frozen_string_literal: true

module SafeMemoize
  module CacheStoreMethods
    private

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
  end
end

