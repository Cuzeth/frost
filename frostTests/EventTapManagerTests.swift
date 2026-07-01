//
//  EventTapManagerTests.swift
//  frostTests
//
//  Exercises the tap-callback decision logic directly with synthetic CGEvents —
//  no live tap needed. This is the riskiest code in the app: a wrong answer
//  here either traps the user (chord not recognized, Esc not reaching the
//  Touch ID prompt) or leaks input (something swallowed that shouldn't be, or
//  vice versa).
//

import Carbon.HIToolbox
import CoreGraphics
import Testing

@testable import frost

@MainActor
struct EventTapManagerTests {

    private func keyEvent(
        _ key: Int,
        flags: CGEventFlags = [],
        keyDown: Bool = true
    ) throws -> CGEvent {
        let event = try #require(CGEvent(
            keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: keyDown))
        event.flags = flags
        return event
    }

    private func mouseEvent(_ type: CGEventType) throws -> CGEvent {
        try #require(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: .zero,
            mouseButton: .left))
    }

    // MARK: - Unlock chord

    @Test func unlockChordFiresCallbackAndIsSwallowed() throws {
        let manager = EventTapManager()
        manager.unlockShortcut = .defaultUnlock
        var fired = false
        manager.onUnlockChord = { fired = true }

        let chord = try keyEvent(
            kVK_ANSI_U, flags: [.maskControl, .maskAlternate, .maskCommand])
        #expect(manager.handle(type: .keyDown, event: chord))
        #expect(fired)
    }

    @Test func chordToleratesIrrelevantFlagBits() throws {
        let manager = EventTapManager()
        manager.unlockShortcut = .defaultUnlock
        var fired = false
        manager.onUnlockChord = { fired = true }

        let chord = try keyEvent(
            kVK_ANSI_U,
            flags: [.maskControl, .maskAlternate, .maskCommand, .maskAlphaShift])
        #expect(manager.handle(type: .keyDown, event: chord))
        #expect(fired)
    }

    @Test func nonChordKeyIsSwallowedWithoutCallback() throws {
        let manager = EventTapManager()
        manager.unlockShortcut = .defaultUnlock
        var fired = false
        manager.onUnlockChord = { fired = true }

        #expect(manager.handle(type: .keyDown, event: try keyEvent(kVK_ANSI_A)))
        #expect(manager.handle(
            type: .keyDown, event: try keyEvent(kVK_ANSI_U, flags: [.maskCommand])))
        #expect(!fired)
    }

    @Test func missingShortcutNeverFiresCallback() throws {
        // unlockShortcut unset (a state the controller should never allow) must
        // degrade to plain swallowing, not a crash or a spurious unlock.
        let manager = EventTapManager()
        var fired = false
        manager.onUnlockChord = { fired = true }

        let chord = try keyEvent(
            kVK_ANSI_U, flags: [.maskControl, .maskAlternate, .maskCommand])
        #expect(manager.handle(type: .keyDown, event: chord))
        #expect(!fired)
    }

    // MARK: - Escape passthrough during authentication

    @Test func bareEscapePassesThroughOnlyWhileAuthenticating() throws {
        let manager = EventTapManager()
        let escDown = try keyEvent(kVK_Escape)
        let escUp = try keyEvent(kVK_Escape, keyDown: false)

        // Idle locked: Esc is swallowed like everything else.
        #expect(manager.handle(type: .keyDown, event: escDown))
        #expect(manager.handle(type: .keyUp, event: escUp))

        // Authenticating: bare Esc (down AND up) must reach the system prompt.
        manager.setAuthenticating(true)
        #expect(!manager.handle(type: .keyDown, event: escDown))
        #expect(!manager.handle(type: .keyUp, event: escUp))

        // Back to idle: swallowed again.
        manager.setAuthenticating(false)
        #expect(manager.handle(type: .keyDown, event: escDown))
    }

    @Test func modifiedEscapeStaysSwallowedWhileAuthenticating() throws {
        // ⌘⌥Esc is the Force Quit chord: opening it steals focus from the
        // Touch ID prompt and strands the user. It must never pass through.
        let manager = EventTapManager()
        manager.setAuthenticating(true)

        let forceQuit = try keyEvent(
            kVK_Escape, flags: [.maskCommand, .maskAlternate])
        #expect(manager.handle(type: .keyDown, event: forceQuit))
        #expect(manager.handle(
            type: .keyDown, event: try keyEvent(kVK_Escape, flags: [.maskControl])))
    }

    // MARK: - Pointer / other events

    @Test func pointerEventsAreSwallowed() throws {
        let manager = EventTapManager()
        #expect(manager.handle(
            type: .mouseMoved, event: try mouseEvent(.mouseMoved)))
        #expect(manager.handle(
            type: .leftMouseDown, event: try mouseEvent(.leftMouseDown)))
        #expect(manager.handle(
            type: .scrollWheel, event: try mouseEvent(.mouseMoved)))
        #expect(manager.handle(
            type: .flagsChanged, event: try keyEvent(kVK_Shift)))
    }

    @Test func tapDisabledEventsAreNeverSwallowed() throws {
        // The disabled marker events must always be returned to the system;
        // with no live tap (shouldSuppress == false) they are simply ignored.
        let manager = EventTapManager()
        #expect(!manager.handle(
            type: .tapDisabledByTimeout, event: try keyEvent(kVK_ANSI_A)))
        #expect(!manager.handle(
            type: .tapDisabledByUserInput, event: try keyEvent(kVK_ANSI_A)))
    }
}
