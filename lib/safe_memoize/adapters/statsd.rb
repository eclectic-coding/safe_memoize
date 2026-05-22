# frozen_string_literal: true

module SafeMemoize
  module Adapters
    # Optional StatsD adapter.
    #
    # Routes SafeMemoize lifecycle events to any StatsD-compatible client
    # (any object that responds to +#increment+).
    #
    # Configure via {Configuration#statsd_client}:
    #
    #   SafeMemoize.configure do |c|
    #     c.statsd_client = Datadog::Statsd.new
    #   end
    #
    # Emitted metrics:
    #
    # | Metric | Fires on |
    # |---|---|
    # | +safe_memoize.hit+ | cache hit |
    # | +safe_memoize.miss+ | cache miss |
    # | +safe_memoize.store+ | value written |
    # | +safe_memoize.evict+ | LRU eviction |
    # | +safe_memoize.expire+ | TTL expiration |
    #
    # Every metric is tagged with +method:<name>+ and +class:<name>+.
    # Client errors are rescued and warned rather than raised.
    module StatsD
      # @api private
      METRIC_NAMES = {
        on_hit: "safe_memoize.hit",
        on_miss: "safe_memoize.miss",
        on_evict: "safe_memoize.evict",
        on_expire: "safe_memoize.expire",
        on_store: "safe_memoize.store"
      }.freeze

      # Dispatches a lifecycle event to the StatsD client.
      #
      # @param client [Object] a StatsD-compatible client responding to +#increment+
      # @param hook_type [Symbol] one of the keys in {METRIC_NAMES}
      # @param cache_key [Array] the internal cache key (first element is the method name)
      # @param class_name [String, nil]
      # @return [void]
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
