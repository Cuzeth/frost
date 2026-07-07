//
//  FrostAppIntents.swift
//  frost
//
//  App Intents surface: a single "Lock Input" action so Shortcuts (and
//  `shortcuts run "Lock Input"` from a terminal or build script) can start a
//  lock programmatically — the product's core workflow is "start an
//  unattended task, then lock the desk".
//
//  SAFETY: the intent can only LOCK, never unlock. It calls the same
//  LockController.lock() entry point as the menu item, so every preflight
//  (Touch ID availability, Accessibility) and every recovery/escape hatch
//  applies unchanged. If the app is already locked or in recovery, the
//  intent is a no-op.
//

import AppIntents

struct LockInputIntent: AppIntent {
    // Mirror the Debug/Release bundle split (dev.abdeen.frost.debug /
    // "Frost (Dev)") so a dev build's action is distinguishable from the
    // installed app's in the Shortcuts gallery.
    #if DEBUG
    static let title: LocalizedStringResource = "Lock Input (Dev)"
    #else
    static let title: LocalizedStringResource = "Lock Input"
    #endif
    static let description = IntentDescription(
        "Locks keyboard, mouse, and trackpad input until unlocked with Touch ID."
    )
    // Menu-bar agent: the lock overlay is the UI; never open a window.
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        // The controller is created by the SwiftUI App on launch. If this
        // intent launched the app, the scene may still be building — give it
        // a short beat rather than failing spuriously.
        for _ in 0..<50 where LockController.shared == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let lock = LockController.shared else {
            throw LockInputIntentError.notReady
        }
        guard !lock.isLocked else {
            return .result()   // already locked or in recovery: no-op
        }
        lock.lock()
        return .result()
    }
}

enum LockInputIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady

    var localizedStringResource: LocalizedStringResource {
        "Frost is still starting. Try again in a moment."
    }
}

/// Publishes the intent as an App Shortcut so it exists in Shortcuts (and is
/// runnable via `shortcuts run`) without the user assembling anything.
struct FrostShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        #if DEBUG
        AppShortcut(
            intent: LockInputIntent(),
            phrases: ["Lock input with \(.applicationName)"],
            shortTitle: "Lock Input (Dev)",
            systemImageName: "lock.fill"
        )
        #else
        AppShortcut(
            intent: LockInputIntent(),
            phrases: ["Lock input with \(.applicationName)"],
            shortTitle: "Lock Input",
            systemImageName: "lock.fill"
        )
        #endif
    }
}
