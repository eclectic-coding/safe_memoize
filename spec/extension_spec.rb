# frozen_string_literal: true

RSpec.describe "SafeMemoize extension API" do
  after do
    SafeMemoize.reset_extensions!
    SafeMemoize.reset_configuration!
  end

  # ---------------------------------------------------------------------------
  # SafeMemoize::Extension DSL
  # ---------------------------------------------------------------------------

  describe "SafeMemoize::Extension DSL" do
    it "provides handled_options" do
      ext = Module.new do
        extend SafeMemoize::Extension

        handles_option(:my_opt) { {} }
      end
      expect(ext.handled_options).to eq([:my_opt])
    end

    it "process_memoize_option calls the declared processor" do
      ext = Module.new do
        extend SafeMemoize::Extension

        handles_option(:my_opt) { |val, _method, _opts| {ttl: val} }
      end
      result = ext.process_memoize_option(:my_opt, 30, :compute, {})
      expect(result).to eq({ttl: 30})
    end

    it "process_memoize_option returns empty hash for undeclared options" do
      ext = Module.new { extend SafeMemoize::Extension }
      expect(ext.process_memoize_option(:unknown, 1, :x, {})).to eq({})
    end

    it "dispatch_cache_event calls registered handlers" do
      fired = []
      ext = Module.new do
        extend SafeMemoize::Extension

        on_cache_event(:on_miss) { |klass, method_name, _key, _rec| fired << [klass, method_name] }
      end
      ext.dispatch_cache_event(:on_miss, String, :fetch, [:fetch, [], {}], nil)
      expect(fired).to eq([[String, :fetch]])
    end

    it "dispatch_cache_event is a no-op for unregistered event types" do
      ext = Module.new { extend SafeMemoize::Extension }
      expect { ext.dispatch_cache_event(:on_miss, String, :x, [], nil) }.not_to raise_error
    end

    it "on_cache_event accepts multiple event types in one call" do
      fired = []
      ext = Module.new do
        extend SafeMemoize::Extension

        on_cache_event(:on_hit, :on_miss) { |_, name, _, _| fired << name }
      end
      ext.dispatch_cache_event(:on_hit, String, :a, [], nil)
      ext.dispatch_cache_event(:on_miss, String, :b, [], nil)
      ext.dispatch_cache_event(:on_store, String, :c, [], nil)
      expect(fired).to eq([:a, :b])
    end
  end

  # ---------------------------------------------------------------------------
  # Registry API
  # ---------------------------------------------------------------------------

  describe "registry" do
    let(:ext) { Module.new { extend SafeMemoize::Extension } }

    it "register_extension stores under a symbol key" do
      SafeMemoize.register_extension(:my_ext, ext)
      expect(SafeMemoize.extensions).to eq({my_ext: ext})
    end

    it "register_extension accepts a string name and normalizes to symbol" do
      SafeMemoize.register_extension("str_ext", ext)
      expect(SafeMemoize.extensions.keys).to include(:str_ext)
    end

    it "unregister_extension removes the entry" do
      SafeMemoize.register_extension(:rm_me, ext)
      SafeMemoize.unregister_extension(:rm_me)
      expect(SafeMemoize.extensions).not_to have_key(:rm_me)
    end

    it "unregister_extension returns nil for unknown name" do
      expect(SafeMemoize.unregister_extension(:ghost)).to be_nil
    end

    it "extensions returns a dup" do
      SafeMemoize.register_extension(:e, ext)
      SafeMemoize.extensions[:injected] = ext
      expect(SafeMemoize.extensions).not_to have_key(:injected)
    end

    it "reset_extensions! empties the registry" do
      SafeMemoize.register_extension(:one, ext)
      SafeMemoize.reset_extensions!
      expect(SafeMemoize.extensions).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # extension_for_option
  # ---------------------------------------------------------------------------

  describe ".extension_for_option" do
    it "returns the extension that handles the option" do
      ext = Module.new do
        extend SafeMemoize::Extension

        handles_option(:special) { {} }
      end
      SafeMemoize.register_extension(:special, ext)
      expect(SafeMemoize.extension_for_option(:special)).to be(ext)
    end

    it "returns nil when no extension handles the option" do
      expect(SafeMemoize.extension_for_option(:nonexistent)).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Custom memoize options
  # ---------------------------------------------------------------------------

  describe "custom memoize options via extension" do
    it "raises ArgumentError for unrecognised options" do
      klass = Class.new {
        prepend SafeMemoize

        def x = 1
      }

      expect { klass.memoize(:x, unknown_opt: true) }
        .to raise_error(ArgumentError, /unknown memoize option :unknown_opt/)
    end

    it "injects cache_bust: from an extension option" do
      ext = Module.new do
        extend SafeMemoize::Extension

        handles_option(:bust_on) do |value, _method, _opts|
          {cache_bust: value}
        end
      end
      SafeMemoize.register_extension(:bust_on, ext)

      calls = 0
      klass = Class.new do
        prepend SafeMemoize

        attr_accessor :version

        def initialize = (@version = 1)

        define_method(:compute) { calls += 1 }
        memoize :compute, bust_on: -> { @version }
      end

      obj = klass.new
      obj.compute
      obj.compute
      expect(calls).to eq(1)

      obj.version = 2
      obj.compute
      expect(calls).to eq(2)
    end

    it "injects ttl: from an extension option" do
      ext = Module.new do
        extend SafeMemoize::Extension

        handles_option(:short_ttl) { |val, _, _| {ttl: val} }
      end
      SafeMemoize.register_extension(:short_ttl, ext)

      klass = Class.new do
        prepend SafeMemoize

        def data = 42
        memoize :data, short_ttl: 0.01
      end

      obj = klass.new
      obj.data
      expect(obj.memoized?(:data)).to be true
      sleep(0.02)
      expect(obj.memoized?(:data)).to be false
    end

    it "injects namespace: from an extension option" do
      ext = Module.new do
        extend SafeMemoize::Extension

        handles_option(:scope) { |val, _, _| {namespace: val} }
      end
      SafeMemoize.register_extension(:scope, ext)

      klass = Class.new do
        prepend SafeMemoize

        def result = 1
        memoize :result, scope: "tenant_42"
      end

      obj = klass.new
      obj.result
      expect(obj.memoized?(:result)).to be true
      expect(obj.memo_count(:result)).to eq(1)
    end

    it "extension injects nothing (returns empty hash) without error" do
      ext = Module.new do
        extend SafeMemoize::Extension

        handles_option(:noop) { |_, _, _| {} }
      end
      SafeMemoize.register_extension(:noop, ext)

      klass = Class.new {
        prepend SafeMemoize

        def x = 1
      }

      expect { klass.memoize(:x, noop: true) }.not_to raise_error
    end

    it "multiple extensions can coexist" do
      ext1 = Module.new do
        extend SafeMemoize::Extension

        handles_option(:opt1) { |val, _, _| {ttl: val} }
      end
      ext2 = Module.new do
        extend SafeMemoize::Extension

        handles_option(:opt2) { |val, _, _| {namespace: val} }
      end
      SafeMemoize.register_extension(:ext1, ext1)
      SafeMemoize.register_extension(:ext2, ext2)

      klass = Class.new {
        prepend SafeMemoize

        def x = 1
      }

      expect { klass.memoize(:x, opt1: 60, opt2: "ns") }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # Global lifecycle event dispatch
  # ---------------------------------------------------------------------------

  describe "global lifecycle events" do
    it "fires on_miss handlers when a method is called cold" do
      events = []
      ext = Module.new do
        extend SafeMemoize::Extension

        on_cache_event(:on_miss) { |_klass, method_name, _key, _rec| events << method_name }
      end
      SafeMemoize.register_extension(:obs, ext)

      klass = Class.new do
        prepend SafeMemoize

        def fetch = 1
        memoize :fetch
      end

      klass.new.fetch
      expect(events).to include(:fetch)
    end

    it "fires on_hit handlers on subsequent calls" do
      hits = 0
      ext = Module.new do
        extend SafeMemoize::Extension

        on_cache_event(:on_hit) { hits += 1 }
      end
      SafeMemoize.register_extension(:hit_obs, ext)

      klass = Class.new {
        prepend SafeMemoize

        def x = 1
        memoize :x
      }

      obj = klass.new
      obj.x
      obj.x
      obj.x
      expect(hits).to eq(2)
    end

    it "strips namespace from method_name passed to handlers" do
      received = []
      ext = Module.new do
        extend SafeMemoize::Extension

        on_cache_event(:on_miss) { |_klass, method_name, _key, _rec| received << method_name }
      end
      SafeMemoize.register_extension(:ns_obs, ext)

      klass = Class.new {
        prepend SafeMemoize

        def value = 1
        memoize :value, namespace: "v1"
      }

      klass.new.value
      expect(received).to include(:value)
    end

    it "does not fire for unregistered event types" do
      fired = []
      ext = Module.new do
        extend SafeMemoize::Extension

        on_cache_event(:on_hit) { fired << :hit }
      end
      SafeMemoize.register_extension(:selective, ext)

      klass = Class.new {
        prepend SafeMemoize

        def y = 2
        memoize :y
      }

      klass.new.y   # fires on_miss + on_store, not on_hit
      expect(fired).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Duck-type compatibility (no extend SafeMemoize::Extension required)
  # ---------------------------------------------------------------------------

  describe "duck-type extension interface" do
    it "accepts any object responding to the interface methods" do
      duck_ext = Object.new
      def duck_ext.handled_options = [:quack]
      def duck_ext.process_memoize_option(_name, val, _method, _opts) = {ttl: val}
      def duck_ext.dispatch_cache_event(*) = nil

      SafeMemoize.register_extension(:duck, duck_ext)

      klass = Class.new {
        prepend SafeMemoize

        def x = 1
      }

      expect { klass.memoize(:x, quack: 10) }.not_to raise_error
    end
  end
end
