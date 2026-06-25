//
//  LockController.swift
//  frost
//
//  Central coordinator for a lock session. Wires PermissionManager,
//  EventTapManager, OverlayCoordinator, and UnlockCoordinator together and owns
//  the state machine + the DEBUG auto-unlock safety net.
//
//  SAFETY: independent ways out of a lock:
//    1. The unlock chord (⌃⌥⌘U) → Touch ID / password fallback.
//    2. The DEBUG auto-unlock timer (debug builds only).
//    3. Sending SIGTERM (e.g. `pkill -x frost` / `kill` over SSH) — caught
//       below and torn down cleanly, independent of app state.
//

import AppKit
import Combine
import Foundation
import LocalAuthentication
import os

enum LockState: Equatable {
    case unlocked
    case locked
    case authenticating
    case recovery(RecoveryState)
}

struct RecoveryState: Equatable {
    var title = "Input Not Locked"
    var message: String
    var showsAccessibilitySettings = false
    var allowsRetry = true
}

@MainActor
final class LockController: ObservableObject {
    @Published private(set) var state: LockState = .unlocked
    @Published private(set) var tapRecoveryNotice: String?
    #if DEBUG
    @Published private(set) var debugSecondsRemaining: Int?
    #endif

    private let permissions = PermissionManager()
    private let tap = EventTapManager()
    private let overlay = OverlayCoordinator()
    private let unlocker = UnlockCoordinator()
    private let sleep = SleepAssertionManager()
    private let inactivity = InactivityLockMonitor()
    private let settings: SettingsStore
    private let log = Logger(subsystem: "dev.abdeen.frost", category: "Lock")

    /// Weak global handle so the SIGTERM dispatch source can reach the live
    /// controller without capturing it in a @Sendable closure.
    nonisolated(unsafe) static weak var shared: LockController?
    private var signalSources: [any DispatchSourceSignal] = []
    /// Global key monitor for the optional lock hotkey (active while unlocked).
    private var lockHotKeyMonitor: Any?
    private var authenticationTask: Task<Void, Never>?

    #if DEBUG
    /// DEBUG-only: the lock always tears down after this many seconds, no matter
    /// what. Never compiled into release builds.
    private let debugAutoUnlockSeconds = 20
    private var debugTask: Task<Void, Never>?
    #endif

    var isLocked: Bool { state != .unlocked }

    /// The configured unlock shortcut, formatted for the overlay hint.
    var unlockShortcutDisplay: String { settings.unlockShortcut.displayString }
    var authenticationContext: LAContext? { unlocker.currentContext }

    init(settings: SettingsStore) {
        self.settings = settings
        Self.shared = self
        tap.unlockShortcut = settings.unlockShortcut
        // Defer to the next main-loop tick so we never mutate the tap from
        // inside its own callback.
        tap.onUnlockChord = { [weak self] in
            Task { @MainActor in self?.requestUnlock() }
        }
        tap.onTapReenabled = { [weak self] message in
            self?.tapRecoveryNotice = message
        }
        installTerminationHandler()
        installLockHotKeyMonitor()
        inactivity.start(settings: settings, lock: self)
    }

    deinit {
        MainActor.assumeIsolated {
            removeLockHotKeyMonitor()
            inactivity.stop()
            stopDebugAutoUnlock()
            sleep.releaseAll()
            tap.stop()
            unlocker.cancel()
            overlay.dismiss()
            signalSources.forEach { $0.cancel() }
            if Self.shared === self {
                Self.shared = nil
            }
        }
    }

