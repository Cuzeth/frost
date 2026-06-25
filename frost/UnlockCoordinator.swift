//
//  UnlockCoordinator.swift
//  frost
//
//  Wraps LocalAuthentication. Frost requires a Mac with Touch ID, then evaluates
//  .deviceOwnerAuthentication so the system can offer password fallback without
//  changing Frost's event-tap lifecycle.
//

import Foundation
import LocalAuthentication

enum TouchIDCheck: Equatable {
    case available
    case unavailable(String)
}

enum AuthenticationResult: Equatable {
    case prepared
    case success
    case cancelled
    case failed
    case unavailable(String)
}

@MainActor
final class UnlockCoordinator {
    private var context: LAContext?
    private let touchIDPolicy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
    private let unlockPolicy: LAPolicy = .deviceOwnerAuthentication

    var currentContext: LAContext? { context }

    /// Frost is Touch ID-gated. Check before suppressing input so machines
    /// without a usable Touch ID path never enter a lock.
    func checkTouchIDAvailability() -> TouchIDCheck {
        let context = LAContext()
        var error: NSError?
        let canEvaluateTouchID = context.canEvaluatePolicy(touchIDPolicy, error: &error)
        guard context.biometryType == .touchID else {
            return .unavailable(Self.touchIDUnavailableMessage(error, whileLocked: false))
        }

        if canEvaluateTouchID {
            return .available
        }

        if Self.isPasswordFallbackAvailable(for: error) {
            return .available
        }

        return .unavailable(Self.touchIDUnavailableMessage(error, whileLocked: false))
    }

    /// Creates the context that the overlay binds to LAAuthenticationView.
    /// Evaluation starts only after the embedded view reports that it exists.
    func prepareAuthenticationContext() -> AuthenticationResult {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Password"
        var error: NSError?

        let canEvaluateTouchID = context.canEvaluatePolicy(touchIDPolicy, error: &error)
        guard context.biometryType == .touchID else {
            return .unavailable(Self.touchIDUnavailableMessage(error, whileLocked: true))
        }

        guard canEvaluateTouchID || Self.isPasswordFallbackAvailable(for: error) else {
            return .unavailable(Self.touchIDUnavailableMessage(error, whileLocked: true))
        }

        guard context.canEvaluatePolicy(unlockPolicy, error: &error) else {
            return .unavailable(Self.unlockUnavailableMessage(error))
        }

        self.context = context
        return .prepared
    }

    /// Runs auth on the prepared, overlay-bound context.
    func authenticatePreparedContext(reason: String) async -> AuthenticationResult {
        guard let context else {
            return .unavailable(Self.unlockUnavailableMessage(nil))
        }

        let result: AuthenticationResult = await withCheckedContinuation { continuation in
            context.evaluatePolicy(unlockPolicy,
                                   localizedReason: reason) { success, error in
                continuation.resume(returning: Self.authenticationResult(success: success, error: error))
            }
        }

        if self.context === context {
            self.context = nil
        }
        return result
    }

    /// Cancels an in-flight prompt — used by the DEBUG auto-unlock safety net so
    /// a stale Touch ID dialog doesn't linger after a forced teardown.
    func cancel() {
        context?.invalidate()
        context = nil
    }

    nonisolated private static func authenticationResult(
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

    nonisolated private static func isPasswordFallbackAvailable(for error: NSError?) -> Bool {
        guard let error,
              error.domain == LAError.errorDomain,
              let code = LAError.Code(rawValue: error.code)
        else {
            return false
        }
        return code == .biometryLockout
    }

    nonisolated private static func unlockUnavailableMessage(_ error: NSError?) -> String {
        guard let error,
              error.domain == LAError.errorDomain,
              let code = LAError.Code(rawValue: error.code)
        else {
            return """
                Frost could not start macOS authentication. Press the unlock \
                shortcut to try again, or use `pkill -x frost` from Remote Login.
                """
        }

        switch code {
        case .passcodeNotSet:
            return """
                macOS password fallback is unavailable because this account has \
                no login password. Use `pkill -x frost` from Remote Login or a \
                terminal opened before locking.
                """
        default:
            return """
                macOS authentication is unavailable right now. Press the unlock \
                shortcut to try again, or use `pkill -x frost` from Remote Login.
                """
        }
    }

    nonisolated private static func touchIDUnavailableMessage(
        _ error: NSError?,
        whileLocked: Bool
    ) -> String {
        if whileLocked {
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
