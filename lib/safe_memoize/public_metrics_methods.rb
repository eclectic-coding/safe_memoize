# frozen_string_literal: true

module SafeMemoize
  module PublicMetricsMethods
    def cache_stats
      with_memo_lock do
        metrics = memo_metrics_store
        return empty_stats if metrics.empty?

        aggregate_metrics(metrics, include_method: true)
      end
    end

    def cache_stats_for(method_name)
      method_name = method_name.to_sym

      with_memo_lock do
        metrics = memo_metrics_store.select { |key, _| key[0] == method_name }
        return empty_stats.merge(method: method_name) if metrics.empty?

        aggregate_metrics(metrics, include_method: false).merge(method: method_name)
      end
    end

    def cache_hit_rate
      cache_stats[:hit_rate]
    end

    def cache_miss_rate
      cache_stats[:miss_rate]
    end

    def cache_metrics_reset
      with_memo_lock do
        _reset_cache_metrics
      end
    end

    private

    def aggregate_metrics(metrics, include_method:)
      total_hits = metrics.values.sum { |m| m[:hits] }
      total_misses = metrics.values.sum { |m| m[:misses] }
      total_time = metrics.values.sum { |m| m[:total_time] }
      total_calls = total_hits + total_misses

      hit_rate = total_calls.zero? ? 0.0 : (total_hits.to_f / total_calls * 100).round(2)
      miss_rate = total_calls.zero? ? 0.0 : (total_misses.to_f / total_calls * 100).round(2)
      avg_time = total_misses.zero? ? 0.0 : (total_time / total_misses).round(6)

      entries = metrics.map do |cache_key, stats|
        method_name, args, _kwargs = cache_key
        entry_calls = stats[:hits] + stats[:misses]
        entry_hit_rate = entry_calls.zero? ? 0.0 : (stats[:hits].to_f / entry_calls * 100).round(2)

        entry = {args: args, hits: stats[:hits], misses: stats[:misses],
                 hit_rate: entry_hit_rate, computation_time: stats[:total_time].round(6)}
        entry[:method] = method_name if include_method
        entry
      end

      {
        total_hits: total_hits,
        total_misses: total_misses,
        hit_rate: hit_rate,
        miss_rate: miss_rate,
        average_computation_time: avg_time,
        entries: entries
      }
    end

    def empty_stats
      {total_hits: 0, total_misses: 0, hit_rate: 0.0, miss_rate: 0.0,
       average_computation_time: 0.0, entries: []}
    end
  end
end
