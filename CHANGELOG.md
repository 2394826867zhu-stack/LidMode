# Changelog

All notable user-visible changes are documented here. The project does not currently publish prebuilt GitHub Releases.

## 1.2.0 — 2026-09-16

Initial public source version.

### Added

- Verified Normal/Awake menu-bar toggle backed by the real macOS power state.
- Restricted root-owned compatibility helper and exact three-command sudoers policy for local source installations.
- Signed-helper architecture for future Developer ID builds, with Team-ID-pinned XPC authentication.
- Launch-at-login, optional display wake, configurable low-battery protection, and three menu-bar text modes.
- Transactional install and uninstall scripts with rollback and post-install verification.
- Native Apple Silicon build, test suite, CI, audit record, English and Simplified Chinese documentation.

### Verified

- 30 unit tests, Release build, Xcode static analysis, helper packaging, and real installation checks.
- Reference M2 idle measurement: 0.0% CPU during a 30-second sample and approximately 25 MB physical footprint.
