//
//  InactivityLockMonitor.swift
//  frost
//
//  Polls macOS session idle time while Frost is unlocked and triggers the normal
//  lock path when the selected inactivity threshold is exceeded.
//

import CoreGraphics
import Foundation

@MainActor
final class InactivityLockMonitor {
    private weak var settings: SettingsStore?
    private weak var lock: LockController?
    private var pollTask: Task<Void, Never>?
    private var snoozedUntil: Date?
    private let failedLockSnoozeSeconds: TimeInterval = 60

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
            eventType: .null
        )
        if idleSeconds >= threshold {
            lock.lock()
        }
    }
}
