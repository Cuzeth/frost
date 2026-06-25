//
//  UpdaterController.swift
//  frost
//
//  Thin wrapper around Sparkle's SPUStandardUpdaterController so SwiftUI can
//  drive "Check for Updates…" and reflect whether a check is currently allowed.
//

import Combine
import Foundation
import Sparkle

/// Owns the Sparkle updater for the app's lifetime.
///
/// Sparkle is the *only* component in Frost that touches the network — it
/// fetches the appcast at `SUFeedURL` and verifies downloads against
/// `SUPublicEDKey` (both in Info.plist). There is no telemetry and no other
/// network use.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors `SPUUpdater.canCheckForUpdates` so the menu item can disable
    /// itself while an update session is already in flight.
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true → Sparkle starts immediately and schedules its
        // automatic background checks using the Info.plist configuration.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Triggers a user-initiated update check (shows Sparkle's standard UI).
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
