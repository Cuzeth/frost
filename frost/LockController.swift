//
//  LockController.swift
//  frost
//
//  Central coordinator for a lock session. Wires PermissionManager,
//  EventTapManager, OverlayCoordinator, and UnlockCoordinator together and owns
//  the state machine + the DEBUG auto-unlock safety net.
//
//  SAFETY: independent ways out of a lock:
//    1. The unlock chord (⌃⌥⌘U) → Touch ID / password.
//    2. The DEBUG auto-unlock timer (debug builds only).
//    3. Sending SIGTERM (e.g. `pkill -x frost` / `kill` over SSH) — caught
//       below and torn down cleanly, independent of app state.
//

import AppKit
import Combine
import Foundation
import os

enum LockState: Equatable {
    case unlocked
    case locked
    case authenticating
    case recovery(String)
}

@MainActor
final class LockController: ObservableObject {
    @Published private(set) var state: LockState = .unlocked
    #if DEBUG
    @Published private(set) var debugSecondsRemaining: Int?
    #endif

    private let permissions = PermissionManager()
    private let tap = EventTapManager()
    private let overlay = OverlayCoordinator()
    private let unlocker = UnlockCoordinator()
    private let log = Logger(subsystem: "dev.abdeen.frost", category: "Lock")

    /// Weak global handle so the SIGTERM dispatch source can reach the live
    /// controller without capturing it in a @Sendable closure.
    nonisolated(unsafe) static weak var shared: LockController?
    private var signalSources: [any DispatchSourceSignal] = []

    #if DEBUG
    /// DEBUG-only: the lock always tears down after this many seconds, no matter
    /// what. Never compiled into release builds.
    private let debugAutoUnlockSeconds = 20
    private var debugTask: Task<Void, Never>?
    #endif

    var isLocked: Bool { state != .unlocked }

    init() {
        Self.shared = self
        // Defer to the next main-loop tick so we never mutate the tap from
        // inside its own callback.
        tap.onUnlockChord = { [weak self] in
            Task { @MainActor in self?.requestUnlock() }
        }
        installTerminationHandler()
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

        // Without BOTH permissions the tap can't suppress input. Prompt, then
        // show the recovery state — never a lock the user can't escape.
        guard permissions.allGranted else {
            permissions.requestAccessibility()
            permissions.requestInputMonitoring()
            enterRecovery("""
                Frost needs Accessibility and Input Monitoring. Enable both for \
                Frost in System Settings → Privacy & Security, then choose Lock \
                Input again. (Relaunching Frost may be required after granting.)
                """)
            return
        }

        guard tap.start() else {
            enterRecovery("""
                Couldn't create the input tap. Confirm Accessibility and Input \
                Monitoring are enabled for Frost, then try again. Input is NOT \
                locked.
                """)
            return
        }

        // Input is now suppressed — arm the safety net BEFORE anything else.
        startDebugAutoUnlock()
        overlay.present(controller: self)
        enterKioskMode()
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
        state = .authenticating

        // Keep the screen covered and input frozen while the Touch ID prompt is
        // up — only Esc is allowed through, so the prompt can be cancelled. The
        // machine is NEVER exposed merely because authentication started; the
        // Touch ID sensor is hardware and works behind the overlay.
        tap.setAuthenticating(true)

        Task { [weak self] in
            guard let self else { return }
            let ok = await self.unlocker.authenticate(reason: "Unlock Frost")
            guard self.state == .authenticating else { return } // safety net won the race
            if ok { self.finishUnlock() } else { self.reLock() }
        }
    }

    private func reLock() {
        // The overlay never hid and the tap never stopped suppressing; just
        // re-freeze Esc and return to the locked state.
        tap.setAuthenticating(false)
        state = .locked
        log.info("Re-locked after failed/cancelled auth")
    }

    private func finishUnlock() {
        teardown()
        log.info("Unlocked")
    }

    // MARK: - Recovery

    private func enterRecovery(_ message: String) {
        state = .recovery(message)
        overlay.present(controller: self)
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
        tap.stop()
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
