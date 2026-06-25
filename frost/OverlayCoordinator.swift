//
//  OverlayCoordinator.swift
//  frost
//
//  Owns the borderless overlay windows — one per display, each joining all
//  Spaces, so the dim covers every desktop and monitor. Rebuilt on display
//  changes. (Notch safe-area handling still TODO.)
//
//  The overlay is intentionally semi-transparent: Frost keeps the display
//  VISIBLE while input is locked, so you can watch whatever is running.
//

import AppKit
import SwiftUI

@MainActor
final class OverlayCoordinator: NSObject {
    private var windows: [NSWindow] = []
    private weak var controller: LockController?

    func present(controller: LockController) {
        self.controller = controller
        rebuild()
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        setVisible(true)
    }

    /// Hide/show every overlay window — used to reveal the screen during auth.
    func setVisible(_ visible: Bool) {
        for window in windows {
            if visible { window.orderFrontRegardless() } else { window.orderOut(nil) }
        }
    }

    func dismiss() {
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        controller = nil
    }

    @objc private func screenParametersChanged() {
        guard !windows.isEmpty else { return }
        rebuild()
        setVisible(true)
    }

    private func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard let controller else { return }
        for screen in NSScreen.screens {
            windows.append(makeWindow(for: screen, controller: controller))
        }
    }

    private func makeWindow(for screen: NSScreen, controller: LockController) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame,
                              styleMask: .borderless,
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false   // recovery buttons must be clickable
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LockOverlayView(controller: controller))
        window.setFrame(screen.frame, display: true)
        return window
    }
}

// MARK: - Overlay UI

struct LockOverlayView: View {
    @ObservedObject var controller: LockController

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            card
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var card: some View {
        switch controller.state {
        case .recovery(let message):
            recoveryCard(message)
        default:
            lockedCard
        }
    }

    private var authenticating: Bool { controller.state == .authenticating }

    private var lockedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
            Text("Input Locked")
                .font(.title2.weight(.semibold))
            Text(authenticating
                 ? "Use Touch ID to unlock · press Esc to cancel"
                 : "Press \(controller.unlockShortcutDisplay) to unlock (Touch ID)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if authenticating {
                ProgressView().padding(.top, 4)
            }
            #if DEBUG
            if let seconds = controller.debugSecondsRemaining {
                Text("DEBUG auto-unlock in \(seconds)s")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.yellow)
            }
            #endif
        }
        .padding(28)
        .frame(width: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func recoveryCard(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.yellow)
            Text("Input Not Locked")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Open Privacy Settings") { controller.openAccessibilitySettings() }
                Button("Dismiss") { controller.dismissRecovery() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
