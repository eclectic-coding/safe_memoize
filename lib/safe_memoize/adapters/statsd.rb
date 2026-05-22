# frozen_string_literal: true

module SafeMemoize
  module Adapters
    module StatsD
      METRIC_NAMES = {
        on_hit: "safe_memoize.hit",
        on_miss: "safe_memoize.miss",
        on_evict: "safe_memoize.evict",
        on_expire: "safe_memoize.expire",
        on_store: "safe_memoize.store"
      }.freeze

      def self.dispatch(client, hook_type, cache_key, class_name)
        metric = METRIC_NAMES[hook_type]
        return unless metric

        tags = ["method:#{cache_key[0]}", "class:#{class_name}"]
        client.increment(metric, tags: tags)
      rescue => error
        warn "[SafeMemoize] StatsD dispatch error: #{error.message}"
      end
    end
  end
end
