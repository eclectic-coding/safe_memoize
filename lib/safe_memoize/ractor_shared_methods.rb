# frozen_string_literal: true

module SafeMemoize
  # Class-level methods for Ractor-safe shared caching.
  #
  # Mixed into a class (via ClassMethods) when any method is memoized with
  # +shared: true, ractor_safe: true+. The class owns a supervisor +Ractor+ that
  # holds the mutable cache hash. All cache reads and writes are serialized through
  # the supervisor's message loop, removing the need for a +Mutex+ (which is not
  # Ractor-shareable).
  #
  # Constraints for +ractor_safe: true+ memoization:
  # - Cached return values are made Ractor-shareable via +Ractor.make_shareable+
  #   (deep-frozen in place). Ensure return values can be frozen.
  # - +if:+, +unless:+, +max_size:+, +ttl_refresh:+, +key:+, and +store:+ are
  #   incompatible and raise +ArgumentError+ at +memoize+ time.
  # - When calling a ractor-safe memoized method from the main Ractor with multiple
  #   threads, responses are matched by thread identity so concurrent callers do not
  #   consume each other's replies.
  module RactorSharedMethods
    # Clears one or all entries from the Ractor-safe shared cache.
    #
    # @param method_name [Symbol, String]
    # @param args [Array] positional args identifying a specific entry; omit to clear all
    # @param kwargs [Hash]
    # @return [void]
    def reset_ractor_memo(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      sup = @__safe_memo_ractor_supervisor__
      return unless sup

      if args.empty? && kwargs.empty?
        __ractor_cache_send__(sup, :delete_all, method_name)
      else
        key = Ractor.make_shareable([method_name, args.freeze, kwargs.freeze])
        __ractor_cache_send__(sup, :delete_one, key)
      end
    end

    # Clears the entire Ractor-safe shared cache for this class.
    # @return [void]
    def reset_all_ractor_memos
      sup = @__safe_memo_ractor_supervisor__
      return unless sup

      __ractor_cache_send__(sup, :clear)
    end

    # Returns +true+ if a live entry exists in the Ractor-safe shared cache.
    #
    # @param method_name [Symbol, String]
    # @param args [Array]
    # @param kwargs [Hash]
    # @return [Boolean]
    def ractor_memoized?(method_name, *args, **kwargs)
      method_name = method_name.to_sym
      sup = @__safe_memo_ractor_supervisor__
      return false unless sup

      key = Ractor.make_shareable([method_name, args.freeze, kwargs.freeze])
      __ractor_cache_send__(sup, :memoized, key)
    end

    # Returns the number of live entries in the Ractor-safe shared cache.
    #
    # @param method_name [Symbol, String, nil] when given, counts only entries for
    #   that method; when +nil+, counts all.
    # @return [Integer]
    def ractor_memo_count(method_name = nil)
      sup = @__safe_memo_ractor_supervisor__
      return 0 unless sup

      __ractor_cache_send__(sup, :count, method_name&.to_sym)
    end

    private

    # Sends a message to the supervisor and blocks until the tagged response arrives.
    # Uses Thread.current.object_id as a per-call tag so concurrent threads in the
    # main Ractor do not steal each other's replies.
    def __ractor_cache_send__(supervisor, op, *args)
      tag = Thread.current.object_id
      msg = Ractor.make_shareable([Ractor.current, tag, op, *args])
      supervisor.send(msg)
      Ractor.receive_if { |m| m.is_a?(Array) && m[0] == tag }[1]
    end

    # Creates the supervisor Ractor that owns this class's Ractor-safe shared cache.
    # Must be called from the main Ractor at class-definition time.
    def __safe_memo_ractor_supervisor__
      # :nocov:
      @__safe_memo_ractor_supervisor__ ||= Ractor.new do
        cache = {}

        loop do
          caller_ractor, tag, op, *args = Ractor.receive
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          result = case op
          when :fetch
            key = args[0]
            record = cache[key]
            live = record && (record[:expires_at].nil? || record[:expires_at] > now)
            live ? {hit: true, record: record} : {hit: false, record: nil}

          when :store
            key, new_record = args
            existing = cache[key]
            live = existing && (existing[:expires_at].nil? || existing[:expires_at] > now)
            cache[key] = new_record unless live
            {stored: live ? existing : new_record}

          when :delete_all
            method_name = args[0]
            cache.delete_if { |k, _| k[0] == method_name }
            :ok

          when :delete_one
            cache.delete(args[0])
            :ok

          when :clear
            cache.clear
            :ok

          when :memoized
            key = args[0]
            record = cache[key]
            !!(record && (record[:expires_at].nil? || record[:expires_at] > now))

          when :count
            method_name = args[0]
            cache.count do |k, r|
              next false if r[:expires_at] && r[:expires_at] <= now
              method_name.nil? || k[0] == method_name
            end
          end

          response = Ractor.make_shareable([tag, result])
          caller_ractor.send(response)
        end
      end
      # :nocov:
    end
  end
end
