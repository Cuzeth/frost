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
import os
import SwiftUI

@MainActor
final class OverlayCoordinator: NSObject {
    private var windows: [NSWindow] = []
    private let log = Logger(subsystem: "dev.abdeen.frost", category: "Overlay")
    /// Index into `windows` of the active-display window: it hosts the embedded
    /// authentication view and becomes key so the prompt is focused where the
    /// user is. Recomputed on every rebuild.
    private var authenticationWindowIndex = 0
    private weak var controller: LockController?
    /// Set when a screen-parameters change arrives mid-authentication. Rebuilding
    /// then would deallocate the embedded `LAAuthenticationView` and cancel the
    /// in-flight Touch ID evaluation, so the rebuild is deferred until Frost
    /// returns to the idle locked state (see `rebuildIfDeferred`).
    private var needsRebuildAfterAuth = false
    /// Owns the ONE embedded `LAAuthenticationView` for the current context.
    /// Shared by every overlay window's SwiftUI hierarchy so that SwiftUI
    /// re-creating the representable (during layout, or across the two displays'
    /// windows) can never produce a second view bound to the same context — two
    /// views fight over the context's UI delegate and the loser's deallocation
    /// cancels the evaluation. See `EmbeddedAuthHost`.
    private let authHost = EmbeddedAuthHost()

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
        log.info("Overlay presented on \(self.windows.count, privacy: .public) display(s)")
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

    /// Bring Frost forward and re-key the active-display window that hosts the
    /// embedded Touch ID prompt. The embedded `LAAuthenticationView` only arms
    /// the sensor when its window is key; on a fresh launch Frost isn't active
    /// yet when the overlay is first presented, so the lock-time
    /// `makeKeyAndOrderFront` doesn't stick. Called when authentication is armed
    /// so the very first prompt evaluates against a key window — otherwise the
    /// first attempt no-opped and the user had to Esc-cancel and retry.
    func focusAuthenticationWindow() {
        guard !windows.isEmpty else { return }
        let keyIndex = min(max(authenticationWindowIndex, 0), windows.count - 1)
        NSApp.activate(ignoringOtherApps: true)
        windows[keyIndex].makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        needsRebuildAfterAuth = false
        authHost.reset()
        controller = nil
        log.info("Overlay dismissed")
    }

    @objc private func screenParametersChanged() {
        guard !windows.isEmpty else { return }
        // Never rebuild while a Touch ID evaluation is live: rebuild() recreates
        // every window, which deallocates the embedded LAAuthenticationView and
        // makes LocalAuthentication cancel with "View was deallocated". Hiding the
        // menu bar for kiosk mode (at lock) and display sleep/wake (after idle)
        // both fire this notification right when the first prompt is evaluating.
        // Defer the rebuild until authentication ends.
        if controller?.isAuthenticating == true {
            needsRebuildAfterAuth = true
            log.info("Screen parameters changed during auth; deferring overlay rebuild")
            return
        }
        rebuild()
        show()
    }

