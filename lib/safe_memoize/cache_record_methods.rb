# frozen_string_literal: true

module SafeMemoize
  module CacheRecordMethods
    private

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
      {value: value, expires_at: expires_at, cached_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)}
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
      cache.delete_if do |cache_key, record|
        if !memo_record_live?(record)
          call_memo_hooks(:on_expire, cache_key, record)
          lru_remove(cache_key[0], cache_key)
          true
        else
          false
        end
      end
    end
  end
end
