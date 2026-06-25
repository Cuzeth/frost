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
    /// Accessibility trust without showing the system prompt.
    func hasAccessibility() -> Bool {
        checkAccessibility(prompt: false)
    }

    /// Shows the system Accessibility prompt if not yet granted.
    @discardableResult
    func requestAccessibility() -> Bool {
        checkAccessibility(prompt: true)
    }

    private func checkAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    var allGranted: Bool {
        hasAccessibility()
    }
}
