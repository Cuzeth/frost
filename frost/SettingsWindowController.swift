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
    private var pendingShow = false
    private var windowController: NSWindowController?

    private init() {}

    func configure(settings: SettingsStore) {
        self.settings = settings
        if pendingShow {
            pendingShow = false
            show()
        }
    }

    func show() {
        guard let settings else {
            pendingShow = true
            return
        }

        if windowController == nil {
            windowController = makeWindowController(settings: settings)
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindowController(settings: SettingsStore) -> NSWindowController {
        let hostingController = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Frost Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed
        let minimumSize = NSSize(width: 460, height: 320)
        let fittingSize = hostingController.view.fittingSize
        window.minSize = minimumSize
        window.setContentSize(NSSize(
            width: max(fittingSize.width, minimumSize.width),
            height: max(fittingSize.height, minimumSize.height)
        ))
        window.center()

        return NSWindowController(window: window)
    }
}
