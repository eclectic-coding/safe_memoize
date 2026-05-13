# frozen_string_literal: true

require "date"
require "safe_memoize/release_tooling"

RSpec.describe SafeMemoize::ReleaseTooling do
  describe ".normalize_version" do
    it "accepts standard semver strings" do
      expect(described_class.normalize_version("1.2.3")).to eq("1.2.3")
    end

    it "strips a leading v" do
      expect(described_class.normalize_version("v1.2.3")).to eq("1.2.3")
    end

    it "rejects invalid versions" do
      expect { described_class.normalize_version("1.2") }
        .to raise_error(ArgumentError, "version must look like x.y.z")
    end
  end

  describe ".update_version_file" do
    it "replaces the VERSION constant" do
      contents = <<~RUBY
        module SafeMemoize
          VERSION = "0.1.0"
        end
      RUBY

      expect(described_class.update_version_file(contents, "1.0.0"))
        .to include('VERSION = "1.0.0"')
    end
  end

  describe ".finalize_changelog" do
    let(:date) { Date.iso8601("2026-05-13") }

    it "converts the unreleased section into a dated release section" do
      contents = <<~MARKDOWN
        ## [Unreleased]

        - Add release automation

        ## [0.1.0] - 2026-02-26

        - Initial release
      MARKDOWN

      expect(described_class.finalize_changelog(contents, "0.2.0", date)).to eq(<<~MARKDOWN)
        ## [Unreleased]

        ## [0.2.0] - 2026-05-13

        - Add release automation

        ## [0.1.0] - 2026-02-26

        - Initial release
      MARKDOWN
    end

    it "fails when the changelog already contains the version" do
      contents = <<~MARKDOWN
        ## [Unreleased]

        ## [0.2.0] - 2026-05-13
      MARKDOWN

      expect { described_class.finalize_changelog(contents, "0.2.0", date) }
        .to raise_error(ArgumentError, "CHANGELOG.md already contains 0.2.0")
    end
  end

  describe ".extract_release_notes" do
    it "returns the requested release section body" do
      contents = <<~MARKDOWN
        ## [Unreleased]

        ## [0.2.0] - 2026-05-13

        - Add release automation

        ## [0.1.0] - 2026-02-26

        - Initial release
      MARKDOWN

      expect(described_class.extract_release_notes(contents, "0.2.0")).to eq(<<~MARKDOWN)
        ## SafeMemoize 0.2.0

        - Add release automation
      MARKDOWN
    end

    it "uses a fallback line when the release section is empty" do
      contents = <<~MARKDOWN
        ## [Unreleased]

        ## [0.2.0] - 2026-05-13
      MARKDOWN

      expect(described_class.extract_release_notes(contents, "0.2.0")).to eq(<<~MARKDOWN)
        ## SafeMemoize 0.2.0

        - No changes listed.
      MARKDOWN
    end
  end
end
