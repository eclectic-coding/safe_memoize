# frozen_string_literal: true

module SafeMemoize
  # @api private
  module CustomKeyMethods
    private

    def custom_key_store
      @__safe_memo_custom_keys__ ||= {}
    end

    def register_custom_key(method_name, &block)
      raise ArgumentError, "block required" unless block

      method_name = method_name.to_sym
      custom_key_store[method_name] = block
    end

    def compute_cache_key(method_name, args, kwargs)
      method_name = method_name.to_sym

      ns = __safe_memo_resolve_namespace__(method_name)
      effective_name = ns ? :"#{ns}:#{method_name}" : method_name

      # Instance-level key generator takes priority over class-level
      key_block = custom_key_store[method_name] ||
        self.class.send(:__safe_memo_class_key_generators__)[method_name]

      if key_block
        [effective_name, key_block.call(*args, **kwargs)]
      else
        bust_block = self.class.send(:__safe_memo_class_cache_bust_generators__)[method_name]
        if bust_block
          token = bust_block.is_a?(Symbol) ? send(bust_block) : instance_exec(&bust_block)
          [effective_name, [deep_freeze_copy(args), deep_freeze_copy(kwargs), token]]
        else
          safe_memo_cache_key(effective_name, args, kwargs)
        end
      end
    end

    def _clear_custom_keys
      @__safe_memo_custom_keys__ = {}
    end
  end
end
