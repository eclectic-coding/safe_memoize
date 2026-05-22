# frozen_string_literal: true

module SafeMemoize
  # @api private
  module HooksMethods
    NOTIFICATION_EVENT_NAMES = {
      on_hit: "cache_hit.safe_memoize",
      on_miss: "cache_miss.safe_memoize",
      on_evict: "cache_evict.safe_memoize",
      on_expire: "cache_expire.safe_memoize",
      on_store: "cache_store.safe_memoize"
    }.freeze

    private

    def memo_hook_store
      @__safe_memo_hooks__ ||= {on_expire: [], on_evict: [], on_hit: [], on_miss: [], on_store: []}
    end

    def register_memo_hook(hook_type, &block)
      raise ArgumentError, "block required" unless block

      valid_hooks = [:on_expire, :on_evict, :on_hit, :on_miss, :on_store]
      raise ArgumentError, "invalid hook type: #{hook_type}" unless valid_hooks.include?(hook_type)

      memo_hook_store[hook_type] << block
    end

    def call_memo_hooks(hook_type, cache_key, record)
      hooks = memo_hook_store[hook_type] || []
      hooks.each do |hook|
        hook.call(cache_key, record)
      rescue => error
        handler = SafeMemoize.configuration.on_hook_error
        if handler
          handler.call(error, hook_type, cache_key)
        else
          warn "[SafeMemoize] Hook error in #{hook_type}: #{error.message}"
        end
      end

      safe_memo_notify(hook_type, cache_key) if SafeMemoize.configuration.active_support_notifications

      if (client = SafeMemoize.configuration.statsd_client)
        Adapters::StatsD.dispatch(client, hook_type, cache_key, self.class.name)
      end
    end

    def safe_memo_notify(hook_type, cache_key)
      return unless defined?(ActiveSupport::Notifications)

      asn = ActiveSupport::Notifications
      return unless asn.respond_to?(:instrument)

      event = NOTIFICATION_EVENT_NAMES[hook_type]
      return unless event

      asn.instrument(event, {
        method: cache_key[0],
        key: cache_key,
        class: self.class.name
      })
    end

    def _clear_memo_hooks(hook_type = nil)
      if hook_type
        memo_hook_store[hook_type] = []
      else
        @__safe_memo_hooks__ = {on_expire: [], on_evict: [], on_hit: [], on_miss: [], on_store: []}
      end
    end
  end
end
