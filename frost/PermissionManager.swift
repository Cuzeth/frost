//
//  PermissionManager.swift
//  frost
//
//  Checks and requests the permission an active (suppressing) session event tap
//  needs. Accessibility is TCC-mediated and granted by the user in System
//  Settings → Privacy & Security. It is not an entitlement.
//

import ApplicationServices

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

    var allGranted: Bool {
        hasAccessibility()
    }
}
