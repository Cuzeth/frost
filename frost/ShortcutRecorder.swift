//
//  ShortcutRecorder.swift
//  frost
//
//  A small click-to-record keyboard-shortcut field. SwiftUI has no native
//  recorder, so this wraps a focus-capturing NSView: click it, press a combo,
//  and it reports the captured Shortcut. A bare modifier-less key is rejected
//  (every Frost shortcut needs at least one of ⌃⌥⇧⌘); Esc cancels recording and
//  Delete clears (when clearing is allowed).
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    /// When false (the required unlock field) Delete won't clear the value.
    var allowsClear: Bool

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.allowsClear = allowsClear
        field.shortcut = shortcut
        field.onChange = { context.coordinator.commit($0) }
        return field
    }

    func updateNSView(_ field: RecorderField, context: Context) {
        context.coordinator.binding = $shortcut
        field.allowsClear = allowsClear
        // Don't stomp on the value the user is mid-recording.
        if !field.isRecording { field.shortcut = shortcut }
    }

    func makeCoordinator() -> Coordinator { Coordinator(binding: $shortcut) }

    final class Coordinator {
        var binding: Binding<Shortcut?>
        init(binding: Binding<Shortcut?>) { self.binding = binding }
        func commit(_ shortcut: Shortcut?) { binding.wrappedValue = shortcut }
    }
}

/// The focus-capturing control behind ShortcutRecorder.
final class RecorderField: NSView {
    var allowsClear = false
    var onChange: ((Shortcut?) -> Void)?

    var shortcut: Shortcut? {
        didSet { refresh() }
    }
    private(set) var isRecording = false {
        didSet { refresh() }
    }

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
            isRecording = true
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    // ⌘-based combos arrive as key equivalents; intercept them while recording
    // so the menu doesn't eat them first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return capture(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        _ = capture(event)
    }

    /// Returns true if the event was consumed.
    private func capture(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(Shortcut.relevantModifiers)
        let unmodified = modifiers.isEmpty

        // Bare Esc cancels; bare Delete clears (when allowed). With modifiers,
        // these are normal keys and fall through to be recorded as a shortcut.
        if unmodified {
            switch Int(event.keyCode) {
            case kVK_Escape:
                stopRecording()
                return true
            case kVK_Delete, kVK_ForwardDelete:
                if allowsClear {
                    shortcut = nil
                    onChange?(nil)
                }
                stopRecording()
                return true
            default:
                // No modifier and not a control key — keep waiting for a combo.
                NSSound.beep()
                return true
            }
        }

        let captured = Shortcut(keyCode: event.keyCode, modifierFlags: modifiers)
        shortcut = captured
        onChange?(captured)
        stopRecording()
        return true
    }

    private func stopRecording() {
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    private func refresh() {
        label.stringValue = displayText
        label.textColor = (shortcut == nil && !isRecording) ? .secondaryLabelColor : .labelColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    private var displayText: String {
        if isRecording { return "Type shortcut…" }
        if let shortcut { return shortcut.displayString }
        return allowsClear ? "Click to record" : "—"
    }
}
