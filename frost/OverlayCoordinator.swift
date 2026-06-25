//
//  OverlayCoordinator.swift
//  frost
//
//  Owns the borderless overlay windows — one per display, each joining all
//  Spaces, so the dim covers every desktop and monitor. Rebuilt on display
//  changes. Content is placed inside each screen's safe area so the central
//  affordance does not sit under a notched display housing.
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

    deinit {
        MainActor.assumeIsolated {
            dismiss()
        }
    }

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
        show()
    }

    private func show() {
        for window in windows {
            if window == windows.first {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
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
        show()
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
        let window = OverlayWindow(contentRect: screen.frame,
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
        window.contentView = NSHostingView(rootView: LockOverlayView(
            controller: controller,
            safeAreaInsets: screen.safeAreaInsets.swiftUIInsets
        ))
        window.setFrame(screen.frame, display: true)
        return window
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private extension NSEdgeInsets {
    var swiftUIInsets: EdgeInsets {
        EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
    }
}

// MARK: - Overlay UI

struct LockOverlayView: View {
    @ObservedObject var controller: LockController
    var safeAreaInsets: EdgeInsets

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            card
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(safeAreaInsets)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var card: some View {
        switch controller.state {
        case .recovery(let recovery):
            recoveryCard(recovery)
        default:
            lockedCard
        }
    }

    private var authenticating: Bool { controller.state == .authenticating }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                authenticationMark

                VStack(alignment: .leading, spacing: 4) {
                    Text(authenticating ? "Authenticate" : "Input Locked")
                        .font(.title2.weight(.semibold))
                    Text(authenticating
                         ? "Touch ID required"
                         : "Keyboard, mouse, and trackpad input are paused")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if authenticating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(24)

            Divider()
                .padding(.horizontal, 24)

            VStack(spacing: 16) {
                if authenticating {
                    authenticatingPrompt
                } else {
                    unlockPrompt
                }

                safetyStrip

                if let notice = controller.tapRecoveryNotice {
                    warningText(notice)
                }

                #if DEBUG
                if let seconds = controller.debugSecondsRemaining {
                    warningText("DEBUG auto-unlock in \(seconds)s", font: .footnote.monospacedDigit())
                }
                #endif
            }
            .padding(24)
        }
        .frame(width: 430)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 32, y: 18)
    }

    private var authenticationMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(authenticating ? 0.16 : 0.10))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
            Image(systemName: authenticating ? "touchid" : "lock.fill")
                .font(.system(size: authenticating ? 36 : 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(authenticating ? Color.accentColor : Color.primary)
        }
        .frame(width: 72, height: 72)
    }

    private var unlockPrompt: some View {
        HStack(spacing: 14) {
            keycap(controller.unlockShortcutDisplay)

            VStack(alignment: .leading, spacing: 3) {
                Text("Unlock Shortcut")
                    .font(.headline)
                Text("Press to open the macOS authentication prompt")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var authenticatingPrompt: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text("macOS authentication is waiting")
                    .font(.headline)
            }

            Text("Use Touch ID to unlock. Press Esc to cancel and keep input locked.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var safetyStrip: some View {
        HStack(spacing: 8) {
            statusPill(icon: "keyboard", text: "Input paused")
            statusPill(icon: "cursorarrow", text: "Pointer frozen")
            statusPill(icon: "touchid", text: "Touch ID")
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 14)
            .frame(minWidth: 106, minHeight: 44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
            }
    }

    private func statusPill(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.07), in: Capsule())
    }

    private func warningText(_ message: String, font: Font = .footnote) -> some View {
        Text(message)
            .font(font)
            .foregroundStyle(.yellow)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func recoveryCard(_ recovery: RecoveryState) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.yellow)
            Text(recovery.title)
                .font(.title2.weight(.semibold))
            Text(recovery.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                if recovery.showsAccessibilitySettings {
                    Button("Open Privacy Settings") { controller.openAccessibilitySettings() }
                }
                if recovery.allowsRetry {
                    Button("Try Again") { controller.retryRecovery() }
                        .keyboardShortcut(.defaultAction)
                }
                Button("Dismiss") { controller.dismissRecovery() }
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
