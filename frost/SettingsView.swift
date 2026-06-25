//
//  SettingsView.swift
//  frost
//
//  The preferences window: configure the lock/unlock shortcuts and the
//  while-locked power behavior. Reached from the menu bar via SettingsLink.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    // Shares the menu-bar flag with the App via UserDefaults (see SettingsStore).
    @AppStorage(SettingsStore.showInMenuBarKey) private var showInMenuBar = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Unlock") {
                    ShortcutRecorder(shortcut: unlockBinding, allowsClear: false)
                        .frame(width: 170, height: 24)
                }
            } header: {
                Text("Unlock Shortcut")
            } footer: {
                Text("Required. Press this while locked to bring up Touch ID. Recognized even though all other input is frozen.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Lock") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(shortcut: $settings.lockShortcut, allowsClear: true)
                            .frame(width: 170, height: 24)
                        Button("Clear") { settings.lockShortcut = nil }
                            .disabled(settings.lockShortcut == nil)
                    }
                }
            } header: {
                Text("Lock Shortcut")
            } footer: {
                Text("Optional. A system-wide hotkey that locks input from anywhere. Leave empty to lock only from the menu bar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Prevent screen saver", isOn: $settings.preventScreenSaver)
                Toggle("Prevent sleep", isOn: $settings.preventSleep)
            } header: {
                Text("While Locked")
            } footer: {
                Text("Keep the screen on and the Mac awake while input is locked. Released automatically on unlock.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("When off, the menu bar icon is hidden. Relaunch Frost to reopen this window; use Quit below to stop it.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Quit Frost") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // An LSUIElement agent doesn't auto-focus its windows; pull the
            // Settings window to the front so the user can interact with it.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// The unlock field is required, so adapt the non-optional store value to the
    /// recorder's optional binding and ignore any nil (clearing is disabled).
    private var unlockBinding: Binding<Shortcut?> {
        Binding(
            get: { settings.unlockShortcut },
            set: { if let new = $0 { settings.unlockShortcut = new } }
        )
    }
}
