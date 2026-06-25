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
    @StateObject private var updater = UpdaterController()
    @StateObject private var lock = LockController()

    var body: some Scene {
        // LSUIElement agent: no Dock icon, no window — the menu bar is the UI.
        MenuBarExtra("Frost", systemImage: "snowflake") {
            Button(lock.isLocked ? "Locked" : "Lock Input") {
                lock.lock()
            }
            .disabled(lock.isLocked)

            Divider()

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
    }
}
