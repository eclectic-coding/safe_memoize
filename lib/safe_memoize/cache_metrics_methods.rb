# frozen_string_literal: true

module SafeMemoize
  # @api private
  module CacheMetricsMethods
    private

    def memo_metrics_store
      @__safe_memo_metrics__ ||= {}
    end

    def record_cache_hit(cache_key)
      metrics = memo_metrics_store
      metrics[cache_key] ||= {hits: 0, misses: 0, total_time: 0.0}
      metrics[cache_key][:hits] += 1
    end

    def record_cache_miss(cache_key, computation_time)
      metrics = memo_metrics_store
      metrics[cache_key] ||= {hits: 0, misses: 0, total_time: 0.0}
      metrics[cache_key][:misses] += 1
      metrics[cache_key][:total_time] += computation_time
    end

    def _reset_cache_metrics
      @__safe_memo_metrics__ = {}
    end

    def _reset_cache_metrics_for(method_name)
      return unless defined?(@__safe_memo_metrics__) && @__safe_memo_metrics__

      effective = resolve_memo_key_name(method_name)
      @__safe_memo_metrics__.delete_if { |key, _| key[0] == effective }
    end
  end
end
