//
//  OverlayCoordinator.swift
//  frost
//
//  Owns the borderless overlay windows — one per display, each joining all
//  Spaces, so the dim covers every desktop and monitor. Rebuilt on display
//  changes. Content is placed inside each screen's safe area so the central
//  affordance does not sit under a notched display housing.
//
//  The embedded authentication view (and the key window that drives it) live on
//  the ACTIVE display — the one the pinned cursor is on, i.e. where the lock was
//  triggered — not always the menu-bar display. Locking from a secondary monitor
//  must put the Touch ID prompt where the user is looking.
//
//  The overlay is intentionally semi-transparent: Frost keeps the display
//  VISIBLE while input is locked, so you can watch whatever is running.
//

import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import SwiftUI

@MainActor
final class OverlayCoordinator: NSObject {
    private var windows: [NSWindow] = []
    /// Index into `windows` of the active-display window: it hosts the embedded
    /// authentication view and becomes key so the prompt is focused where the
    /// user is. Recomputed on every rebuild.
    private var authenticationWindowIndex = 0
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
        guard !windows.isEmpty else { return }
        let keyIndex = min(max(authenticationWindowIndex, 0), windows.count - 1)
        // Order the non-key windows first, then key the active-display window
        // last so it ends up frontmost and focused.
        for (index, window) in windows.enumerated() where index != keyIndex {
            window.orderFrontRegardless()
        }
        windows[keyIndex].makeKeyAndOrderFront(nil)
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
        let screens = NSScreen.screens
        authenticationWindowIndex = Self.activeScreenIndex(in: screens)
        for (index, screen) in screens.enumerated() {
            windows.append(makeWindow(
                for: screen,
                controller: controller,
                showsEmbeddedAuthentication: index == authenticationWindowIndex
            ))
        }
    }

    /// The display the user is on — where the lock was triggered. The cursor is
    /// pinned for the whole session, so its location stays on the lock-time
    /// display and the embedded prompt follows it across rebuilds. Falls back to
    /// the main screen, then the first screen, if the cursor isn't on any screen.
    private static func activeScreenIndex(in screens: [NSScreen]) -> Int {
        guard !screens.isEmpty else { return 0 }
        let mouse = NSEvent.mouseLocation
        if let index = screens.firstIndex(where: { $0.frame.contains(mouse) }) {
            return index
        }
        if let main = NSScreen.main, let index = screens.firstIndex(of: main) {
            return index
        }
        return 0
    }

    private func makeWindow(
        for screen: NSScreen,
        controller: LockController,
        showsEmbeddedAuthentication: Bool
    ) -> NSWindow {
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
            showsEmbeddedAuthentication: showsEmbeddedAuthentication,
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
    var showsEmbeddedAuthentication: Bool
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
                         ? "Touch ID"
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
                Text("Press to open the Touch ID prompt")
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
            if showsEmbeddedAuthentication, let context = controller.authenticationContext {
                EmbeddedAuthenticationView(
                    authenticationContext: context,
                    onReady: controller.authenticationViewReady
                )
                .id(ObjectIdentifier(context))
                .fixedSize()
            } else {
                Image(systemName: "touchid")
                    .font(.system(size: 44, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }

            Text("Use Touch ID. Press Esc to cancel and keep input locked.")
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
            statusPill(icon: "touchid", text: "Local auth")
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

private struct EmbeddedAuthenticationView: NSViewRepresentable {
    let authenticationContext: LAContext
    let onReady: (LAContext) -> Void

    func makeNSView(context: Context) -> EmbeddedAuthView {
        // `.regular` keeps the Touch ID control compact enough to sit inside the
        // card. Combined with `.fixedSize()` on the SwiftUI side, the view is
        // laid out at its own intrinsic size, so it never overflows its box the
        // way a `.large` control forced into a smaller frame did.
        let view = EmbeddedAuthView(
            context: authenticationContext,
            controlSize: .regular
        )
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        // Start evaluation only once the view has actually joined the window (see
        // EmbeddedAuthView). Firing from makeNSView was too early on first
        // presentation: the prompt had nowhere to render, so the first Touch ID
        // attempt silently no-opped and you had to Esc-cancel and retry.
        view.onAttachedToWindow = { onReady(authenticationContext) }
        return view
    }

    func updateNSView(_ view: EmbeddedAuthView, context: Context) {}
}

/// `LAAuthenticationView` that reports when it has joined a window, so the caller
/// can defer `evaluatePolicy` until the embedded UI can actually render. The
/// deferred hop also lets the first layout pass settle before evaluation starts.
private final class EmbeddedAuthView: LAAuthenticationView {
    var onAttachedToWindow: (() -> Void)?
    private var didNotify = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didNotify else { return }
        didNotify = true
        DispatchQueue.main.async { [weak self] in
            guard self?.window != nil else { return }
            self?.onAttachedToWindow?()
        }
    }
}
