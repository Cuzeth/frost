//
//  SettingsView.swift
//  frost
//
//  The preferences window: configure the lock/unlock shortcuts and the
//  while-locked power behavior.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    @ObservedObject var updater: UpdaterController
    // Shares the menu-bar flag with the App via UserDefaults (see SettingsStore).
    @AppStorage(SettingsStore.showInMenuBarKey) private var showInMenuBar = true

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Unlock")
                    Spacer()
                    ShortcutRecorder(shortcut: unlockBinding, allowsClear: false)
                        .frame(width: 170, height: 24)
                }
                Toggle("Start Touch ID automatically when locked", isOn: $settings.startTouchIDWhenLocked)
            } header: {
                Text("Unlock")
            } footer: {
                Text("Required. Press this while locked to bring up Touch ID. Click the field and press a new combo to change it. Turn on automatic start to show Touch ID as soon as a lock begins. Frost requires a Mac with Touch ID.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Lock")
                    Spacer()
                    ShortcutRecorder(shortcut: lockBinding, allowsClear: true)
                        .frame(width: 170, height: 24)
                    Button("Clear") { settings.lockShortcut = nil }
                        .disabled(settings.lockShortcut == nil)
                }
            } header: {
                Text("Lock Shortcut")
            } footer: {
                Text("Optional. A system-wide hotkey that locks input from anywhere. Click the field and press a combo to set it; press ⌫ or Clear to remove it, or ⎋ to cancel. If it matches Unlock, Frost clears it.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Auto-lock", selection: $settings.inactivityLock) {
                    ForEach(InactivityLockOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Inactivity")
            } footer: {
                Text("Locks after the selected time without keyboard, mouse, or trackpad input. Passive reading still counts as idle.")
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
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.requiresApproval {
                    Button("Open Login Items Settings") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }
            } header: {
                Text("Startup")
            } footer: {
                if let message = launchAtLogin.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                } else if launchAtLogin.requiresApproval {
                    Text("macOS needs approval in Login Items before Frost can launch at login.")
                        .foregroundStyle(.secondary)
                }
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
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text("Frost checks automatically in the background. Use this to check right now.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Quit Frost") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 320)
        .onAppear {
            // An LSUIElement agent doesn't auto-focus its windows; pull the
            // Settings window to the front so the user can interact with it.
            NSApp.activate(ignoringOtherApps: true)
            launchAtLogin.refresh()
        }
    }

    /// The unlock field is required, so adapt the non-optional store value to the
    /// recorder's optional binding and ignore any nil (clearing is disabled).
    private var unlockBinding: Binding<Shortcut?> {
        Binding(
            get: { settings.unlockShortcut },
            set: {
                if let new = $0 {
                    settings.unlockShortcut = new
                    if settings.lockShortcut == new {
                        settings.lockShortcut = nil
                    }
                }
            }
        )
    }

    private var lockBinding: Binding<Shortcut?> {
        Binding(
            get: { settings.lockShortcut },
            set: {
                guard $0 != settings.unlockShortcut else {
                    settings.lockShortcut = nil
                    NSSound.beep()
                    return
                }
                settings.lockShortcut = $0
            }
        )
    }
}
