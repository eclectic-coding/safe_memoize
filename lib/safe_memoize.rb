# frozen_string_literal: true

require_relative "safe_memoize/version"
require_relative "safe_memoize/configuration"
require_relative "safe_memoize/extension"
require_relative "safe_memoize/stores/base"
require_relative "safe_memoize/stores/memory"
require_relative "safe_memoize/adapters/statsd"
require_relative "safe_memoize/adapters/opentelemetry"
require_relative "safe_memoize/adapters/concurrent_ruby"
require_relative "safe_memoize/class_methods"
require_relative "safe_memoize/public_methods"
require_relative "safe_memoize/cache_store_methods"
require_relative "safe_memoize/cache_record_methods"
require_relative "safe_memoize/inspection_methods"
require_relative "safe_memoize/hooks_methods"
require_relative "safe_memoize/cache_metrics_methods"
require_relative "safe_memoize/public_metrics_methods"
require_relative "safe_memoize/custom_key_methods"
require_relative "safe_memoize/public_custom_key_methods"
require_relative "safe_memoize/lru_methods"
require_relative "safe_memoize/fiber_local_methods"
require_relative "safe_memoize/ractor_shared_methods"
require_relative "safe_memoize/instance_methods"

# Thread-safe memoization for Ruby that correctly handles +nil+ and +false+ values.
#
# Prepend this module into any class, then call {ClassMethods#memoize} to wrap
# instance methods with a per-instance cache backed by a +Mutex+.
#
# @example Basic usage
#   class UserService
#     prepend SafeMemoize
#
#     def current_user
#       User.find_by(session_id: session_id)
#     end
#     memoize :current_user
#   end
#
# @example With TTL and LRU cap
#   class ApiClient
#     prepend SafeMemoize
#
#     def fetch(id)
#       http_get("/items/#{id}")
#     end
#     memoize :fetch, ttl: 60, max_size: 500
#   end
#
# @see ClassMethods#memoize
# @see https://github.com/eclectic-coding/safe_memoize README
module SafeMemoize
  # Base class for all SafeMemoize-specific exceptions.
  # Rescue this to catch any error raised by the library itself.
  class Error < StandardError; end

  # @api private — sentinel distinguishing "not passed" from explicit nil/false in memoize kwargs
  UNSET = Object.new.freeze

  # @api private
  SHARED_CACHE_REGISTRY = {}
  # @api private
  SHARED_CACHE_MUTEX = Mutex.new

  # @api private
  EXTENSION_REGISTRY = {}
  # @api private
  EXTENSION_MUTEX = Mutex.new

  include InstanceMethods

  # @api private
  def self.prepended(base)
    base.extend(ClassMethods)
  end

  # Yields the global {Configuration} object for mutation.
  #
  # @example
  #   SafeMemoize.configure do |c|
  #     c.default_ttl = 300
  #   end
  #
  # @yield [config] The current {Configuration} instance.
  # @yieldparam config [Configuration]
  # @return [void]
  def self.configure
    yield configuration
  end

  # Returns the global {Configuration} instance, creating it on first access.
  #
  # @return [Configuration]
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Resets the global configuration to all defaults.
  #
  # Useful in test suites to prevent configuration leaking between examples.
  #
  # @return [Configuration] the new blank configuration
  def self.reset_configuration!
    @configuration = Configuration.new
  end

  # Emits a structured deprecation warning through the configured handler.
  #
  # @param subject [String] short identifier of the deprecated symbol
  # @param message [String] migration instructions
  # @param horizon [String] version when the symbol will be removed (e.g. +"v2.0.0"+)
  # @return [void]
  def self.deprecate(subject, message:, horizon:)
    text = "[SafeMemoize] #{subject} is deprecated and will be removed in #{horizon}. #{message}"
    handler = configuration.on_deprecation
    handler ? handler.call(text) : warn(text)
  end

  # Returns the named shared cache store, creating a new in-process
  # {Stores::Memory} instance if one has not been registered under +name+.
  #
  # Use {register_shared_cache} to supply a custom adapter (e.g. Redis) before
  # any class that references the same name is loaded.
  #
  # @param name [String] the logical cache name
  # @return [Stores::Base]
  def self.shared_cache(name)
    SHARED_CACHE_MUTEX.synchronize do
      SHARED_CACHE_REGISTRY[name] ||= Stores::Memory.new
    end
  end

  # Registers a custom store under +name+, replacing any existing entry.
  #
  # Must be called *before* any class that references +name+ via +shared_cache:+
  # is loaded, because the store is captured at +memoize+ definition time.
  #
  # @param name [String] the logical cache name
  # @param store [Stores::Base] any {Stores::Base} subclass instance
  # @return [Stores::Base] the registered store
  # @raise [ArgumentError] if +store+ is not a {Stores::Base} instance
  def self.register_shared_cache(name, store)
    unless store.is_a?(Stores::Base)
      raise ArgumentError, "store must be a SafeMemoize::Stores::Base instance (got #{store.class})"
    end
    SHARED_CACHE_MUTEX.synchronize { SHARED_CACHE_REGISTRY[name] = store }
  end

  # Clears all entries in the named shared cache without removing it from the
  # registry. A no-op when no cache is registered under +name+.
  #
  # @param name [String]
  # @return [void]
  def self.clear_shared_cache(name)
    SHARED_CACHE_MUTEX.synchronize { SHARED_CACHE_REGISTRY[name]&.clear }
  end

  # Removes the named shared cache from the registry entirely.
  # Subsequent +shared_cache(name)+ calls will create a fresh store.
  #
  # @param name [String]
  # @return [Stores::Base, nil] the removed store, or +nil+ if not present
  def self.drop_shared_cache(name)
    SHARED_CACHE_MUTEX.synchronize { SHARED_CACHE_REGISTRY.delete(name) }
  end

  # Returns a snapshot of the current registry as a plain +Hash+.
  #
  # @return [Hash{String => Stores::Base}]
  def self.shared_caches
    SHARED_CACHE_MUTEX.synchronize { SHARED_CACHE_REGISTRY.dup }
  end

  # Removes all named shared caches from the registry.
  #
  # Useful in test suite +after+ hooks to prevent state leaking between examples.
  #
  # @return [void]
  def self.reset_shared_caches!
    SHARED_CACHE_MUTEX.synchronize { SHARED_CACHE_REGISTRY.clear }
  end

  # Registers an extension under +name+.
  #
  # An extension is any Ruby object that optionally responds to the
  # {Extension} interface: {Extension#handled_options}, {Extension#process_memoize_option},
  # and {Extension#dispatch_cache_event}. Use {Extension} as a mixin to get a
  # convenient DSL for defining these.
  #
  # @param name [Symbol, String] a unique identifier for this extension
  # @param extension [Object] the extension object or module
  # @return [Object] the registered extension
  def self.register_extension(name, extension)
    EXTENSION_MUTEX.synchronize { EXTENSION_REGISTRY[name.to_sym] = extension }
  end

  # Removes an extension from the registry.
  #
  # @param name [Symbol, String]
  # @return [Object, nil] the removed extension, or +nil+ if not present
  def self.unregister_extension(name)
    EXTENSION_MUTEX.synchronize { EXTENSION_REGISTRY.delete(name.to_sym) }
  end

  # Returns a snapshot of all registered extensions as a +Hash+.
  #
  # @return [Hash{Symbol => Object}]
  def self.extensions
    EXTENSION_MUTEX.synchronize { EXTENSION_REGISTRY.dup }
  end

  # Removes all registered extensions.
  #
  # Useful in test suite +after+ hooks to prevent state leaking between examples.
  #
  # @return [void]
  def self.reset_extensions!
    EXTENSION_MUTEX.synchronize { EXTENSION_REGISTRY.clear }
  end

  # Returns the first registered extension that declares it handles +option_name+,
  # or +nil+ if none does.
  #
  # @param option_name [Symbol]
  # @return [Object, nil]
  def self.extension_for_option(option_name)
    sym = option_name.to_sym
    EXTENSION_MUTEX.synchronize do
      EXTENSION_REGISTRY.values.find do |ext|
        ext.respond_to?(:handled_options) && ext.handled_options.include?(sym)
      end
    end
  end

  # Dispatches a cache lifecycle event to all registered extensions that
  # respond to +dispatch_cache_event+.
  #
  # @api private
  def self.dispatch_extension_events(event_type, klass, method_name, cache_key, record)
    exts = EXTENSION_MUTEX.synchronize { EXTENSION_REGISTRY.values.dup }
    exts.each do |ext|
      ext.dispatch_cache_event(event_type, klass, method_name, cache_key, record) if ext.respond_to?(:dispatch_cache_event)
    end
  end
end
