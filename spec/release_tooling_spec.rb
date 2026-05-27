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

    it "raises ArgumentError when the file has no VERSION constant" do
      expect { described_class.update_version_file("# no version here", "1.0.0") }
        .to raise_error(ArgumentError, "version file does not define VERSION")
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

    it "raises ArgumentError when the changelog has no Unreleased heading" do
      expect { described_class.finalize_changelog("## [0.1.0] - 2026-01-01\n", "0.2.0", date) }
        .to raise_error(ArgumentError, "CHANGELOG.md must contain an Unreleased heading")
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

  describe ".prune_roadmap" do
    let(:shipped_section) do
      <<~MD.chomp
        ## v1.2.0 — Async & Fiber-Safe Memoization

        *Goal: concurrency.*

        | Feature | Description | Status |
        |---|---|---|
        | Fiber-local | fiber_local: true | Shipped |
        | Ractor cache | ractor_safe: true | Shipped |
      MD
    end

    let(:planned_section) do
      <<~MD.chomp
        ## v2.0.0 — Next Generation

        | Feature | Description | Status |
        |---|---|---|
        | Plugin arch | Extension API | Planned |
        | DSL changes | New syntax | Planned |
      MD
    end

    let(:mixed_section) do
      <<~MD.chomp
        ## v1.3.0 — Mixed

        | Feature | Description | Status |
        |---|---|---|
        | Done thing | Already done | Shipped |
        | Pending thing | Not yet | Planned |
      MD
    end

    let(:non_milestone_section) do
      <<~MD.chomp
        ## Versioning policy

        SafeMemoize follows Semantic Versioning from v1.0.0 onwards.
      MD
    end

    def join(*sections)
      sections.join("\n\n---\n\n")
    end

    it "removes a fully-shipped milestone section" do
      roadmap = join("# Preamble", shipped_section, planned_section)
      result = described_class.prune_roadmap(roadmap)
      expect(result).not_to include("v1.2.0")
      expect(result).to include("v2.0.0")
    end

    it "keeps a section with any Planned row" do
      roadmap = join("# Preamble", mixed_section, planned_section)
      result = described_class.prune_roadmap(roadmap)
      expect(result).to include("v1.3.0")
      expect(result).to include("v2.0.0")
    end

    it "keeps non-milestone sections unchanged" do
      roadmap = join("# Preamble", shipped_section, non_milestone_section)
      result = described_class.prune_roadmap(roadmap)
      expect(result).to include("Versioning policy")
    end

    it "returns the contents unchanged when no sections are fully shipped" do
      roadmap = join("# Preamble", planned_section)
      expect(described_class.prune_roadmap(roadmap)).to eq(roadmap)
    end

    it "removes multiple fully-shipped sections in one pass" do
      shipped2 = shipped_section.sub("v1.2.0", "v1.1.0")
      roadmap = join("# Preamble", shipped_section, shipped2, planned_section)
      result = described_class.prune_roadmap(roadmap)
      expect(result).not_to include("v1.2.0")
      expect(result).not_to include("v1.1.0")
      expect(result).to include("v2.0.0")
    end

    it "preserves correct separator structure after pruning" do
      roadmap = join("# Preamble", shipped_section, planned_section, non_milestone_section)
      result = described_class.prune_roadmap(roadmap)
      expect(result).to eq(join("# Preamble", planned_section, non_milestone_section))
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
