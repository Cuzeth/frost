//
//  AppDelegate.swift
//  frost
//
//  Bridges the two AppKit launch hooks SwiftUI doesn't expose, both in service
//  of one rule: the user must always have a way back into Settings - even with
//  the menu bar icon hidden, which removes Frost's only other UI.
//
//    - On launch with the icon hidden, open Settings (otherwise the app would
//      start with no visible UI at all).
//    - On reopen (relaunching Frost from Finder/Spotlight while it's already
//      running), open Settings.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read the flag straight from defaults. The default is "shown".
        let showInMenuBar = UserDefaults.standard
            .object(forKey: SettingsStore.showInMenuBarKey) as? Bool ?? true
        if !showInMenuBar {
            SettingsWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Never churn window focus while a lock is active: `show()` activates
        // the app and keys the Settings window, which competes with the system
        // Touch ID prompt — and a reopen can arrive mid-lock (e.g. `open -a
        // Frost` from a remote shell, or Quit & Reopen racing a new lock).
        if LockController.shared?.isLocked != true {
            SettingsWindowController.shared.show()
        }
        return true
    }

    // Safety backstop: if Frost is told to terminate while a lock (or recovery)
    // is still active — e.g. a plain NSApp.terminate that bypasses teardown() —
    // restore the cursor, presentation options, tap, and power assertions here
    // rather than depending on @StateObject deinit running at exit. Runs on the
    // main thread, so the @MainActor hop is safe; no-op when already unlocked.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            LockController.shared?.tearDownForTermination()
        }
    }
}
