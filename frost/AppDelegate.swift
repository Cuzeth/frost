//
//  AppDelegate.swift
//  frost
//
//  Bridges the two AppKit launch hooks SwiftUI doesn't expose, both in service
//  of one rule: the user must always have a way back into Settings - even with
//  the menu bar icon hidden, which removes Frost's only other UI.
//
//    - On a user-initiated launch with the icon hidden, open Settings (otherwise
//      the app would start with no visible UI at all). A login-item launch is
//      NOT user-initiated, so it stays silent — the user booted their Mac, they
//      didn't ask to see Settings.
//    - On reopen (relaunching Frost from Finder/Spotlight while it's already
//      running), open Settings.
//

import AppKit
import CoreServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    // True when macOS started Frost at login rather than the user launching it.
    // Captured from the launch Apple event in `applicationWillFinishLaunching`,
    // while that event is still current.
    private var launchedAsLoginItem = false

    // Gate for `applicationShouldHandleReopen`. macOS can deliver a reopen Apple
    // event as part of a login-item launch (and when "Reopen windows when
    // logging back in" relaunches Frost) — indistinguishable from the user
    // double-clicking Frost while it's running. Left ungated, that login-time
    // reopen pops Settings on every boot. We only honor reopens once the
    // initial launch batch has drained.
    private var didFinishInitialLaunch = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch Apple event carries keyAELaunchedAsLogInItem when launchd /
        // SMAppService starts Frost at login. Read it here, while it's still the
        // current Apple event — by `didFinishLaunching` it may be gone.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let isOpenAppEvent = event?.eventID == AEEventID(kAEOpenApplication)
        let launchSource = event?
            .paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?
            .enumCodeValue
        launchedAsLoginItem = isOpenAppEvent
            && launchSource == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read the flag straight from defaults. The default is "shown".
        let showInMenuBar = UserDefaults.standard
            .object(forKey: SettingsStore.showInMenuBarKey) as? Bool ?? true
        // Only surface Settings when the icon is hidden AND the user launched
        // Frost themselves. At login Frost runs silently; the user can reopen it
        // from Finder later to get back to Settings (handled below).
        if !showInMenuBar && !launchedAsLoginItem {
            SettingsWindowController.shared.show()
        }

        // Defer past the current run-loop turn so the login-time reopen event
        // — delivered in the same launch batch, before or just after this
        // callback — is still seen as "mid-launch" and ignored. Genuine user
        // reopens arrive much later, once this flag is set.
        DispatchQueue.main.async { [weak self] in
            self?.didFinishInitialLaunch = true
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A reopen during the initial launch is the system relaunching Frost
        // (login item / window restoration), not a user asking for Settings.
        guard didFinishInitialLaunch else { return true }

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
