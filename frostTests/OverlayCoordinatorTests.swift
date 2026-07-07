//
//  OverlayCoordinatorTests.swift
//  frostTests
//
//  Pins the two pure decisions extracted from OverlayCoordinator: whether a
//  screen-parameters change should defer past a live Touch ID prompt, and
//  which display becomes the active (keyed) one. Both are easy to get subtly
//  wrong and hard to exercise through real NSWindows/NSScreens.
//

import CoreGraphics
import Testing

@testable import frost

@MainActor
struct OverlayCoordinatorTests {

    // MARK: - screenChangeAction

    @Test func noWindowsIsIgnoredRegardlessOfAuthState() {
        #expect(
            OverlayCoordinator.screenChangeAction(hasWindows: false, isAuthenticating: false)
                == .ignore)
        #expect(
            OverlayCoordinator.screenChangeAction(hasWindows: false, isAuthenticating: true)
                == .ignore)
    }

    @Test func windowsPresentAndAuthenticatingDefers() {
        #expect(
            OverlayCoordinator.screenChangeAction(hasWindows: true, isAuthenticating: true)
                == .deferUntilAuthEnds)
    }

    @Test func windowsPresentAndIdleRebuildsImmediately() {
        #expect(
            OverlayCoordinator.screenChangeAction(hasWindows: true, isAuthenticating: false)
                == .rebuild)
    }

    // MARK: - shouldApplyDeferredRebuild

    @Test func deferredRebuildAppliesOnlyWhenNeededAndWindowsExist() {
        #expect(
            OverlayCoordinator.shouldApplyDeferredRebuild(
                needsRebuildAfterAuth: true, hasWindows: true) == true)
        #expect(
            OverlayCoordinator.shouldApplyDeferredRebuild(
                needsRebuildAfterAuth: true, hasWindows: false) == false)
        #expect(
            OverlayCoordinator.shouldApplyDeferredRebuild(
                needsRebuildAfterAuth: false, hasWindows: true) == false)
        #expect(
            OverlayCoordinator.shouldApplyDeferredRebuild(
                needsRebuildAfterAuth: false, hasWindows: false) == false)
    }

    // MARK: - activeScreenIndex

    @Test func mouseInsideSecondFrameSelectsIt() {
        let frames = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let index = OverlayCoordinator.activeScreenIndex(
            frames: frames, mouse: CGPoint(x: 150, y: 50), mainIndex: nil)
        #expect(index == 1)
    }

    @Test func mouseOutsideAllFramesFallsBackToMainIndex() {
        let frames = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let index = OverlayCoordinator.activeScreenIndex(
            frames: frames, mouse: CGPoint(x: 500, y: 500), mainIndex: 1)
        #expect(index == 1)
    }

    @Test func mouseOutsideAllFramesWithNoMainIndexFallsBackToFirst() {
        let frames = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let index = OverlayCoordinator.activeScreenIndex(
            frames: frames, mouse: CGPoint(x: 500, y: 500), mainIndex: nil)
        #expect(index == 0)
    }

    @Test func emptyFramesReturnsZero() {
        let index = OverlayCoordinator.activeScreenIndex(
            frames: [], mouse: .zero, mainIndex: nil)
        #expect(index == 0)
    }

    @Test func outOfRangeMainIndexFallsBackToFirst() {
        let frames = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let index = OverlayCoordinator.activeScreenIndex(
            frames: frames, mouse: CGPoint(x: 500, y: 500), mainIndex: 5)
        #expect(index == 0)
    }
}
