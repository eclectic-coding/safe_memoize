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
