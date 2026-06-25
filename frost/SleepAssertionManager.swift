//
//  SleepAssertionManager.swift
//  frost
//
//  Holds IOKit power assertions while locked so an unattended-but-visible task
//  stays on screen. Two independent assertions, matching the two settings:
//    • PreventUserIdleDisplaySleep — keeps the display awake, which also stops
//      the screen saver from starting ("prevent screen saver").
//    • PreventUserIdleSystemSleep  — stops idle system sleep ("prevent sleep").
//
//  Assertions are acquired on lock and released on unlock/teardown. They do NOT
//  override the power button or a closed lid — only the idle timers.
//

import Foundation
import IOKit.pwr_mgt
import os

@MainActor
final class SleepAssertionManager {
    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var holdingDisplay = false
    private var holdingSystem = false
    private let log = Logger(subsystem: "dev.abdeen.frost", category: "Sleep")

    deinit {
        MainActor.assumeIsolated {
            releaseAll()
        }
    }

    /// Reconcile held assertions with what the settings ask for.
    func apply(preventScreenSaver: Bool, preventSleep: Bool) {
        setDisplay(preventScreenSaver)
        setSystem(preventSleep)
    }

    /// Release everything — always called on teardown so we never leak an
    /// assertion that keeps the Mac awake after unlock.
    func releaseAll() {
        setDisplay(false)
        setSystem(false)
    }

    private func setDisplay(_ on: Bool) {
        guard on != holdingDisplay else { return }
        if on {
            holdingDisplay = create(kIOPMAssertionTypePreventUserIdleDisplaySleep,
                                    reason: "Frost is locked — screen saver prevented",
                                    into: &displayAssertion)
        } else {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
            holdingDisplay = false
        }
    }

    private func setSystem(_ on: Bool) {
        guard on != holdingSystem else { return }
        if on {
            holdingSystem = create(kIOPMAssertionTypePreventUserIdleSystemSleep,
                                   reason: "Frost is locked — sleep prevented",
                                   into: &systemAssertion)
        } else {
            IOPMAssertionRelease(systemAssertion)
            systemAssertion = 0
            holdingSystem = false
        }
    }

    private func create(_ type: String, reason: String, into id: inout IOPMAssertionID) -> Bool {
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        if result != kIOReturnSuccess {
            log.error("IOPMAssertionCreateWithName(\(type, privacy: .public)) failed: \(result)")
            return false
        }
        return true
    }
}
