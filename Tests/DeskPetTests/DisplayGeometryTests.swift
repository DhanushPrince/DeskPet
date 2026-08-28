import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import DeskPetKit

/// Ported from `tests/displayPosition.test.ts`, with the original fixtures.
@Suite("Display geometry")
struct DisplayGeometryTests {
    static let primary = DisplayBounds(
        id: 1,
        workArea: GlobalRect(x: 0, y: 0, width: 1440, height: 900)
    )
    static let secondary = DisplayBounds(
        id: 2,
        workArea: GlobalRect(x: 1440, y: 0, width: 1280, height: 900)
    )
    static let petSize = Constants.petWindowSize   // 220 × 340

    private func rect(x: Double, y: Double) -> GlobalRect {
        GlobalRect(origin: CGPoint(x: x, y: y), size: Self.petSize)
    }

    // MARK: Ported cases

    @Test("a pet on a removed display is moved back into the primary work area")
    func clampsBackFromRemovedDisplay() {
        let offscreen = rect(x: 2400, y: 560)
        let bounds = DisplayGeometry.visibleBounds(
            displays: [Self.primary],
            primaryDisplay: Self.primary,
            bounds: offscreen
        )
        #expect(bounds.x == 1220)
        #expect(bounds.y == 560)
    }

    @Test("saved position records the display id and relative coordinates")
    func savedPositionRecordsDisplay() throws {
        let saved = DisplayGeometry.savedPosition(
            displays: [Self.primary, Self.secondary],
            bounds: rect(x: 2080, y: 280),
            fallback: Self.primary
        )
        #expect(saved.displayId == Self.secondary.id)
        let relativeX = try #require(saved.relativeX)
        let relativeY = try #require(saved.relativeY)
        #expect(relativeX >= 0 && relativeX <= 1)
        #expect(relativeY >= 0 && relativeY <= 1)
    }

    @Test("relative position is restored on the same display after a resolution change")
    func restoresRelativePositionAfterResize() {
        let saved = DisplayGeometry.savedPosition(
            displays: [Self.primary, Self.secondary],
            bounds: rect(x: 2080, y: 280),
            fallback: Self.primary
        )
        let resized = DisplayBounds(
            id: Self.secondary.id,
            workArea: GlobalRect(x: 1440, y: 0, width: 1600, height: 1000)
        )

        let restored = DisplayGeometry.initialBounds(
            displays: [Self.primary, resized],
            primaryDisplay: Self.primary,
            size: Self.petSize,
            saved: saved
        )

        #expect(restored.x > resized.workArea.x)
        #expect(restored.x < resized.workArea.maxX)
        #expect(restored.y > resized.workArea.y)
        #expect(restored.y < resized.workArea.maxY)
    }

    @Test("a saved display that no longer exists falls back to the nearest visible one")
    func fallsBackWhenSavedDisplayIsGone() {
        let bounds = DisplayGeometry.initialBounds(
            displays: [Self.primary],
            primaryDisplay: Self.primary,
            size: Self.petSize,
            saved: SavedWindowPosition(
                x: 2400, y: 560,
                displayId: Self.secondary.id,
                relativeX: 0.5, relativeY: 1
            )
        )
        #expect(bounds.x == 1220)
        #expect(bounds.y == 560)
    }

    // MARK: Default placement

    @Test("with no saved position the pet opens bottom-centre of the primary display")
    func defaultPlacement() {
        let bounds = DisplayGeometry.initialBounds(
            displays: [Self.primary],
            primaryDisplay: Self.primary,
            size: Self.petSize,
            saved: nil
        )
        // 1440/2 - 220/2 = 610; 900 - 340 = 560
        #expect(bounds.x == 610)
        #expect(bounds.y == 560)
        // Compared as Double: mixing Double and CGFloat inside #expect makes the
        // macro capture two differently-typed operands and report a spurious
        // mismatch even when the values are identical.
        #expect(bounds.width == Double(Self.petSize.width))
        #expect(bounds.height == Double(Self.petSize.height))
    }

    // MARK: Clamping

    @Test("clamping pins each edge independently")
    func clampsEachEdge() {
        let work = Self.primary.workArea
        #expect(DisplayGeometry.clampToWorkArea(rect(x: -50, y: 400), work).x == 0)
        #expect(DisplayGeometry.clampToWorkArea(rect(x: 5000, y: 400), work).x == 1220)
        #expect(DisplayGeometry.clampToWorkArea(rect(x: 400, y: -50), work).y == 0)
        #expect(DisplayGeometry.clampToWorkArea(rect(x: 400, y: 5000), work).y == 560)
    }

    @Test("a window larger than the work area pins to the work area origin")
    func oversizedWindowPinsToOrigin() {
        let tiny = GlobalRect(x: 0, y: 0, width: 300, height: 200)
        let huge = GlobalRect(x: 100, y: 100, width: 900, height: 900)
        let clamped = DisplayGeometry.clampToWorkArea(huge, tiny)
        #expect(clamped.x == 0)
        #expect(clamped.y == 0)
    }

