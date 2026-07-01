//
//  UnlockCoordinatorTests.swift
//  frostTests
//
//  Covers the pure LAError → AuthenticationResult mapping that decides what
//  happens after a Touch ID evaluation: unlock, return to idle, or re-lock
//  with a notice. Getting a code wrong here either unlocks on failure or
//  strands the user behind a misleading message.
//

import Foundation
import LocalAuthentication
import Testing

@testable import frost

@MainActor
struct UnlockCoordinatorTests {

    private func laError(_ code: LAError.Code) -> NSError {
        NSError(domain: LAError.errorDomain, code: code.rawValue)
    }

    @Test func successWinsRegardlessOfError() {
        #expect(UnlockCoordinator.authenticationResult(
            success: true, error: nil) == .success)
        #expect(UnlockCoordinator.authenticationResult(
            success: true, error: laError(.systemCancel)) == .success)
    }

    @Test func failureWithoutErrorIsFailed() {
        #expect(UnlockCoordinator.authenticationResult(
            success: false, error: nil) == .failed)
    }

    @Test(arguments: [LAError.userCancel, .systemCancel, .appCancel])
    func cancellationCodesMapToCancelled(code: LAError.Code) {
        #expect(UnlockCoordinator.authenticationResult(
            success: false, error: laError(code)) == .cancelled)
    }

    @Test(arguments: [LAError.authenticationFailed, .userFallback])
    func failureCodesMapToFailed(code: LAError.Code) {
        #expect(UnlockCoordinator.authenticationResult(
            success: false, error: laError(code)) == .failed)
    }

    @Test(arguments: [
        LAError.biometryLockout, .biometryNotAvailable, .biometryNotEnrolled,
        .passcodeNotSet,
    ])
    func unavailabilityCodesMapToUnavailable(code: LAError.Code) {
        let result = UnlockCoordinator.authenticationResult(
            success: false, error: laError(code))
        guard case .unavailable = result else {
            Issue.record("\(code) mapped to \(result), expected .unavailable")
            return
        }
    }

    /// Lockout is terminal while input is suppressed — the message must give
    /// the exits that work and must not suggest retrying.
    @Test func lockoutMessageGivesWorkableExitsOnly() {
        let result = UnlockCoordinator.authenticationResult(
            success: false, error: laError(.biometryLockout))
        guard case .unavailable(let message) = result else {
            Issue.record("biometryLockout did not map to .unavailable")
            return
        }
        #expect(message.contains("pkill -x frost"))
        #expect(message.contains("power button"))
        #expect(!message.lowercased().contains("try again"))
    }

    @Test func transientUnavailabilityMessageOffersRetry() {
        let result = UnlockCoordinator.authenticationResult(
            success: false, error: laError(.biometryNotAvailable))
        guard case .unavailable(let message) = result else {
            Issue.record("biometryNotAvailable did not map to .unavailable")
            return
        }
        #expect(message.contains("unlock shortcut"))
    }

    @Test func nonLAErrorDomainIsFailed() {
        let error = NSError(domain: "dev.abdeen.frost.tests", code: 1)
        #expect(UnlockCoordinator.authenticationResult(
            success: false, error: error) == .failed)
    }

    @Test func unknownLAErrorCodeIsFailed() {
        let error = NSError(domain: LAError.errorDomain, code: 9999)
        #expect(UnlockCoordinator.authenticationResult(
            success: false, error: error) == .failed)
    }
}
