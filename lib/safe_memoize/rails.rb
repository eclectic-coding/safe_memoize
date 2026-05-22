# frozen_string_literal: true

require "safe_memoize"
require_relative "rails/request_scoped"
require_relative "rails/middleware"

module SafeMemoize
  # Optional Rails integration. Not auto-required — add to your initializer:
  #   require "safe_memoize/rails"
  module Rails
    # Register an instance to have its memos reset at the end of the current
    # request (via Middleware). Thread-local; each thread maintains its own list.
    def self.track(instance)
      (Thread.current[:safe_memoize_tracked] ||= []) << instance
    end

    # Reset all tracked instances and clear the list. Called automatically by
    # Middleware after each request. Safe to call with an empty list.
    def self.reset_tracked!
      instances = Thread.current[:safe_memoize_tracked] || []
      instances.each do |instance|
        instance.reset_all_memos if instance.respond_to?(:reset_all_memos)
      end
    ensure
      Thread.current[:safe_memoize_tracked] = []
    end
  end
end