    /// Apply a rebuild that was deferred because the screen-parameters change
    /// arrived mid-authentication. Called by `LockController` when it returns to
    /// the idle locked state, so the overlay still picks up any real display
    /// change that happened while the prompt was up.
    func rebuildIfDeferred() {
        guard needsRebuildAfterAuth, !windows.isEmpty else { return }
        needsRebuildAfterAuth = false
        log.info("Applying overlay rebuild deferred during auth")
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
            safeAreaInsets: screen.safeAreaInsets.swiftUIInsets,
            authHost: authHost
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
    let authHost: EmbeddedAuthHost
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    // Scale the card width with Dynamic Type so large accessibility text sizes
    // have room to wrap instead of clipping against a hard-coded width.
    @ScaledMetric private var cardWidth: CGFloat = 430

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(
                280,
                proxy.size.width - safeAreaInsets.leading - safeAreaInsets.trailing - 32
            )

            ZStack {
                // A stronger scrim (paired with an opaque card) when the user has
                // asked to reduce transparency, so text stays legible over a busy
                // desktop showing through.
                Color.black.opacity(reduceTransparency ? 0.6 : 0.35).ignoresSafeArea()
                card(maxWidth: availableWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(safeAreaInsets)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func card(maxWidth: CGFloat) -> some View {
        switch controller.state {
        case .recovery(let recovery):
            recoveryCard(recovery, width: min(cardWidth + 10, maxWidth))
        default:
            lockedCard(width: min(cardWidth, maxWidth))
        }
    }

    private var authenticating: Bool { controller.state == .authenticating }

    private func lockedCard(width: CGFloat) -> some View {
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
        .frame(width: width)
        .background(cardBackground(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 32, y: 18)
        .accessibilityElement(children: .contain)
    }

    /// Card fill: translucent material normally, but a near-opaque solid when the
    /// user has reduced transparency, so legibility never depends on the desktop
    /// showing through behind the text.
    @ViewBuilder
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            shape.fill(Color.black.opacity(0.85))
        } else {
            shape.fill(.ultraThinMaterial)
        }
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
        .accessibilityHidden(true)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Unlock shortcut: \(controller.unlockShortcutSpoken). Press to open the Touch ID prompt.")
    }

    private var authenticatingPrompt: some View {
        VStack(spacing: 12) {
            if showsEmbeddedAuthentication, let context = controller.authenticationContext {
                EmbeddedAuthenticationView(
                    host: authHost,
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Input paused, pointer frozen, local authentication")
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

    // A filled banner with dark text, so the warning meets contrast over any
    // desktop and regardless of reduce-transparency — yellow text on translucent
    // material did not.
    private func warningText(_ message: String, font: Font = .footnote) -> some View {
        Text(message)
            .font(font.weight(.medium))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func recoveryCard(_ recovery: RecoveryState, width: CGFloat) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(recovery.title)
                .font(.title2.weight(.semibold))
            Text(recovery.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Promote the primary action and push the destructive Quit to the
            // trailing edge so the button hierarchy is unambiguous.
            ViewThatFits(in: .horizontal) {
                recoveryButtons(recovery)
                stackedRecoveryButtons(recovery)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: width)
        .background(cardBackground(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    private func recoveryButtons(_ recovery: RecoveryState) -> some View {
        HStack(spacing: 12) {
            if recovery.showsAccessibilitySettings {
                Button("Open Privacy Settings") { controller.openAccessibilitySettings() }
                    .buttonStyle(.borderedProminent)
                Button("Dismiss") { controller.dismissRecovery() }
                Spacer(minLength: 0)
                Button("Quit Frost") { controller.quitFrost() }
            } else {
                if recovery.allowsRetry {
                    Button("Try Again") { controller.retryRecovery() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Button("Dismiss") { controller.dismissRecovery() }
            }
        }
    }

    private func stackedRecoveryButtons(_ recovery: RecoveryState) -> some View {
        VStack(spacing: 10) {
            if recovery.showsAccessibilitySettings {
                Button("Open Privacy Settings") { controller.openAccessibilitySettings() }
                    .buttonStyle(.borderedProminent)
                Button("Dismiss") { controller.dismissRecovery() }
                Button("Quit Frost") { controller.quitFrost() }
            } else {
                if recovery.allowsRetry {
                    Button("Try Again") { controller.retryRecovery() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Button("Dismiss") { controller.dismissRecovery() }
            }
        }
    }
}

/// Single source of truth for the embedded `LAAuthenticationView`. Owned by the
/// `OverlayCoordinator` (one per overlay, NOT per SwiftUI view), it vends exactly
/// one `LAAuthenticationView` per `LAContext`. Because every overlay window's
/// SwiftUI hierarchy shares this one host, SwiftUI re-creating the representable —
/// during a layout pass or across the two displays' windows — returns the SAME
/// view instead of spawning a second one. That matters because each
/// `LAAuthenticationView` registers itself as the context's UI delegate on init;
/// two of them on one context fight over that delegate, and the loser's
/// deallocation cancels the live evaluation with "View was deallocated" — the
/// intermittent failure that forced an Esc-and-retry.
@MainActor
final class EmbeddedAuthHost {
    private var view: EmbeddedAuthView?
    private var boundContext: ObjectIdentifier?
    private let log = Logger(subsystem: "dev.abdeen.frost", category: "Overlay")

    func view(for context: LAContext, onReady: @escaping (LAContext) -> Void) -> EmbeddedAuthView {
        let id = ObjectIdentifier(context)
        if let view, boundContext == id { return view }
        // New context (or first use): drop any prior view and build the one view.
        view?.removeFromSuperview()
        // `.regular` keeps the Touch ID control compact enough to sit inside the
        // card. Combined with `.fixedSize()` on the SwiftUI side, the view is laid
        // out at its own intrinsic size, so it never overflows its box the way a
        // `.large` control forced into a smaller frame did.
        let created = EmbeddedAuthView(context: context, controlSize: .regular)
        created.setContentHuggingPriority(.required, for: .horizontal)
        created.setContentHuggingPriority(.required, for: .vertical)
        created.setContentCompressionResistancePriority(.required, for: .horizontal)
        created.setContentCompressionResistancePriority(.required, for: .vertical)
        created.onReadyToEvaluate = { onReady(context) }
        view = created
        boundContext = id
        log.info("Created embedded auth view (shared host)")
        return created
    }

    func reset() {
        view?.removeFromSuperview()
        view = nil
        boundContext = nil
    }
}

private struct EmbeddedAuthenticationView: NSViewRepresentable {
    let host: EmbeddedAuthHost
    let authenticationContext: LAContext
    let onReady: (LAContext) -> Void

    func makeNSView(context: Context) -> EmbeddedAuthView {
        host.view(for: authenticationContext, onReady: onReady)
    }

    func updateNSView(_ view: EmbeddedAuthView, context: Context) {}
}

/// `LAAuthenticationView` that reports when it is ready to evaluate — i.e. it has
/// joined a window AND that window is key. The embedded Touch ID sensor only arms
/// while its window is key; calling `evaluatePolicy` against a non-key window
/// silently shows no prompt (the bug behind "unlock, Esc, unlock again"). Frost
/// is an LSUIElement agent, so `NSApp.activate` + `makeKeyAndOrderFront` make the
/// window key only a few run-loop cycles later — after the attach callback. So we
/// wait for `didBecomeKeyNotification` (or fire immediately if the window is
/// already key) before evaluating. A fallback timer evaluates anyway if key
/// status never arrives, preserving the Esc-cancel escape hatch rather than
/// stranding the user. The notify hop also lets the first layout pass settle.
final class EmbeddedAuthView: LAAuthenticationView {
    var onReadyToEvaluate: (() -> Void)?
    private var didNotify = false
    private var keyObserver: (any NSObjectProtocol)?
    private var fallback: DispatchWorkItem?
    private let log = Logger(subsystem: "dev.abdeen.frost", category: "Overlay")

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            // Detached before we fired; drop any pending waiters.
            log.info("Embedded auth view detached from window (notified=\(self.didNotify, privacy: .public))")
            teardownWaiters()
            return
        }
        log.info("Embedded auth view attached to window (key=\(window.isKeyWindow, privacy: .public), notified=\(self.didNotify, privacy: .public))")
        guard !didNotify else { return }

        if window.isKeyWindow {
            notifyReady()
            return
        }

        // Arm evaluation the instant the window becomes key.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.notifyReady()
        }

        // Safety net: if key status never arrives, evaluate anyway so the user
        // can still Esc-cancel and retry instead of facing a dead prompt. This is
        // strictly no worse than the pre-fix behavior.
        let work = DispatchWorkItem { [weak self] in self?.notifyReady() }
        fallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func notifyReady() {
        guard !didNotify, window != nil else { return }
        didNotify = true
        teardownWaiters()
        // One more hop so the first layout pass settles before evaluation.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.log.info("Embedded auth view ready; starting evaluation")
            self.onReadyToEvaluate?()
        }
    }

    private func teardownWaiters() {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
            self.keyObserver = nil
        }
        fallback?.cancel()
        fallback = nil
    }

    deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        fallback?.cancel()
    }
}
