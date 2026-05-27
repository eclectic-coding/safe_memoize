# frozen_string_literal: true

require "date"

module SafeMemoize
  # @api private
  module ReleaseTooling
    module_function

    VERSION_PATTERN = /VERSION = "[^"]+"/
    SEMVER_PATTERN = /\A\d+\.\d+\.\d+(?:[-.][0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\z/
    UNRELEASED_HEADING = "## [Unreleased]"

    def normalize_version(version)
      normalized_version = version.to_s.sub(/\Av/, "")

      unless normalized_version.match?(SEMVER_PATTERN)
        raise ArgumentError, "version must look like x.y.z"
      end

      normalized_version
    end

    def update_version_file(contents, version)
      normalized_version = normalize_version(version)

      unless contents.match?(VERSION_PATTERN)
        raise ArgumentError, "version file does not define VERSION"
      end

      contents.sub(VERSION_PATTERN, %(VERSION = "#{normalized_version}"))
    end

    def finalize_changelog(contents, version, date = Date.today)
      normalized_version = normalize_version(version)
      release_heading = "## [#{normalized_version}] - #{date.iso8601}"

      unless contents.include?(UNRELEASED_HEADING)
        raise ArgumentError, "CHANGELOG.md must contain an Unreleased heading"
      end

      if contents.match?(/^## \[#{Regexp.escape(normalized_version)}\](?: - .+)?$/)
        raise ArgumentError, "CHANGELOG.md already contains #{normalized_version}"
      end

      contents.sub(UNRELEASED_HEADING, "#{UNRELEASED_HEADING}\n\n#{release_heading}")
    end

    # Removes milestone sections from ROADMAP.md where every feature row has
    # "Shipped" status. Non-milestone sections (Versioning policy, Contributing,
    # etc.) and sections with any non-Shipped row are left untouched.
    #
    # Sections are delimited by the +\n\n---\n\n+ horizontal-rule separator that
    # the ROADMAP uses between headings. A milestone section is any section whose
    # first non-blank line starts with +## v+.
    def prune_roadmap(contents)
      separator = "\n\n---\n\n"
      sections = contents.split(separator)

      pruned = sections.reject do |section|
        next false unless section.lstrip.start_with?("## v")

        # Table rows: lines starting with "|"; drop alignment rows (only |, -, :, whitespace)
        rows = section.lines.select { |l| l.strip.start_with?("|") }
        rows = rows.reject { |l| l.match?(/\A[\s|:-]+\z/) }
        data_rows = rows.drop(1) # first row is the header

        data_rows.any? && data_rows.all? { |row| row.strip.end_with?("Shipped |") }
      end

      pruned.join(separator)
    end

    def extract_release_notes(contents, version)
      normalized_version = normalize_version(version)
      lines = contents.lines
      release_heading = /^## \[#{Regexp.escape(normalized_version)}\](?: - .+)?$/
      start_index = lines.index { |line| line.match?(release_heading) }

      raise ArgumentError, "CHANGELOG.md is missing release notes for #{normalized_version}" unless start_index

      body = lines[(start_index + 1)..].take_while { |line| !line.start_with?("## [") }.join.strip
      body = "- No changes listed." if body.empty?

      <<~MARKDOWN
        ## SafeMemoize #{normalized_version}

        #{body}
      MARKDOWN
    end
  end
end
