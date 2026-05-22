# frozen_string_literal: true

module SafeMemoize
  class Configuration
    attr_accessor :default_ttl, :default_max_size, :on_deprecation, :on_hook_error,
      :active_support_notifications, :statsd_client, :opentelemetry_tracer

    def initialize
      @default_ttl = nil
      @default_max_size = nil
      @on_deprecation = nil
      @on_hook_error = nil
      @active_support_notifications = false
      @statsd_client = nil
      @opentelemetry_tracer = nil
    end
  end
end
