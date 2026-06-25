//
//  AppDelegate.swift
//  frost
//
//  Bridges the two AppKit launch hooks SwiftUI doesn't expose, both in service
//  of one rule: the user must always have a way back into Settings — even with
//  the menu bar icon hidden, which removes Frost's only other UI.
//
//    • On launch with the icon hidden, open Settings (otherwise the app would
//      start with no visible UI at all).
//    • On reopen (relaunching Frost from Finder/Spotlight while it's already
//      running), open Settings.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read the flag straight from defaults — this runs at launch, before we
        // hold a SettingsStore reference, and the default is "shown".
        let showInMenuBar = UserDefaults.standard
            .object(forKey: SettingsStore.showInMenuBarKey) as? Bool ?? true
        if !showInMenuBar {
            // Defer one hop so the Settings scene is registered before we open it.
            Task { @MainActor in Self.openSettings() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.openSettings()
        return true
    }

    /// Opens the SwiftUI `Settings` scene. There's no public programmatic opener
    /// for it, so we go through the standard responder action (renamed to
    /// `showSettingsWindow:` in macOS 13; older fallback kept just in case).
    @MainActor
    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let settingsSelector = Selector(("showSettingsWindow:"))
        if NSApp.responds(to: settingsSelector) {
            NSApp.sendAction(settingsSelector, to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
