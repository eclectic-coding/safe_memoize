# frozen_string_literal: true

require_relative "safe_memoize/version"
require_relative "safe_memoize/configuration"
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
end
