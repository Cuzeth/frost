//
//  InactivityLockMonitorTests.swift
//  frostTests
//
//  Behavioral coverage for auto-lock timing. The monitor combines macOS' session
//  idle timer with Frost's own local baseline so changing settings or unlocking
//  via Touch ID does not immediately re-lock from stale global idle time.
//

import Foundation
import Testing

@testable import frost

@MainActor
final class InactivityLockMonitorTests {
    private let suiteName: String
    private let defaults: UserDefaults
    private var now = Date(timeIntervalSinceReferenceDate: 0)
    private var systemIdleSeconds: TimeInterval = 0
    private var lockCount = 0
    private var locked = false

    init() {
        suiteName = "dev.abdeen.frost.monitor-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test func enablingAutoLockStartsAFreshLocalCountdown() {
        let settings = SettingsStore(defaults: defaults)
        let monitor = makeMonitor(settings: settings)
        defer { monitor.stop() }

        systemIdleSeconds = 999
        settings.inactivityLock = .thirtySeconds

        monitor.poll()
        #expect(lockCount == 0)

        advance(by: 29)
        monitor.poll()
        #expect(lockCount == 0)

        advance(by: 1)
        monitor.poll()
        #expect(lockCount == 1)
    }

    @Test func resetIdleBaselinePreventsImmediateRelockAfterUnlock() {
        let settings = SettingsStore(defaults: defaults)
        settings.inactivityLock = .thirtySeconds
        let monitor = makeMonitor(settings: settings)
        defer { monitor.stop() }

        systemIdleSeconds = 999
        advance(by: 30)
        monitor.poll()
        #expect(lockCount == 1)

        lockCount = 0
        monitor.resetIdleBaseline()
        monitor.poll()
        #expect(lockCount == 0)

        advance(by: 30)
        monitor.poll()
        #expect(lockCount == 1)
    }

    @Test func recentSystemInputStillPreventsLockAfterLocalBaselineElapses() {
        let settings = SettingsStore(defaults: defaults)
        settings.inactivityLock = .thirtySeconds
        let monitor = makeMonitor(settings: settings)
        defer { monitor.stop() }

        advance(by: 120)
        systemIdleSeconds = 5
        monitor.poll()
        #expect(lockCount == 0)

        systemIdleSeconds = 30
        monitor.poll()
        #expect(lockCount == 1)
    }

    @Test func failedLockSnoozeSuppressesRepeatedAttemptsTemporarily() {
        let settings = SettingsStore(defaults: defaults)
        settings.inactivityLock = .thirtySeconds
        let monitor = makeMonitor(settings: settings)
        defer { monitor.stop() }

        systemIdleSeconds = 999
        monitor.snoozeAfterFailedLock()

        advance(by: 59)
        monitor.poll()
        #expect(lockCount == 0)

        advance(by: 1)
        monitor.poll()
        #expect(lockCount == 1)
    }

    @Test func lockedStateSuppressesAutoLockAttempts() {
        let settings = SettingsStore(defaults: defaults)
        settings.inactivityLock = .thirtySeconds
        let monitor = makeMonitor(settings: settings)
        defer { monitor.stop() }

        locked = true
        systemIdleSeconds = 999
        advance(by: 999)
        monitor.poll()

        #expect(lockCount == 0)
    }

    private func makeMonitor(settings: SettingsStore) -> InactivityLockMonitor {
        let monitor = InactivityLockMonitor(
            now: { [weak self] in self?.now ?? Date() },
            idleSeconds: { [weak self] in self?.systemIdleSeconds ?? 0 }
        )
        monitor.start(
            settings: settings,
            isLocked: { [weak self] in self?.locked ?? true },
            lock: { [weak self] in self?.lockCount += 1 },
            pollAutomatically: false
        )
        return monitor
    }

    private func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}
