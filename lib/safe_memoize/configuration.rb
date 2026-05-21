# frozen_string_literal: true

module SafeMemoize
  class Configuration
    attr_accessor :default_ttl, :default_max_size, :on_deprecation, :on_hook_error

    def initialize
      @default_ttl = nil
      @default_max_size = nil
      @on_deprecation = nil
      @on_hook_error = nil
    end
  end
end
