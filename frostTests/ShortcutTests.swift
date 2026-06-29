//
//  ShortcutTests.swift
//  frostTests
//
//  Covers the value-type heart of Frost: how a Shortcut normalizes modifiers,
//  matches the three event dialects (raw keyCode/modifiers, CGEvent, NSEvent),
//  renders itself, and survives a Codable round-trip.
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Testing

@testable import frost

// `@MainActor` to match the app's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
// MainActor-isolated conformances (Equatable/Codable on Shortcut) are usable here.
@MainActor
struct ShortcutTests {

    // MARK: - Initialization & normalization

    @Test func initStripsIrrelevantModifiers() {
        let s = Shortcut(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: [.command, .capsLock, .function, .numericPad]
        )
        #expect(s.modifierFlags == [.command])
    }

    @Test func relevantModifiersAreTheFourChordKeys() {
        #expect(Shortcut.relevantModifiers == [.command, .option, .control, .shift])
    }

    @Test func defaultUnlockIsControlOptionCommandU() {
        let s = Shortcut.defaultUnlock
        #expect(s.keyCode == UInt16(kVK_ANSI_U))
        #expect(s.modifierFlags == [.control, .option, .command])
    }

    // MARK: - Equatable (driven by normalization)

    @Test func equalityIgnoresIrrelevantModifiers() {
        let a = Shortcut(keyCode: 0, modifierFlags: [.command])
        let b = Shortcut(keyCode: 0, modifierFlags: [.command, .capsLock])
        #expect(a == b)
    }

    @Test func differingKeyOrModifiersAreNotEqual() {
        let base = Shortcut(keyCode: 0, modifierFlags: [.command])
        #expect(base != Shortcut(keyCode: 1, modifierFlags: [.command]))
        #expect(base != Shortcut(keyCode: 0, modifierFlags: [.command, .shift]))
    }

    // MARK: - matches(keyCode:modifiers:)

    @Test func matchesExactKeyAndModifiers() {
        #expect(Shortcut.defaultUnlock.matches(
            keyCode: UInt16(kVK_ANSI_U), modifiers: [.control, .option, .command]))
    }

    @Test func matchesIgnoresIrrelevantModifierBits() {
        // CapsLock / Fn etc. on the incoming event must not break a match.
        #expect(Shortcut.defaultUnlock.matches(
            keyCode: UInt16(kVK_ANSI_U),
            modifiers: [.control, .option, .command, .capsLock]))
    }

    @Test func rejectsExtraRelevantModifier() {
        #expect(!Shortcut.defaultUnlock.matches(
            keyCode: UInt16(kVK_ANSI_U),
            modifiers: [.control, .option, .command, .shift]))
    }

    @Test func rejectsMissingModifier() {
        #expect(!Shortcut.defaultUnlock.matches(
            keyCode: UInt16(kVK_ANSI_U), modifiers: [.control, .option]))
    }

    @Test func rejectsWrongKeyCode() {
        #expect(!Shortcut.defaultUnlock.matches(
            keyCode: UInt16(kVK_ANSI_I), modifiers: [.control, .option, .command]))
    }

    // MARK: - matches(cgEvent:)  — the unlock path inside the event tap

    @Test func matchesCGEventWithEquivalentFlags() throws {
        let event = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_U), keyDown: true))
        event.flags = [.maskControl, .maskAlternate, .maskCommand]
        #expect(Shortcut.defaultUnlock.matches(cgEvent: event))
    }

    @Test func cgEventMapsShiftFlag() throws {
        let event = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Space), keyDown: true))
        event.flags = [.maskShift]
        let shortcut = Shortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.shift])
        #expect(shortcut.matches(cgEvent: event))
    }

    @Test func cgEventWithWrongFlagsDoesNotMatch() throws {
        let event = try #require(
            CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_U), keyDown: true))
        event.flags = [.maskCommand]
        #expect(!Shortcut.defaultUnlock.matches(cgEvent: event))
    }

    // MARK: - matches(nsEvent:)  — the lock-hotkey path

    @Test func matchesNSEvent() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .option, .command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "u",
            charactersIgnoringModifiers: "u",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_U)))
        #expect(Shortcut.defaultUnlock.matches(nsEvent: event))
    }

    @Test func rejectsNonMatchingNSEvent() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "u",
            charactersIgnoringModifiers: "u",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_U)))
        #expect(!Shortcut.defaultUnlock.matches(nsEvent: event))
    }

    // MARK: - Display

    @Test func displayStringOrdersModifiersCanonically() {
        // Canonical macOS order is ⌃⌥⇧⌘, regardless of construction order.
        let s = Shortcut(
            keyCode: UInt16(kVK_Space),
            modifierFlags: [.command, .shift, .option, .control]
        )
        #expect(s.displayString == "⌃⌥⇧⌘Space")
    }

    @Test func displayStringWithoutModifiers() {
        let s = Shortcut(keyCode: UInt16(kVK_Return), modifierFlags: [])
        #expect(s.displayString == "↩")
    }

    // MARK: - keyName

    @Test func keyNameSpecialKeys() {
        #expect(Shortcut.keyName(for: UInt16(kVK_Return)) == "↩")
        #expect(Shortcut.keyName(for: UInt16(kVK_Tab)) == "⇥")
        #expect(Shortcut.keyName(for: UInt16(kVK_Space)) == "Space")
        #expect(Shortcut.keyName(for: UInt16(kVK_Delete)) == "⌫")
        #expect(Shortcut.keyName(for: UInt16(kVK_Escape)) == "⎋")
        #expect(Shortcut.keyName(for: UInt16(kVK_ForwardDelete)) == "⌦")
        #expect(Shortcut.keyName(for: UInt16(kVK_LeftArrow)) == "←")
        #expect(Shortcut.keyName(for: UInt16(kVK_F1)) == "F1")
        #expect(Shortcut.keyName(for: UInt16(kVK_F12)) == "F12")
    }

    @Test func keyNameLetterKeysAreUppercased() {
        // Assumes a Latin (ANSI-capable) keyboard layout — what Frost's display
        // targets. character(forKeyCode:) goes through the live layout.
        #expect(Shortcut.keyName(for: UInt16(kVK_ANSI_A)) == "A")
        #expect(Shortcut.keyName(for: UInt16(kVK_ANSI_U)) == "U")
    }

    @Test func keyNameUnknownKeyFallsBack() {
        // No special glyph and no character → "Key <code>".
        #expect(Shortcut.keyName(for: 1000) == "Key 1000")
    }

    // MARK: - Codable

    @Test func codableRoundTrip() throws {
        let original = Shortcut(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .shift])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        #expect(decoded == original)
    }

    @Test func defaultUnlockRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(Shortcut.defaultUnlock)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        #expect(decoded == .defaultUnlock)
        #expect(decoded.displayString == Shortcut.defaultUnlock.displayString)
    }
}
