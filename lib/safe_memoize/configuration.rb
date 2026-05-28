# frozen_string_literal: true

module SafeMemoize
  # Global configuration for SafeMemoize.
  #
  # Obtain an instance via {SafeMemoize.configure} or {SafeMemoize.configuration}.
  #
  # @example
  #   SafeMemoize.configure do |c|
  #     c.default_ttl = 300
  #     c.default_max_size = 100
  #     c.on_hook_error = ->(err, type, key) { Bugsnag.notify(err) }
  #   end
  class Configuration
    # @return [Numeric, nil] Default TTL (seconds) applied to every {ClassMethods#memoize}
    #   call that does not specify its own +ttl:+. +nil+ means no expiry.
    attr_accessor :default_ttl

    # @return [Integer, nil] Default LRU size cap applied to every {ClassMethods#memoize}
    #   call that does not specify its own +max_size:+. +nil+ means unlimited.
    attr_accessor :default_max_size

    # @return [Proc, nil] Custom handler for deprecation warnings.
    #   Receives a single +String+ message. When +nil+, warnings are written to +$stderr+.
    attr_accessor :on_deprecation

    # @return [Proc, nil] Custom handler for errors raised inside lifecycle hooks.
    #   Receives +(Exception, Symbol hook_type, cache_key)+. When +nil+, a warning is
    #   written to +$stderr+ and the error is swallowed.
    attr_accessor :on_hook_error

    # @return [Boolean] When +true+, SafeMemoize emits +ActiveSupport::Notifications+
    #   events for cache hits, misses, stores, evictions, and expirations.
    #   Requires +activesupport+ to be loaded; has zero overhead when it is not.
    attr_accessor :active_support_notifications

    # @return [Object, nil] Any StatsD-compatible client (responds to +#increment+).
    #   When set, {Adapters::StatsD} routes lifecycle events to this client.
    attr_accessor :statsd_client

    # @return [Object, nil] An OpenTelemetry tracer (responds to +#in_span+).
    #   When set, {Adapters::OpenTelemetry} wraps each cache-miss computation in a span.
    attr_accessor :opentelemetry_tracer

    # @return [Stores::Base, nil] Default cache store applied to every {ClassMethods#memoize}
    #   call that does not specify its own +store:+. +nil+ uses the built-in per-instance
    #   hash cache. Methods using +max_size:+ or +shared:+ are incompatible with an external
    #   store and will silently continue using the per-instance hash even when this is set.
    attr_accessor :default_store

    # @return [String, nil] Global namespace prefix applied to every cache key produced by
    #   {ClassMethods#memoize}. Useful for versioned deployments (change the namespace to
    #   bust all in-flight cached values) and multi-tenant setups (scope keys to a tenant
    #   identifier). A class-level {ClassMethods#safe_memoize_namespace} or a per-method
    #   +namespace:+ option takes precedence over this value. +nil+ means no prefix.
    attr_accessor :namespace

    # @api private
    def initialize
      @default_ttl = nil
      @default_max_size = nil
      @on_deprecation = nil
      @on_hook_error = nil
      @active_support_notifications = false
      @statsd_client = nil
      @opentelemetry_tracer = nil
      @default_store = nil
      @namespace = nil
    end
  end
end
