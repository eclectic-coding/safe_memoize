# frozen_string_literal: true

module SafeMemoize
  # Per-instance cache metrics: hit/miss counts and average computation time.
  module PublicMetricsMethods
    # Returns aggregate metrics across all memoized methods on this instance.
    #
    # @return [Hash] with keys +:total_hits+, +:total_misses+, +:hit_rate+,
    #   +:miss_rate+, +:average_computation_time+, and +:entries+ (one entry
    #   per cached argument combination)
    def cache_stats
      with_memo_lock do
        metrics = memo_metrics_store
        return empty_stats if metrics.empty?

        aggregate_metrics(metrics, include_method: true)
      end
    end

    # Returns metrics for a single memoized method.
    #
    # @param method_name [Symbol, String]
    # @return [Hash] same shape as {#cache_stats} but scoped to one method,
    #   with an extra +:method+ key
    def cache_stats_for(method_name)
      method_name = method_name.to_sym

      with_memo_lock do
        metrics = memo_metrics_store.select { |key, _| key[0] == method_name }
        return empty_stats.merge(method: method_name) if metrics.empty?

        aggregate_metrics(metrics, include_method: false).merge(method: method_name)
      end
    end

    # Returns the overall cache hit rate as a percentage (0.0–100.0).
    # @return [Float]
    def cache_hit_rate
      cache_stats[:hit_rate]
    end

    # Returns the overall cache miss rate as a percentage (0.0–100.0).
    # @return [Float]
    def cache_miss_rate
      cache_stats[:miss_rate]
    end

    # Resets hit/miss counters, either for one method or for all methods.
    #
    # @param method_name [Symbol, String, nil] when given, resets only that method's
    #   metrics; when +nil+, resets all
    # @return [void]
    def cache_metrics_reset(method_name = nil)
      with_memo_lock do
        if method_name
          _reset_cache_metrics_for(method_name.to_sym)
        else
          _reset_cache_metrics
        end
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