    /// Optional system-wide hotkey that STARTS a lock. A non-consuming global
    /// monitor is enough: it only needs to trigger a lock, and it never fires
    /// while Frost itself is frontmost (so it won't clash with the recorder).
    private func installLockHotKeyMonitor() {
        lockHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Pull the Sendable bits out here; hop to the main actor to act.
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            Task { @MainActor in self?.handleLockHotKey(keyCode: keyCode, modifiers: modifiers) }
        }
    }

    private func removeLockHotKeyMonitor() {
        if let lockHotKeyMonitor {
            NSEvent.removeMonitor(lockHotKeyMonitor)
            self.lockHotKeyMonitor = nil
        }
    }

    private func handleLockHotKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard state == .unlocked, let shortcut = settings.lockShortcut else { return }
        if shortcut.matches(keyCode: keyCode, modifiers: modifiers) { lock() }
    }

    /// Catch SIGTERM (e.g. from `pkill`/`kill` over SSH) so we can restore the
    /// cursor + release the tap before exiting — never die with the cursor still
    /// decoupled from the mouse.
    private func installTerminationHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            Task { @MainActor in LockController.shared?.handleTerminationSignal() }
        }
        source.resume()
        signalSources.append(source)
    }

    private func handleTerminationSignal() {
        log.notice("SIGTERM received; tearing down before exit")
        teardown()
        NSApp.terminate(nil)
    }

    // MARK: - Lock

    func lock() {
        guard state == .unlocked else { return }

        switch unlocker.checkTouchIDAvailability() {
        case .available:
            break
        case .unavailable(let message):
            enterRecovery(RecoveryState(
                title: "Touch ID Required",
                message: message
            ))
            return
        }

        // Without Accessibility the tap can't suppress input. Prompt, then show
        // the recovery state — never a lock the user can't escape.
        guard permissions.allGranted else {
            permissions.requestAccessibility()
            enterRecovery(RecoveryState(
                message: """
                Frost needs Accessibility. Enable it for \
                Frost in System Settings → Privacy & Security, then try again. \
                Input is NOT locked.
                """,
                showsAccessibilitySettings: true
            ))
            return
        }

        // Recognize the latest configured unlock shortcut for this session.
        tap.unlockShortcut = settings.unlockShortcut

        guard tap.start() else {
            enterRecovery(RecoveryState(
                message: """
                Couldn't create the input tap. Confirm Accessibility is enabled \
                for Frost, then try again. Input is NOT locked.
                """
            ))
            return
        }

        // Input is now suppressed — arm the safety net BEFORE anything else.
        startDebugAutoUnlock()
        overlay.present(controller: self)
        enterKioskMode()
        sleep.apply(preventScreenSaver: settings.preventScreenSaver,
                    preventSleep: settings.preventSleep)
        tapRecoveryNotice = nil
        state = .locked
        log.info("Locked")
    }

    // Trackpad swipes for Mission Control / Spaces / App Exposé, ⌘-Tab, and the
    // ⌘⌥Esc Force Quit panel are handled by the Dock / WindowServer above the
    // HID layer, so the event tap can't swallow them. The only supported way to
    // disable them is kiosk presentation options — and macOS REQUIRES the Dock
    // and menu bar to be hidden for the disable* flags to be legal (an invalid
    // combination raises an exception that would crash the lock). So blocking
    // the gestures and hiding the Dock are one and the same switch; they cannot
    // be separated. Force Quit is disabled because opening ⌘⌥Esc while the Touch
    // ID prompt is up steals its focus and strands the user. ALWAYS undone in
    // teardown so the desktop returns to normal.
    private func enterKioskMode() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableAppleMenu,
        ]
    }

    private func exitKioskMode() {
        NSApp.presentationOptions = []
    }

    // MARK: - Unlock

    func requestUnlock() {
        guard state == .locked else { return }
        authenticationTask?.cancel()
        authenticationTask = nil

        switch unlocker.prepareAuthenticationContext() {
        case .prepared:
            break
        case .unavailable(let message):
            reLock(notice: message)
            return
        case .success, .cancelled, .failed:
            reLock()
            return
        }

        state = .authenticating

        // Keep the screen covered and input frozen while the embedded
        // LocalAuthentication view is up. Esc is allowed through so the user can
        // cancel the prompt and remain locked.
        tap.setAuthenticating(true)
    }

    func authenticationViewReady(for context: LAContext) {
        guard state == .authenticating,
              authenticationTask == nil,
              unlocker.currentContext === context
        else { return }

        authenticationTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.unlocker.authenticatePreparedContext(reason: "Unlock Frost")
            if Task.isCancelled { return }
            self.authenticationTask = nil
            guard self.state == .authenticating else { return } // safety net won the race
            switch result {
            case .prepared:
                self.reLock()
            case .success:
                self.finishUnlock()
            case .unavailable(let message):
                self.reLock(notice: message)
            case .cancelled, .failed:
                self.reLock()
            }
        }
    }

    private func reLock(notice: String? = nil) {
        // The overlay never hid and the tap never stopped suppressing; just
        // re-freeze Esc and return to the locked state.
        tap.setAuthenticating(false)
        if let notice {
            tapRecoveryNotice = notice
        }
        state = .locked
        log.info("Re-locked after failed/cancelled auth")
    }

    private func finishUnlock() {
        teardown()
        log.info("Unlocked")
    }

    // MARK: - Recovery

    private func enterRecovery(_ recovery: RecoveryState) {
        inactivity.snoozeAfterFailedLock()
        state = .recovery(recovery)
        overlay.present(controller: self)
    }

    func retryRecovery() {
        guard case .recovery = state else { return }
        teardown()
        lock()
    }

    func dismissRecovery() {
        guard case .recovery = state else { return }
        teardown()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Teardown

    private func teardown() {
        stopDebugAutoUnlock()
        exitKioskMode()
        sleep.releaseAll()
        tap.stop()
        authenticationTask?.cancel()
        authenticationTask = nil
        tapRecoveryNotice = nil
        unlocker.cancel()
        overlay.dismiss()
        state = .unlocked
    }

    // MARK: - DEBUG auto-unlock safety net

    private func startDebugAutoUnlock() {
        #if DEBUG
        debugSecondsRemaining = debugAutoUnlockSeconds
        log.notice("DEBUG auto-unlock armed")
        debugTask?.cancel()
        debugTask = Task { [weak self] in
            guard let self else { return }
            var remaining = self.debugAutoUnlockSeconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
                self.debugSecondsRemaining = remaining
            }
            self.log.notice("DEBUG auto-unlock fired")
            self.teardown()
        }
        #endif
    }

    private func stopDebugAutoUnlock() {
        #if DEBUG
        debugTask?.cancel()
        debugTask = nil
        debugSecondsRemaining = nil
        #endif
    }
}
