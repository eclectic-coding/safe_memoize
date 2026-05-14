# frozen_string_literal: true

module SafeMemoize
  module PublicMetricsMethods
    def cache_stats
      with_memo_lock do
        metrics = memo_metrics_store

        if metrics.empty?
          return {
            total_hits: 0,
            total_misses: 0,
            hit_rate: 0.0,
            miss_rate: 0.0,
            average_computation_time: 0.0,
            entries: []
          }
        end

        total_hits = metrics.values.sum { |m| m[:hits] }
        total_misses = metrics.values.sum { |m| m[:misses] }
        total_time = metrics.values.sum { |m| m[:total_time] }
        total_calls = total_hits + total_misses

        hit_rate = total_calls.zero? ? 0.0 : (total_hits.to_f / total_calls * 100).round(2)
        miss_rate = total_calls.zero? ? 0.0 : (total_misses.to_f / total_calls * 100).round(2)
        avg_time = total_misses.zero? ? 0.0 : (total_time / total_misses).round(6)

        entries = metrics.map do |cache_key, stats|
          method_name, args, _kwargs = cache_key
          entry_hit_rate = if (stats[:hits] + stats[:misses]).zero?
            0.0
          else
            (stats[:hits].to_f / (stats[:hits] + stats[:misses]) * 100).round(2)
          end

          {
            method: method_name,
            args: args,
            hits: stats[:hits],
            misses: stats[:misses],
            hit_rate: entry_hit_rate,
            computation_time: stats[:total_time].round(6)
          }
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
    end

    def cache_stats_for(method_name)
      method_name = method_name.to_sym

      with_memo_lock do
        metrics = memo_metrics_store
        method_metrics = metrics.select { |key, _| key[0] == method_name }

        if method_metrics.empty?
          return {
            method: method_name,
            total_hits: 0,
            total_misses: 0,
            hit_rate: 0.0,
            miss_rate: 0.0,
            average_computation_time: 0.0,
            entries: []
          }
        end

        total_hits = method_metrics.values.sum { |m| m[:hits] }
        total_misses = method_metrics.values.sum { |m| m[:misses] }
        total_time = method_metrics.values.sum { |m| m[:total_time] }
        total_calls = total_hits + total_misses

        hit_rate = total_calls.zero? ? 0.0 : (total_hits.to_f / total_calls * 100).round(2)
        miss_rate = total_calls.zero? ? 0.0 : (total_misses.to_f / total_calls * 100).round(2)
        avg_time = total_misses.zero? ? 0.0 : (total_time / total_misses).round(6)

        entries = method_metrics.map do |cache_key, stats|
          _method, args, _kwargs = cache_key
          entry_hit_rate = if (stats[:hits] + stats[:misses]).zero?
            0.0
          else
            (stats[:hits].to_f / (stats[:hits] + stats[:misses]) * 100).round(2)
          end

          {
            args: args,
            hits: stats[:hits],
            misses: stats[:misses],
            hit_rate: entry_hit_rate,
            computation_time: stats[:total_time].round(6)
          }
        end

        {
          method: method_name,
          total_hits: total_hits,
          total_misses: total_misses,
          hit_rate: hit_rate,
          miss_rate: miss_rate,
          average_computation_time: avg_time,
          entries: entries
        }
      end
    end

    def cache_hit_rate
      stats = cache_stats
      stats[:hit_rate]
    end

    def cache_miss_rate
      stats = cache_stats
      stats[:miss_rate]
    end

    def cache_metrics_reset
      with_memo_lock do
        _reset_cache_metrics
      end
    end
  end
end
