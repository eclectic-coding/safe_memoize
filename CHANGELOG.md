## [Unreleased]

- Preserve public, protected, and private visibility for memoized methods
- Allow reset_memo to clear one cached argument combination or all entries for a method
- Add a memoized? helper for checking whether a method call is already cached
- Add a memo_count helper for inspecting cache size per instance or method
- Add a memo_keys helper for inspecting cached argument signatures
- Add a memo_values helper for inspecting cached signatures and their values

## [0.1.1] - 2026-05-13

- Add automated release tooling plus a GitHub Actions workflow for RubyGems publishing and GitHub releases

## [0.1.0] - 2026-02-26

- Initial release
