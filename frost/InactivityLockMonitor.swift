//
//  InactivityLockMonitor.swift
//  frost
//
//  Polls macOS session idle time while Frost is unlocked and triggers the normal
//  lock path when the selected inactivity threshold is exceeded.
//

import CoreGraphics
import Foundation
import os

@MainActor
final class InactivityLockMonitor {
    private weak var settings: SettingsStore?
    private weak var lock: LockController?
    private var pollTask: Task<Void, Never>?
    private var snoozedUntil: Date?
    private let failedLockSnoozeSeconds: TimeInterval = 60
    private let log = Logger(subsystem: "dev.abdeen.frost", category: "Inactivity")

    /// `kCGAnyInputEventType` (raw value `0xFFFFFFFF`): the documented sentinel
    /// for "seconds since the last event of ANY type", i.e. true input idle time.
    /// The C constant isn't bridged into Swift, so we build a `CGEventType` with
    /// the same raw value — `CGEventSource.secondsSinceLastEventType` reads only
    /// the raw value, so this is correct even though Swift happens to name that
    /// case `.tapDisabledByUserInput`. Do NOT "simplify" this back to `.null`
    /// (raw value 0): that measures idle time since the last *null* event, which
    /// real input never resets, so auto-lock would misfire.
    private static let anyInputEventType = CGEventType(rawValue: ~0)!

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    func start(settings: SettingsStore, lock: LockController) {
        self.settings = settings
        self.lock = lock
        pollTask?.cancel()

        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                self?.poll()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func snoozeAfterFailedLock() {
        snoozedUntil = Date().addingTimeInterval(failedLockSnoozeSeconds)
    }

    private func poll() {
        guard let settings,
              let lock,
              !lock.isLocked,
              let threshold = settings.inactivityLock.seconds
        else { return }

        if let snoozedUntil {
            guard Date() >= snoozedUntil else { return }
            self.snoozedUntil = nil
        }

        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: Self.anyInputEventType
        )
        if idleSeconds >= threshold {
            log.info("Inactivity threshold reached; locking")
            lock.lock()
        }
    }
}
