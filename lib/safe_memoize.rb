# frozen_string_literal: true

require_relative "safe_memoize/version"

module SafeMemoize
  class Error < StandardError; end

  def self.prepended(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def memoize(method_name)
      method_name = method_name.to_sym

      mod = Module.new do
        define_method(method_name) do |*args, **kwargs, &block|
          # Blocks bypass cache entirely — they aren't comparable
          return super(*args, **kwargs, &block) if block

          cache_key = [method_name, args, kwargs]

          @__safe_memo_mutex__ ||= Mutex.new

          # Fast path: check without lock
          if defined?(@__safe_memo_cache__) && @__safe_memo_cache__.key?(cache_key)
            return @__safe_memo_cache__[cache_key]
          end

          # Slow path: lock and double-check
          @__safe_memo_mutex__.synchronize do
            @__safe_memo_cache__ ||= {}

            if @__safe_memo_cache__.key?(cache_key)
              @__safe_memo_cache__[cache_key]
            else
              @__safe_memo_cache__[cache_key] = super(*args, **kwargs)
            end
          end
        end
      end

      prepend mod
    end
  end

  def reset_memo(method_name)
    method_name = method_name.to_sym

    return unless defined?(@__safe_memo_cache__)

    if defined?(@__safe_memo_mutex__) && @__safe_memo_mutex__
      @__safe_memo_mutex__.synchronize do
        @__safe_memo_cache__.delete_if { |key, _| key[0] == method_name }
      end
    else
      @__safe_memo_cache__.delete_if { |key, _| key[0] == method_name }
    end
  end

  def reset_all_memos
    if defined?(@__safe_memo_mutex__) && @__safe_memo_mutex__
      @__safe_memo_mutex__.synchronize do
        @__safe_memo_cache__ = {}
      end
    else
      @__safe_memo_cache__ = {}
    end
  end
end
