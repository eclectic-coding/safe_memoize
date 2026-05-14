# frozen_string_literal: true

require_relative "safe_memoize/version"
require_relative "safe_memoize/class_methods"
require_relative "safe_memoize/public_methods"
require_relative "safe_memoize/cache_store_methods"
require_relative "safe_memoize/cache_record_methods"
require_relative "safe_memoize/inspection_methods"
require_relative "safe_memoize/hooks_methods"
require_relative "safe_memoize/cache_metrics_methods"
require_relative "safe_memoize/public_metrics_methods"
require_relative "safe_memoize/instance_methods"

module SafeMemoize
  class Error < StandardError; end

  include InstanceMethods

  def self.prepended(base)
    base.extend(ClassMethods)
  end
end
