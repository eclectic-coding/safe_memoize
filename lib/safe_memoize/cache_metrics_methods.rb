# frozen_string_literal: true

module SafeMemoize
  module CacheMetricsMethods
    private

    def memo_metrics_store
      @__safe_memo_metrics__ ||= {}
    end

    def record_cache_hit(method_name, args)
      cache_key = safe_memo_cache_key(method_name, args, {})
      metrics = memo_metrics_store
      metrics[cache_key] ||= {hits: 0, misses: 0, total_time: 0.0}
      metrics[cache_key][:hits] += 1
    end

    def record_cache_miss(method_name, args, computation_time)
      cache_key = safe_memo_cache_key(method_name, args, {})
      metrics = memo_metrics_store
      metrics[cache_key] ||= {hits: 0, misses: 0, total_time: 0.0}
      metrics[cache_key][:misses] += 1
      metrics[cache_key][:total_time] += computation_time
    end

    def _reset_cache_metrics
      @__safe_memo_metrics__ = {}
    end
  end
end
