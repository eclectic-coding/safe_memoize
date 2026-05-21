# frozen_string_literal: true

RSpec.describe "SafeMemoize.deprecate" do
  around do |example|
    example.run
  ensure
    SafeMemoize.reset_configuration!
  end

  describe "default behaviour (no on_deprecation handler)" do
    it "emits a warning to stderr" do
      expect {
        SafeMemoize.deprecate("old_method", message: "Use new_method instead.", horizon: "v1.0.0")
      }.to output(/\[SafeMemoize\]/).to_stderr
    end

    it "includes the subject in the warning" do
      expect {
        SafeMemoize.deprecate("old_method", message: "Use new_method instead.", horizon: "v1.0.0")
      }.to output(/old_method/).to_stderr
    end

    it "includes the horizon in the warning" do
      expect {
        SafeMemoize.deprecate("old_method", message: "Use new_method instead.", horizon: "v1.0.0")
      }.to output(/v1\.0\.0/).to_stderr
    end

    it "includes the message in the warning" do
      expect {
        SafeMemoize.deprecate("old_method", message: "Use new_method instead.", horizon: "v1.0.0")
      }.to output(/Use new_method instead\./).to_stderr
    end
  end

  describe "custom on_deprecation handler" do
    it "calls the handler instead of emitting to stderr" do
      received = nil
      SafeMemoize.configure { |c| c.on_deprecation = ->(msg) { received = msg } }

      expect {
        SafeMemoize.deprecate("old_method", message: "Use new_method instead.", horizon: "v1.0.0")
      }.not_to output.to_stderr

      expect(received).not_to be_nil
    end

    it "passes the full formatted message to the handler" do
      received = nil
      SafeMemoize.configure { |c| c.on_deprecation = ->(msg) { received = msg } }

      SafeMemoize.deprecate("old_method", message: "Use new_method instead.", horizon: "v1.0.0")

      expect(received).to include("[SafeMemoize]")
      expect(received).to include("old_method")
      expect(received).to include("v1.0.0")
      expect(received).to include("Use new_method instead.")
    end

    it "can be configured to raise on deprecation" do
      SafeMemoize.configure { |c| c.on_deprecation = ->(msg) { raise msg } }

      expect {
        SafeMemoize.deprecate("old_method", message: "Use new_method.", horizon: "v1.0.0")
      }.to raise_error(/old_method/)
    end

    it "collects multiple deprecation warnings" do
      warnings = []
      SafeMemoize.configure { |c| c.on_deprecation = ->(msg) { warnings << msg } }

      SafeMemoize.deprecate("method_a", message: "Gone.", horizon: "v1.0.0")
      SafeMemoize.deprecate("method_b", message: "Gone.", horizon: "v1.0.0")

      expect(warnings.length).to eq(2)
      expect(warnings[0]).to include("method_a")
      expect(warnings[1]).to include("method_b")
    end
  end

  describe "reset_configuration!" do
    it "restores the default warn behaviour after a custom handler was set" do
      SafeMemoize.configure { |c| c.on_deprecation = ->(_) { raise "should not be called" } }
      SafeMemoize.reset_configuration!

      expect {
        SafeMemoize.deprecate("old_method", message: "Use new_method.", horizon: "v1.0.0")
      }.to output(/\[SafeMemoize\]/).to_stderr
    end

    it "clears on_deprecation back to nil" do
      SafeMemoize.configure { |c| c.on_deprecation = ->(_) {} }
      SafeMemoize.reset_configuration!
      expect(SafeMemoize.configuration.on_deprecation).to be_nil
    end
  end
end
