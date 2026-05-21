# frozen_string_literal: true

module SafeMemoize
  class Configuration
    attr_accessor :default_ttl, :default_max_size, :on_deprecation

    def initialize
      @default_ttl = nil
      @default_max_size = nil
      @on_deprecation = nil
    end
  end
end
