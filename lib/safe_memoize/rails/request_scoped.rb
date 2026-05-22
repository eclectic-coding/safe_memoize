# frozen_string_literal: true

module SafeMemoize
  module Rails
    # Include in a Rails controller to automatically reset instance memos after
    # each request. In non-controller classes (service objects, models), include
    # it to gain `reset_request_memos` and call it manually at the end of a
    # request or job.
    #
    # The class must also `prepend SafeMemoize` for `reset_all_memos` to exist.
    #
    # Example — controller:
    #   class ApplicationController < ActionController::Base
    #     prepend SafeMemoize
    #     include SafeMemoize::Rails::RequestScoped
    #   end
    #
    # Example — service object with middleware tracking:
    #   class ReportService
    #     prepend SafeMemoize
    #     include SafeMemoize::Rails::RequestScoped
    #
    #     def initialize
    #       SafeMemoize::Rails.track(self)
    #     end
    #   end
    module RequestScoped
      # @api private
      def self.included(base)
        base.after_action :reset_all_memos if base.respond_to?(:after_action)
      end

      # Resets all memoized values on this instance. Delegates to {PublicMethods#reset_all_memos}.
      # @return [void]
      def reset_request_memos
        reset_all_memos
      end
    end
  end
end
