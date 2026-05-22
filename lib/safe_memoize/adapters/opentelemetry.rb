# frozen_string_literal: true

module SafeMemoize
  module Adapters
    module OpenTelemetry
      SPAN_NAME = "safe_memoize.compute"

      def self.trace(tracer, method_name, class_name)
        return yield unless tracer&.respond_to?(:in_span)

        tracer.in_span(SPAN_NAME, attributes: {
          "safe_memoize.method" => method_name.to_s,
          "safe_memoize.class" => class_name.to_s,
          "safe_memoize.cache_hit" => false
        }) { yield }
      end
    end
  end
end
