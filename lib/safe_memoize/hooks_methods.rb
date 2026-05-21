# frozen_string_literal: true

module SafeMemoize
  module HooksMethods
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