    @Test("an empty display list yields the fallback display")
    func emptyDisplayListUsesFallback() {
        let resolved = DisplayGeometry.displayForBounds(
            displays: [],
            bounds: rect(x: 10, y: 10),
            fallback: Self.primary
        )
        #expect(resolved == Self.primary)
    }

    @Test("the display containing the window centre wins over the nearest one")
    func centreContainmentWins() {
        let onSecondary = rect(x: 1500, y: 100)
        let resolved = DisplayGeometry.displayForBounds(
            displays: [Self.primary, Self.secondary],
            bounds: onSecondary,
            fallback: Self.primary
        )
        #expect(resolved.id == Self.secondary.id)
    }

    // MARK: Negative-coordinate rounding

    @Test("rounding matches JavaScript Math.round for negative halves")
    func jsRoundSemantics() {
        #expect(DisplayGeometry.jsRound(2.5) == 3)
        #expect(DisplayGeometry.jsRound(-2.5) == -2)   // Swift's rounded() gives -3
        #expect(DisplayGeometry.jsRound(-2.6) == -3)
        #expect(DisplayGeometry.jsRound(2.4) == 2)
    }

    @Test("a display left of the primary one places the default position correctly")
    func defaultPlacementOnNegativeOriginDisplay() {
        let leftOfPrimary = DisplayBounds(
            id: 3,
            workArea: GlobalRect(x: -1281, y: 0, width: 1280, height: 900)
        )
        let bounds = DisplayGeometry.initialBounds(
            displays: [leftOfPrimary],
            primaryDisplay: leftOfPrimary,
            size: Self.petSize,
            saved: nil
        )
        // -1281 + 640 - 110 = -751
        #expect(bounds.x == -751)
        #expect(bounds.y == 560)
    }

    // MARK: Coordinate space round trip

    @Test("global ↔ Cocoa rect conversion round-trips", arguments: [
        GlobalRect(x: 0, y: 0, width: 220, height: 340),
        GlobalRect(x: 610, y: 560, width: 220, height: 340),
        GlobalRect(x: -751, y: 120, width: 220, height: 340),
        GlobalRect(x: 1500, y: 0, width: 1280, height: 900)
    ])
    func rectRoundTrip(rect: GlobalRect) {
        let height = 900.0
        let cocoa = CoordinateSpace.cocoaRect(fromGlobal: rect, primaryFrameHeight: height)
        let back = CoordinateSpace.globalRect(fromCocoa: cocoa, primaryFrameHeight: height)
        #expect(back == rect)
    }

    @Test("the global origin maps to the top-left of the primary display")
    func originMapsToTopLeft() {
        let height = 900.0
        // A 340pt-tall window at global y=0 sits with its top edge at the top of
        // the screen, so its Cocoa bottom edge is at 900 - 340 = 560.
        let cocoa = CoordinateSpace.cocoaRect(
            fromGlobal: GlobalRect(x: 0, y: 0, width: 220, height: 340),
            primaryFrameHeight: height
        )
        #expect(cocoa.minX == 0)
        #expect(cocoa.minY == 560)
        #expect(cocoa.maxY == 900)
    }

    @Test("point conversion is its own inverse")
    func pointRoundTrip() {
        let height = 1080.0
        let global = CGPoint(x: 300, y: 200)
        let cocoa = CoordinateSpace.cocoaPoint(fromGlobal: global, primaryFrameHeight: height)
        #expect(cocoa.y == 880)
        #expect(CoordinateSpace.globalPoint(fromCocoa: cocoa, primaryFrameHeight: height) == global)
    }

    // MARK: Live screen bridge

    @Test("the live screen bridge reports a usable primary display")
    func liveScreenBridge() throws {
        // Skipped when no display is attached (headless CI).
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        let primary = ScreenBridge.primaryDisplay
        #expect(primary.workArea.width > 0)
        #expect(primary.workArea.height > 0)
        // The menu bar means the primary work area starts below the top of the
        // screen in global coordinates.
        #expect(primary.workArea.y >= 0)
        #expect(ScreenBridge.displays.contains { $0.id == primary.id })
        #expect(ScreenBridge.primaryFrameHeight > 0)
    }

    @Test("the pet's default position is inside the real primary work area")
    func defaultPositionIsOnScreen() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        let displays = ScreenBridge.displays
        let primary = ScreenBridge.primaryDisplay
        let bounds = DisplayGeometry.initialBounds(
            displays: displays,
            primaryDisplay: primary,
            size: Constants.petWindowSize,
            saved: nil
        )
        let clamped = DisplayGeometry.visibleBounds(
            displays: displays,
            primaryDisplay: primary,
            bounds: bounds
        )
        #expect(clamped == bounds, "default placement should already be on screen")
    }
}
