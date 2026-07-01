//
//  UnlockCoordinator.swift
//  frost
//
//  Wraps LocalAuthentication. Frost is Touch ID-only: the event tap suppresses
//  keyboard input while locked, so a typed password is not a viable unlock path.
//  Unlocking evaluates .deviceOwnerAuthenticationWithBiometrics on a fresh
//  LAContext, which presents the standard system Touch ID prompt.
//

import Foundation
import LocalAuthentication
import os

enum TouchIDCheck: Equatable {
    case available
    case unavailable(String)
}

/// Outcome of *evaluating* Touch ID.
enum AuthenticationResult: Equatable {
    case success
    case cancelled
    case failed
    case unavailable(String)
}

@MainActor
final class UnlockCoordinator {
    private var context: LAContext?
    private let policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
    private let log = Logger(subsystem: "dev.abdeen.frost", category: "Unlock")

    /// Frost is Touch ID-only. Check before suppressing input so machines
    /// without a usable Touch ID path never enter a lock.
    func checkTouchIDAvailability() -> TouchIDCheck {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error),
              context.biometryType == .touchID
        else {
            return .unavailable(Self.touchIDUnavailableMessage(error, whileLocked: false))
        }
        return .available
    }

    /// Presents the standard system Touch ID prompt and evaluates it. A fresh
    /// `LAContext` is created per call (a context evaluates only once) and held so
    /// an in-flight prompt can be cancelled via `cancel()`; it is cleared when the
    /// evaluation ends.
    func authenticate(reason: String) async -> AuthenticationResult {
        let context = LAContext()
        // Empty fallback title hides the password button — Touch ID only.
        context.localizedFallbackTitle = ""
        var error: NSError?

        guard context.canEvaluatePolicy(policy, error: &error),
              context.biometryType == .touchID
        else {
            return .unavailable(Self.touchIDUnavailableMessage(error, whileLocked: true))
        }

        self.context = context
        let result: AuthenticationResult = await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy,
                                   localizedReason: reason) { success, error in
                continuation.resume(returning: Self.authenticationResult(success: success, error: error))
            }
        }

        if self.context === context {
            self.context = nil
        }
        switch result {
        case .success: log.info("Touch ID succeeded")
        case .cancelled: log.info("Touch ID cancelled")
        case .failed: log.info("Touch ID failed")
        case .unavailable: log.error("Touch ID unavailable during unlock")
        }
        return result
    }

    /// Cancels an in-flight prompt — used by the DEBUG auto-unlock safety net so
    /// a stale Touch ID dialog doesn't linger after a forced teardown.
    func cancel() {
        context?.invalidate()
        context = nil
    }

    nonisolated static func authenticationResult(
        success: Bool,
        error: Error?
    ) -> AuthenticationResult {
        guard !success else { return .success }
        guard let error else { return .failed }
        let nsError = error as NSError
        guard nsError.domain == LAError.errorDomain,
              let code = LAError.Code(rawValue: nsError.code)
        else {
            return .failed
        }

        switch code {
        case .userCancel, .systemCancel, .appCancel:
            return .cancelled
        case .authenticationFailed, .userFallback:
            return .failed
        case .biometryLockout, .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
            return .unavailable(touchIDUnavailableMessage(nsError, whileLocked: true))
        default:
            return .failed
        }
    }

    nonisolated private static func touchIDUnavailableMessage(
        _ error: NSError?,
        whileLocked: Bool
    ) -> String {
        if whileLocked {
            // Lockout is terminal while input is suppressed: it clears only via
            // a typed password, which the tap makes impossible. "Try again"
            // would be false hope — every retry fails instantly. Say so, and
            // give the two exits that actually work.
            if let error,
               error.domain == LAError.errorDomain,
               LAError.Code(rawValue: error.code) == .biometryLockout {
                return """
                    Touch ID is locked after too many failed attempts and \
                    cannot recover while input is locked. From another device, \
                    run `pkill -x frost` over SSH (Remote Login must already \
                    be on), or press and hold the power button to shut down \
                    this Mac.
                    """
            }
            return """
                Touch ID is not available right now. Press the unlock shortcut \
                to try again. If Touch ID remains unavailable, use Remote Login \
                from another device, or a terminal opened before locking, to run \
                `pkill -x frost`.
                """
        }

        guard let error,
              error.domain == LAError.errorDomain,
              let code = LAError.Code(rawValue: error.code)
        else {
            return """
                Frost could not verify that Touch ID is available, so input was \
                not locked.
                """
        }

        switch code {
        case .biometryNotAvailable:
            return """
                Frost requires Touch ID. This Mac does not report a usable Touch \
                ID sensor, so input was not locked.
                """
        case .biometryNotEnrolled:
            return """
                Frost requires Touch ID. Add a fingerprint in System Settings, \
                then try again. Input was not locked.
                """
        case .biometryLockout:
            return """
                Touch ID is temporarily locked after too many attempts. Unlock \
                the Mac normally with your password, then try Frost again. Input \
                was not locked.
                """
        case .passcodeNotSet:
            return """
                Touch ID needs a Mac login password before Frost can use it. Set \
                one up in System Settings, then try again. Input was not locked.
                """
        default:
            return """
                Touch ID is not available right now. Frost did not lock input.
                """
        }
    }
}
