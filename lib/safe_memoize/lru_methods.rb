# frozen_string_literal: true

module SafeMemoize
  module LruMethods
    private

    # Per-method LRU order: { method_name => { cache_key => true, ... } }
    # Ruby Hash insertion order gives LRU for free: oldest key first, newest last.
    def lru_order_store
      @__safe_memo_lru_order__ ||= {}
    end

    # Mark +cache_key+ as most recently used for +method_name+.
    def lru_touch(method_name, cache_key)
      method_store = lru_order_store[method_name] ||= {}
      method_store.delete(cache_key)
      method_store[cache_key] = true
    end

    # Evict the least-recently-used entry for +method_name+ when at +max_size+.
    # Must be called while holding the mutex.
    def lru_evict_if_over_limit(method_name, max_size)
      method_store = lru_order_store[method_name]
      return unless method_store && !method_store.empty?

      cache = @__safe_memo_cache__

      # Prune stale LRU references left behind by reset_memo calls.
      method_store.delete_if { |key, _| !cache&.key?(key) }

      return if method_store.size < max_size

      lru_cache_key = method_store.keys.first
      return unless lru_cache_key

      method_store.delete(lru_cache_key)
      record = cache&.delete(lru_cache_key)
      call_memo_hooks(:on_evict, lru_cache_key, record) if record
    end

    # Clear all LRU tracking state. Called by reset_all_memos.
    def lru_clear_all
      @__safe_memo_lru_order__ = {}
    end
  end
end
