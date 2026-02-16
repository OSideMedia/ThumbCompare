# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-16

### Added
- Initial public release of ThumbCompare for macOS.
- Feed-style comparison view for your thumbnail/title against competitor uploads.
- A/B thumbnail toggle support.
- PNG export of the comparison snapshot.
- YouTube handle resolution flow with optional search fallback.
- Filtering to prioritize feed-friendly, non-Short competitor uploads.
- Local image caching for thumbnail/avatar loading performance.
- Settings screen for YouTube Data API v3 key input.
- Local key storage in macOS Keychain via `KeychainStore`.
- Repository safety checks:
  - Pre-commit secret scan hook.
  - Pre-push secret scan hook.
- Project documentation updates:
  - API key setup guidance.
  - Security notes.
  - Screenshot section and screenshot asset placeholders.

### Security
- Confirmed API keys are not embedded in repository source files.
- Confirmed release DMG does not contain hardcoded API keys or token patterns.

