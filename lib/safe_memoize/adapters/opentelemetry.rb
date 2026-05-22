# frozen_string_literal: true

module SafeMemoize
  # Optional adapters for external observability systems.
  # None are auto-required; load them explicitly when needed.
  module Adapters
    # Optional OpenTelemetry adapter.
    #
    # Wraps each cache-miss computation in an OpenTelemetry span so the time
    # spent computing uncached values is visible in distributed traces.
    #
    # Configure via {Configuration#opentelemetry_tracer}:
    #
    #   SafeMemoize.configure do |c|
    #     c.opentelemetry_tracer = OpenTelemetry.tracer_provider.tracer("safe_memoize")
    #   end
    #
    # Each span is named {SPAN_NAME} and carries the attributes
    # +safe_memoize.method+, +safe_memoize.class+, and +safe_memoize.cache_hit+.
    # Falls back to untraced execution when no tracer is configured or the tracer
    # does not respond to +#in_span+.
    module OpenTelemetry
      # The name given to every span created by this adapter.
      SPAN_NAME = "safe_memoize.compute"

      # Wraps the block in a span if a tracer is available; otherwise yields directly.
      #
      # @param tracer [Object, nil] an object responding to +#in_span+
      # @param method_name [Symbol, String]
      # @param class_name [String, nil]
      # @yield the computation block (cache-miss path)
      # @return [Object] the result of the block
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
