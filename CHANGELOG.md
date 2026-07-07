# Changelog

All notable changes to Frost are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

At release time, `scripts/release.sh` and `scripts/publish.sh` read the section
for the version being shipped and use it verbatim as both the GitHub release
notes and the Sparkle update description — so keep entries user-facing and write
them for someone deciding whether to install the update.

## [Unreleased]

<!-- Add entries here, under [Unreleased], in the same PR as the change. At
     release, leave this heading and comment in place and insert the new
     "## [x.y.z] - YYYY-MM-DD" heading just below, so the entries fall under it;
     then repoint the [Unreleased] link and add a compare-link at the bottom. -->

## [2.1] - 2026-07-07

### Added

- Lock Input App Intent, so you can lock from the Shortcuts app, Spotlight, or a script.
- Optional Apple Watch unlock, off by default and enabled in Settings.
- Optional owner message shown on the locked overlay.

### Fixed

- The Settings window now opens above other apps without stealing initial keyboard focus.
- The failed-lock snooze is preserved across baseline resets.

### Changed

- Removed an unverified timeout claim from the Inactivity settings footer.

## [2.0] - 2026-07-01

### Added

- Termination watchdog that keeps input from staying locked if the app is killed.

### Changed

- Reworked the recovery, menu, and settings UX following a full audit.

### Fixed

- Hardened the global shortcuts, event tap, and Sparkle update flow, and resolved the top audit findings.

## [1.4] - 2026-06-29

### Changed

- Switched from the embedded Touch ID prompt to the system Touch ID prompt.

### Fixed

- Delayed the Touch ID prompt until the lock window is key, so it no longer appears before the overlay is ready.

## [1.3] - 2026-06-29

### Fixed

- Touch ID now succeeds on the first attempt.

### Changed

- Improved safety, responsiveness, and accessibility handling, including the inactivity monitor.

## [1.2.1] - 2026-06-25

- Packaging and maintenance only; no user-facing changes.

## [1.2] - 2026-06-25

### Changed

- Require relaunching Frost after granting Accessibility permission, so the input tap installs reliably.

## [1.1] - 2026-06-25

### Added

- In-app updater UI (Sparkle) and accessibility-permission retry logic.

## [1.0.2] - 2026-06-25

### Fixed

- Re-arm the lock hotkey when Accessibility trust changes, so the shortcut keeps working after you grant permission.

## [1.0.1] - 2026-06-25

- Release-tooling fixes; no user-facing changes.

## [1.0] - 2026-06-25

Initial public release.

### Added

- Input lock that blocks keyboard, mouse, and kiosk gestures, cancelable with Esc.
- Touch ID unlock (biometrics-only) with multi-display support and a password fallback.
- Menu-bar agent with a configurable lock/unlock shortcut and power toggles.
- Settings window for lock/unlock shortcuts, auto-lock durations, auto-start Touch ID, and menu-bar visibility.
- Pointer stays pinned while the screen is locked.
- Sparkle-based automatic updates.

[Unreleased]: https://github.com/Cuzeth/frost/compare/v2.1...HEAD
[2.1]: https://github.com/Cuzeth/frost/compare/v2.0...v2.1
[2.0]: https://github.com/Cuzeth/frost/compare/v1.4...v2.0
[1.4]: https://github.com/Cuzeth/frost/compare/v1.3...v1.4
[1.3]: https://github.com/Cuzeth/frost/compare/v1.2.1...v1.3
[1.2.1]: https://github.com/Cuzeth/frost/compare/v1.2...v1.2.1
[1.2]: https://github.com/Cuzeth/frost/compare/v1.1...v1.2
[1.1]: https://github.com/Cuzeth/frost/compare/v1.0.2...v1.1
[1.0.2]: https://github.com/Cuzeth/frost/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/Cuzeth/frost/compare/v1.0...v1.0.1
[1.0]: https://github.com/Cuzeth/frost/releases/tag/v1.0
