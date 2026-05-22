# frozen_string_literal: true

module SafeMemoize
  module Rails
    # Rack middleware that resets all thread-tracked memoized instances at the
    # end of each request. Useful for service objects that are instantiated
    # per-request and register themselves via `SafeMemoize::Rails.track(self)`.
    #
    # Add to your Rack stack in config/application.rb:
    #   config.middleware.use SafeMemoize::Rails::Middleware
    class Middleware
      def initialize(app)
        @app = app
      end

      # @param env [Hash] Rack environment
      # @return [Array] Rack response triplet
      def call(env)
        @app.call(env)
      ensure
        SafeMemoize::Rails.reset_tracked!
      end
    end
  end
end
