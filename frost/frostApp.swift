//
//  frostApp.swift
//  frost
//
//  Created by Jaafar Abdeen on 6/25/26.
//

import SwiftUI
import AppKit

@main
struct frostApp: App {
    // Owns Sparkle for the app's lifetime. Created once here so the updater
    // starts (and begins its scheduled background checks) at launch.
    @StateObject private var updater: UpdaterController
    @StateObject private var settings: SettingsStore
    @StateObject private var lock: LockController

    init() {
        // SettingsStore is created first so the lock controller can read the
        // user's shortcuts/power preferences from the same instance the
        // Settings window edits.
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _updater = StateObject(wrappedValue: UpdaterController())
        _lock = StateObject(wrappedValue: LockController(settings: settings))
    }

    var body: some Scene {
        // LSUIElement agent: no Dock icon, no window — the menu bar is the UI.
        MenuBarExtra("Frost", image: "MenuBarIcon") {
            Button(lock.isLocked ? "Locked" : "Lock Input") {
                lock.lock()
            }
            .disabled(lock.isLocked)

            Divider()

            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",")

            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)

            Divider()

            Button("Quit Frost") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(settings: settings)
        }
    }
}
