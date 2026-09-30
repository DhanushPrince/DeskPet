import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import DeskPetKit

/// Notch detection lives on real `NSScreen` state, which cannot be mocked, so
/// these tests exercise the real display (skipping on headless CI) and assert
/// the invariants that must hold either way rather than a specific geometry.
@Suite("Notch detection")
struct ScreenBridgeNotchTests {
    static let petSize = Constants.petWindowSize   // 220 × 340

    @Test("notchScreen is nil or a real attached screen")
    func notchScreenIsPlausible() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        if let notchScreen = ScreenBridge.notchScreen {
            #expect(NSScreen.screens.contains(notchScreen))
            #expect(notchScreen.safeAreaInsets.top > 0)
        }
        // No assertion when nil: most CI runners and external-monitor-only Macs
        // have no notch, and that is a valid, expected outcome.
    }

    @Test("notchHangRect is nil exactly when there is no notch screen")
    func notchHangRectMatchesDetection() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        let rect = ScreenBridge.notchHangRect(size: Self.petSize)
        if ScreenBridge.notchScreen == nil {
            #expect(rect == nil)
        } else {
            #expect(rect != nil)
        }
    }

    @Test("notchHangRect, when present, sizes the pet exactly and sits at the top of the screen")
    func notchHangRectGeometryIsSane() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        try #require(ScreenBridge.notchScreen != nil, "no notch on this machine")

        let rect = try #require(ScreenBridge.notchHangRect(size: Self.petSize))
        #expect(rect.width == Double(Self.petSize.width))
        #expect(rect.height == Double(Self.petSize.height))
        // The window extends above the sprite so the drawn pet, not the empty
        // bubble band, meets the bottom of the notch. That sprite top sits in
        // the menu-bar band, just under the camera.
        let spriteTop = rect.y + Double(Constants.notchSpriteTopInset)
        #expect(spriteTop >= 0)
        #expect(spriteTop < 80)
    }

    @Test("notchGeometry is nil for a screen with a zero top safe-area inset")
    func notchGeometryNilWithoutInset() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let nonNotchScreens = NSScreen.screens.filter { $0.safeAreaInsets.top == 0 }
        for screen in nonNotchScreens {
            #expect(ScreenBridge.notchGeometry(for: screen) == nil)
        }
    }
}
