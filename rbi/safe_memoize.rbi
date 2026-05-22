# typed: true

# Sorbet type stubs for the safe_memoize gem.
#
# These stubs cover every symbol listed in the public API guarantee
# (see README "Public API and versioning guarantee"). Opt-in extensions
# (SafeMemoize::Rails, SafeMemoize::Adapters::*) are included as well,
# but they are not part of the v1.0.0 semver guarantee.
#
# Usage: add `require "safe_memoize"` to your Sorbet ignore list if you
# use tapioca, or copy this file into sorbet/rbi/shims/ for manual setups.

module SafeMemoize
  VERSION = T.let(T.unsafe(nil), String)

  sig { params(base: T::Class[T.anything]).void }
  def self.prepended(base); end

  sig { params(blk: T.proc.params(config: SafeMemoize::Configuration).void).void }
  def self.configure(&blk); end

  sig { returns(SafeMemoize::Configuration) }
  def self.configuration; end

  sig { returns(SafeMemoize::Configuration) }
  def self.reset_configuration!; end

  sig { params(subject: String, message: String, horizon: String).void }
  def self.deprecate(subject, message:, horizon:); end

  class Configuration
    sig { returns(T.nilable(Numeric)) }
    attr_accessor :default_ttl

    sig { returns(T.nilable(Integer)) }
    attr_accessor :default_max_size

    sig { returns(T.nilable(T.proc.params(message: String).void)) }
    attr_accessor :on_deprecation

    sig { returns(T.nilable(T.proc.params(error: Exception, hook_type: Symbol, cache_key: T.untyped).void)) }
    attr_accessor :on_hook_error

    sig { returns(T::Boolean) }
    attr_accessor :active_support_notifications

    sig { returns(T.untyped) }
    attr_accessor :statsd_client

    sig { returns(T.untyped) }
    attr_accessor :opentelemetry_tracer

    sig { void }
    def initialize; end
  end

  module ClassMethods
    sig do
      params(
        method_name: T.any(Symbol, String),
        ttl: T.nilable(Numeric),
        max_size: T.nilable(Integer),
        ttl_refresh: T::Boolean,
        if: T.nilable(T.proc.params(result: T.untyped).returns(T.untyped)),
        unless: T.nilable(T.proc.params(result: T.untyped).returns(T.untyped)),
        shared: T::Boolean,
        key: T.nilable(T.proc.params(args: T.untyped).returns(T.untyped))
      ).void
    end
    def memoize(method_name, ttl: nil, max_size: nil, ttl_refresh: false, if: nil, unless: nil, shared: false, key: nil); end

    sig do
      params(
        except: T::Array[T.any(Symbol, String)],
        only: T::Array[T.any(Symbol, String)],
        include_protected: T::Boolean,
        include_private: T::Boolean,
        ttl: T.nilable(Numeric),
        max_size: T.nilable(Integer),
        ttl_refresh: T::Boolean,
        if: T.nilable(T.proc.params(result: T.untyped).returns(T.untyped)),
        unless: T.nilable(T.proc.params(result: T.untyped).returns(T.untyped)),
        shared: T::Boolean,
        key: T.nilable(T.proc.params(args: T.untyped).returns(T.untyped))
      ).void
    end
    def memoize_all(except: [], only: [], include_protected: false, include_private: false, ttl: nil, max_size: nil, ttl_refresh: false, if: nil, unless: nil, shared: false, key: nil); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped).void }
    def reset_shared_memo(method_name, *args, **kwargs); end

    sig { void }
    def reset_all_shared_memos; end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped).returns(T::Boolean) }
    def shared_memoized?(method_name, *args, **kwargs); end

    sig { params(method_name: T.nilable(T.any(Symbol, String))).returns(Integer) }
    def shared_memo_count(method_name = nil); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped).returns(T.nilable(Float)) }
    def shared_memo_age(method_name, *args, **kwargs); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped).returns(T::Boolean) }
    def shared_memo_stale?(method_name, *args, **kwargs); end
  end

  module PublicMethods
    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped, blk: T.nilable(T.proc.returns(T.untyped))).returns(T::Boolean) }
    def memoized?(method_name, *args, **kwargs, &blk); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped).returns(T.nilable(T.any(Float, Integer))) }
    def memo_ttl_remaining(method_name, *args, **kwargs); end

    sig { params(method_name: T.nilable(T.any(Symbol, String))).returns(Integer) }
    def memo_count(method_name = nil); end

    sig { params(method_name: T.nilable(T.any(Symbol, String))).returns(T::Array[T.untyped]) }
    def memo_keys(method_name = nil); end

    sig { params(method_name: T.nilable(T.any(Symbol, String))).returns(T::Array[T.untyped]) }
    def memo_values(method_name = nil); end

    sig { params(blk: T.proc.params(cache_key: T.untyped, record: T::Hash[Symbol, T.untyped]).returns(T.untyped)).void }
    def on_memo_expire(&blk); end

    sig { params(blk: T.proc.params(cache_key: T.untyped, record: T::Hash[Symbol, T.untyped]).returns(T.untyped)).void }
    def on_memo_evict(&blk); end

    sig { params(blk: T.proc.params(cache_key: T.untyped, record: T::Hash[Symbol, T.untyped]).returns(T.untyped)).void }
    def on_memo_hit(&blk); end

    sig { params(blk: T.proc.params(cache_key: T.untyped, record: T::Hash[Symbol, T.untyped]).returns(T.untyped)).void }
    def on_memo_miss(&blk); end

    sig { params(blk: T.proc.params(cache_key: T.untyped, record: T::Hash[Symbol, T.untyped]).returns(T.untyped)).void }
    def on_memo_store(&blk); end

    sig { params(hook_type: T.nilable(Symbol)).void }
    def clear_memo_hooks(hook_type = nil); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, ttl: T.nilable(Numeric), kwargs: T.untyped, blk: T.nilable(T.proc.returns(T.untyped))).returns(T.untyped) }
    def warm_memo(method_name, *args, ttl: nil, **kwargs, &blk); end

    sig { params(method_name: T.any(Symbol, String), arg_sets: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
    def memo_preload(method_name, *arg_sets); end

    sig { params(method_name: T.nilable(T.any(Symbol, String))).returns(T::Hash[T.untyped, T.untyped]) }
    def dump_memo(method_name = nil); end

    sig { params(snapshot: T::Hash[T.untyped, T.untyped]).void }
    def load_memo(snapshot); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, ttl: T.nilable(Numeric), kwargs: T.untyped).returns(T::Boolean) }
    def memo_touch(method_name, *args, ttl: nil, **kwargs); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped).returns(T.untyped) }
    def memo_refresh(method_name, *args, **kwargs); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped).returns(T.nilable(Float)) }
    def memo_age(method_name, *args, **kwargs); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped).returns(T::Boolean) }
    def memo_stale?(method_name, *args, **kwargs); end

    sig { params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped).void }
    def reset_memo(method_name, *args, **kwargs); end

    sig { void }
    def reset_all_memos; end

    sig do
      params(method_name: T.any(Symbol, String), args: T.untyped, kwargs: T.untyped)
        .returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def memo_inspect(method_name, *args, **kwargs); end
  end

  module PublicMetricsMethods
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def cache_stats; end

    sig { params(method_name: T.any(Symbol, String)).returns(T::Hash[Symbol, T.untyped]) }
    def cache_stats_for(method_name); end

    sig { returns(Float) }
    def cache_hit_rate; end

    sig { returns(Float) }
    def cache_miss_rate; end

    sig { params(method_name: T.nilable(T.any(Symbol, String))).void }
    def cache_metrics_reset(method_name = nil); end
  end

  module PublicCustomKeyMethods
    sig { params(method_name: T.any(Symbol, String), blk: T.proc.params(args: T.untyped).returns(T.untyped)).void }
    def memoize_with_custom_key(method_name, &blk); end

    sig { params(method_name: T.nilable(T.any(Symbol, String))).void }
    def clear_custom_keys(method_name = nil); end
  end

  module Adapters
    module StatsD
      METRIC_NAMES = T.let(T.unsafe(nil), T::Hash[Symbol, String])

      sig { params(client: T.untyped, hook_type: Symbol, cache_key: T.untyped, class_name: T.nilable(String)).void }
      def self.dispatch(client, hook_type, cache_key, class_name); end
    end

    module OpenTelemetry
      SPAN_NAME = T.let(T.unsafe(nil), String)

      sig { params(tracer: T.untyped, method_name: T.any(Symbol, String), class_name: T.nilable(String), blk: T.proc.returns(T.untyped)).returns(T.untyped) }
      def self.trace(tracer, method_name, class_name, &blk); end
    end
  end

  module Rails
    sig { params(instance: T.untyped).void }
    def self.track(instance); end

    sig { void }
    def self.reset_tracked!; end

    module RequestScoped
      sig { params(base: Module).void }
      def self.included(base); end

      sig { void }
      def reset_request_memos; end
    end

    class Middleware
      sig { params(app: T.untyped).void }
      def initialize(app); end

      sig { params(env: T.untyped).returns(T.untyped) }
      def call(env); end
    end
  end
end