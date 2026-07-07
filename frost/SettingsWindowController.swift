//
//  SettingsWindowController.swift
//  frost
//
//  Owns Frost's settings window directly. Relying on SwiftUI's Settings scene
//  responder action is brittle for an LSUIElement app because there is no normal
//  Dock/app-menu lifecycle to route that action through.
//

import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var settings: SettingsStore?
    private var launchAtLogin: LaunchAtLoginManager?
    private var updater: UpdaterController?
    private var pendingShow = false
    private var windowController: NSWindowController?

    private init() {}

    func configure(settings: SettingsStore, launchAtLogin: LaunchAtLoginManager, updater: UpdaterController) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.updater = updater
        if pendingShow {
            pendingShow = false
            show()
        }
    }

    func show() {
        guard let settings, let launchAtLogin, let updater else {
            pendingShow = true
            return
        }

        if windowController == nil {
            windowController = makeWindowController(
                settings: settings,
                launchAtLogin: launchAtLogin,
                updater: updater
            )
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        guard let window = windowController?.window else { return }
        window.makeKeyAndOrderFront(nil)
        // Cooperative activation (macOS 14+) may decline to activate an
        // LSUIElement agent; without this the window can open BEHIND the
        // frontmost app.
        window.orderFrontRegardless()
        // Don't open with the caret captured by the settings form's text
        // field (the form's only plain text input receives initial focus,
        // and clicking empty form space never resigns it).
        window.makeFirstResponder(nil)
    }

    private func makeWindowController(
        settings: SettingsStore,
        launchAtLogin: LaunchAtLoginManager,
        updater: UpdaterController
    ) -> NSWindowController {
        let hostingController = NSHostingController(rootView: SettingsView(
            settings: settings,
            launchAtLogin: launchAtLogin,
            updater: updater
        ))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Frost Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed
        let minimumSize = NSSize(width: 460, height: 320)
        let maximumContentHeight = Self.maximumContentHeight(minimumHeight: minimumSize.height)
        let fittingSize = hostingController.view.fittingSize
        let contentWidth = max(fittingSize.width, minimumSize.width)
        window.contentMinSize = minimumSize
        window.contentMaxSize = NSSize(width: contentWidth, height: maximumContentHeight)
        window.setContentSize(NSSize(
            width: contentWidth,
            height: min(max(fittingSize.height, minimumSize.height), maximumContentHeight)
        ))
        Self.center(window)

        return NSWindowController(window: window)
    }

    private static func maximumContentHeight(minimumHeight: CGFloat) -> CGFloat {
        let margin: CGFloat = 72
        guard let visibleFrame = preferredScreen()?.visibleFrame else { return minimumHeight }
        return max(minimumHeight, visibleFrame.height - margin)
    }

    private static func center(_ window: NSWindow) {
        guard let visibleFrame = preferredScreen()?.visibleFrame else {
            window.center()
            return
        }

        let frame = window.frame
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        ))
    }

    private static func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
