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
        SettingsWindowController.shared.show()
        return true
    }
}
