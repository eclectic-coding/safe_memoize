# frozen_string_literal: true

module SafeMemoize
  # Mixin for defining SafeMemoize extensions.
  #
  # Extend this module in any Ruby module or class that you want to register
  # as a SafeMemoize extension. It provides a DSL for declaring custom
  # +memoize+ options and global cache lifecycle event handlers.
  #
  # @example Defining an extension
  #   module MyExtension
  #     extend SafeMemoize::Extension
  #
  #     handles_option :active_record_bust do |value, method_name, _options|
  #       { cache_bust: -> { send(:updated_at) } }
  #     end
  #
  #     on_cache_event :miss do |klass, method_name, _cache_key, _record|
  #       Rails.logger.debug "cache miss: #{klass}##{method_name}"
  #     end
  #   end
  #
  #   SafeMemoize.register_extension(:active_record_bust, MyExtension)
  module Extension
    # Declares a custom +memoize+ option handled by this extension.
    #
    # The block is called at +memoize+ definition time whenever +option_name+
    # appears in the +memoize+ keyword arguments. It receives the option value,
    # the method name being memoized, and the full hash of other extension options
    # passed to that +memoize+ call. It must return a +Hash+ of standard
    # {ClassMethods#memoize} options to inject (e.g. +{ cache_bust: ... }+), or
    # +nil+/empty hash for no injection.
    #
    # @param option_name [Symbol]
    # @yieldparam value [Object] the option value supplied by the caller
    # @yieldparam method_name [Symbol] the method being memoized
    # @yieldparam all_options [Hash] other extension options in the same +memoize+ call
    # @yieldreturn [Hash, nil] standard memoize options to inject
    # @return [void]
    def handles_option(option_name, &processor)
      @__handled_options__ ||= {}
      @__handled_options__[option_name.to_sym] = processor
    end

    # Registers a global cache lifecycle event handler.
    #
    # The block fires after every matching cache event across *all* memoized
    # methods on all classes. Multiple event types can be listed in a single
    # call. Valid types are +:on_hit+, +:on_miss+, +:on_store+, +:on_expire+,
    # and +:on_evict+.
    #
    # Handlers execute on the main Ractor only; they are silently skipped from
    # worker Ractors.
    #
    # @param event_types [Array<Symbol>] one or more of +:on_hit+, +:on_miss+,
    #   +:on_store+, +:on_expire+, +:on_evict+
    # @yieldparam klass [Class] the class whose instance triggered the event
    # @yieldparam method_name [Symbol] bare method name (namespace stripped)
    # @yieldparam cache_key [Array] the full cache key
    # @yieldparam record [Hash, nil] the cache record (+value+, +expires_at+, +cached_at+)
    # @return [void]
    def on_cache_event(*event_types, &handler)
      @__event_handlers__ ||= {}
      event_types.each { |type| (@__event_handlers__[type.to_sym] ||= []) << handler }
    end

    # @api private
    def handled_options
      @__handled_options__&.keys || []
    end

    # @api private
    def process_memoize_option(option_name, value, method_name, all_options)
      processor = @__handled_options__&.[](option_name.to_sym)
      result = processor&.call(value, method_name, all_options)
      result.is_a?(Hash) ? result : {}
    end

    # @api private
    def dispatch_cache_event(event_type, klass, method_name, cache_key, record)
      return unless @__event_handlers__

      (@__event_handlers__[event_type] || []).each do |handler|
        handler.call(klass, method_name, cache_key, record)
      end
    end
  end
end
