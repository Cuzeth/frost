//
//  UnlockCoordinator.swift
//  frost
//
//  Wraps LocalAuthentication. Unlock uses .deviceOwnerAuthentication — Touch ID
//  with automatic password fallback.
//

import Foundation
import LocalAuthentication

@MainActor
final class UnlockCoordinator {
    private var context: LAContext?

    /// Presents Touch ID / password and resolves to whether auth succeeded.
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        self.context = context

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// Cancels an in-flight prompt — used by the DEBUG auto-unlock safety net so
    /// a stale Touch ID dialog doesn't linger after a forced teardown.
    func cancel() {
        context?.invalidate()
        context = nil
    }
}
