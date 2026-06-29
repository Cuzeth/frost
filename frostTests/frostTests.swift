//
//  frostTests.swift
//  frostTests
//
//  Top-level smoke checks for cross-cutting invariants. Detailed, per-type
//  coverage lives in the dedicated suites:
//    • ShortcutTests             — matching, display, Codable
//    • InactivityLockOptionTests — thresholds, labels, case list
//    • SettingsStoreTests        — UserDefaults persistence & reconciliation
//    • LockStateTests            — state-machine value semantics
//

import Testing

@testable import frost

@MainActor
struct frostTests {

    /// Every Frost shortcut must carry at least one chord modifier, so a bare
    /// keypress can never lock or unlock by accident.
    @Test func defaultUnlockChordRequiresAModifier() {
        #expect(!Shortcut.defaultUnlock.modifierFlags.isEmpty)
    }

    /// The factory unlock chord renders its modifiers in canonical order. The
    /// final key name comes from the user's current keyboard layout.
    @Test func defaultUnlockDisplaysAsExpected() {
        let display = Shortcut.defaultUnlock.displayString
        #expect(display.hasPrefix("⌃⌥⌘"))
        #expect(display.count > 3)
    }
}
