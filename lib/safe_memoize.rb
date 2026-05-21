# frozen_string_literal: true

require_relative "safe_memoize/version"
require_relative "safe_memoize/configuration"
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
require_relative "safe_memoize/instance_methods"

module SafeMemoize
  class Error < StandardError; end

  include InstanceMethods

  def self.prepended(base)
    base.extend(ClassMethods)
  end

  def self.configure
    yield configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.reset_configuration!
    @configuration = Configuration.new
  end

  def self.deprecate(subject, message:, horizon:)
    text = "[SafeMemoize] #{subject} is deprecated and will be removed in #{horizon}. #{message}"
    handler = configuration.on_deprecation
    handler ? handler.call(text) : warn(text)
  end
end
