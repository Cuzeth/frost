//
//  SettingsStore.swift
//  frost
//
//  User-facing preferences, persisted to UserDefaults:
//    • unlockShortcut    — REQUIRED; recognized inside the event tap to unlock.
//    • lockShortcut      — OPTIONAL; a global hotkey that starts a lock.
//    • preventScreenSaver / preventSleep — power assertions held while locked.
//
//  Published so the Settings UI updates live; LockController reads the current
//  values when a lock begins (settings can't change while locked — input is
//  frozen — so a snapshot at lock time is always current).
//

import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var unlockShortcut: Shortcut {
        didSet { write(unlockShortcut, forKey: Key.unlockShortcut) }
    }
    @Published var lockShortcut: Shortcut? {
        didSet { write(lockShortcut, forKey: Key.lockShortcut) }
    }
    @Published var preventScreenSaver: Bool {
        didSet { defaults.set(preventScreenSaver, forKey: Key.preventScreenSaver) }
    }
    @Published var preventSleep: Bool {
        didSet { defaults.set(preventSleep, forKey: Key.preventSleep) }
    }

    private let defaults: UserDefaults

    /// Key for the menu-bar-visibility flag. Deliberately NOT an @Published here:
    /// it's read via @AppStorage in the App/Settings views so binding it to
    /// MenuBarExtra(isInserted:) doesn't publish object changes during a view
    /// update, and read straight from defaults by AppDelegate at launch (before
    /// any store exists). Defaults to `true`.
    static let showInMenuBarKey = "showInMenuBar"

    private enum Key {
        static let unlockShortcut = "unlockShortcut"
        static let lockShortcut = "lockShortcut"
        static let preventScreenSaver = "preventScreenSaver"
        static let preventSleep = "preventSleep"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // didSet does not fire during init, so these loads never re-persist.
        self.unlockShortcut = Self.read(Key.unlockShortcut, from: defaults) ?? .defaultUnlock
        self.lockShortcut = Self.read(Key.lockShortcut, from: defaults)
        self.preventScreenSaver = defaults.bool(forKey: Key.preventScreenSaver)
        self.preventSleep = defaults.bool(forKey: Key.preventSleep)
    }

    private func write(_ shortcut: Shortcut?, forKey key: String) {
        guard let shortcut else { defaults.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        }
    }

    private static func read(_ key: String, from defaults: UserDefaults) -> Shortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}
