//
//  PermissionManager.swift
//  frost
//
//  Checks and requests the two permissions an active (suppressing) event tap
//  needs:
//    • Accessibility   — required for a .defaultTap to ALTER/suppress events.
//    • Input Monitoring — required to RECEIVE keyboard events in the tap.
//  Both are TCC-mediated and granted by the user in System Settings →
//  Privacy & Security. Neither is an entitlement.
//

import ApplicationServices
import CoreGraphics

@MainActor
final class PermissionManager {
    /// Accessibility trust (`AXIsProcessTrusted`).
    func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt if not yet granted.
    @discardableResult
    func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Input Monitoring access (`CGPreflightListenEventAccess`).
    func hasInputMonitoring() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// Shows the system Input Monitoring prompt if not yet granted.
    @discardableResult
    func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    var allGranted: Bool {
        hasAccessibility() && hasInputMonitoring()
    }
}
