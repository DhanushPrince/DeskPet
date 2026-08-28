import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import DeskPetKit

@Suite("Pet drag math")
struct PetDragMathTests {
    static let petSize = Constants.petWindowSize   // 220 × 340

    // MARK: Offset clamping

    @Test("an offset inside the window is kept, rounded")
    func offsetInsideWindow() {
        let offset = PetDragMath.clampOffset(CGPoint(x: 110.4, y: 170.6), in: Self.petSize)
        #expect(offset.x == 110)
        #expect(offset.y == 171)
    }

    @Test("an offset outside the window is clamped to its edges")
    func offsetClamped() {
        #expect(PetDragMath.clampOffset(CGPoint(x: -50, y: -50), in: Self.petSize) == .zero)

        let far = PetDragMath.clampOffset(CGPoint(x: 900, y: 900), in: Self.petSize)
        // Inclusive of the far edge, matching the Electron clamp.
        #expect(far.x == 220)
        #expect(far.y == 340)
    }

    // MARK: Click versus drag

    @Test("travel at or below the threshold is still a click")
    func belowThresholdIsClick() {
        let start = CGPoint(x: 100, y: 100)
        #expect(!PetDragMath.exceedsDragThreshold(from: start, to: start))
        #expect(!PetDragMath.exceedsDragThreshold(from: start, to: CGPoint(x: 109, y: 100)))
        // Exactly 10 is not a drag: the original comparison is strictly greater.
        #expect(!PetDragMath.exceedsDragThreshold(from: start, to: CGPoint(x: 110, y: 100)))
    }

    @Test("travel beyond the threshold is a drag")
    func aboveThresholdIsDrag() {
        let start = CGPoint(x: 100, y: 100)
        #expect(PetDragMath.exceedsDragThreshold(from: start, to: CGPoint(x: 111, y: 100)))
        #expect(PetDragMath.exceedsDragThreshold(from: start, to: CGPoint(x: 100, y: 88)))
        // Diagonal: hypot(8, 8) ≈ 11.3 > 10.
        #expect(PetDragMath.exceedsDragThreshold(from: start, to: CGPoint(x: 108, y: 108)))
        // hypot(7, 7) ≈ 9.9 < 10.
        #expect(!PetDragMath.exceedsDragThreshold(from: start, to: CGPoint(x: 107, y: 107)))
    }

    // MARK: Target bounds

    @Test("the drag anchor stays under the cursor")
    func anchorFollowsCursor() {
        let bounds = PetDragMath.targetBounds(
            cursor: CGPoint(x: 500, y: 400),
            offset: CGPoint(x: 110, y: 170),
            size: Self.petSize
        )
        #expect(bounds.x == 390)
        #expect(bounds.y == 230)
        #expect(bounds.width == 220)
        #expect(bounds.height == 340)
        // The anchor point maps back to the cursor.
        #expect(bounds.x + 110 == 500)
        #expect(bounds.y + 170 == 400)
    }

    @Test("a zero offset puts the window's top-left at the cursor")
    func zeroOffset() {
        let bounds = PetDragMath.targetBounds(
            cursor: CGPoint(x: 42, y: 84),
            offset: .zero,
            size: Self.petSize
        )
        #expect(bounds.x == 42)
        #expect(bounds.y == 84)
    }

    // MARK: Facing

    @Test("facing follows horizontal travel")
    func facingFromDelta() {
        #expect(PetDragMath.facing(fromDeltaX: 5, current: .left) == .right)
        #expect(PetDragMath.facing(fromDeltaX: -5, current: .right) == .left)
    }

    @Test("no horizontal travel leaves facing unchanged")
    func facingUnchangedOnVerticalDrag() {
        #expect(PetDragMath.facing(fromDeltaX: 0, current: .left) == .left)
        #expect(PetDragMath.facing(fromDeltaX: 0, current: .right) == .right)
    }
}

@Suite("Pet drag behaviour", .serialized)
@MainActor
struct PetDragBehaviourTests {

    @Test("a click without travel reports a click, not a drag")
    func clickReported() {
        let view = PetContentView(frame: CGRect(origin: .zero, size: Constants.petWindowSize))
        var clicks = 0
        var dragStarts = 0
        view.onClick = { clicks += 1 }
        view.onDragStart = { _ in dragStarts += 1 }

        view.mouseDown(with: MouseEventFactory.down(at: CGPoint(x: 110, y: 170)))
        view.mouseUp(with: MouseEventFactory.up(at: CGPoint(x: 110, y: 170)))

        #expect(clicks == 1)
        #expect(dragStarts == 0)
    }

    @Test("travel past the threshold starts a drag and suppresses the click")
    func dragSuppressesClick() {
        let view = PetContentView(frame: CGRect(origin: .zero, size: Constants.petWindowSize))
        var clicks = 0
        var dragStarts: [CGPoint] = []
        var dragEnds = 0
        view.onClick = { clicks += 1 }
        view.onDragStart = { dragStarts.append($0) }
        view.onDragEnd = { dragEnds += 1 }

        view.mouseDown(with: MouseEventFactory.down(at: CGPoint(x: 100, y: 200)))
        view.mouseDragged(with: MouseEventFactory.dragged(at: CGPoint(x: 140, y: 200)))
        view.mouseUp(with: MouseEventFactory.up(at: CGPoint(x: 140, y: 200)))

        #expect(clicks == 0)
        #expect(dragEnds == 1)
        #expect(dragStarts.count == 1)
        // The anchor is the original press point in top-left coordinates.
        // mouseDown at Cocoa y=200 in a 340-tall view → top-left y = 140.
        #expect(dragStarts.first?.x == 100)
        #expect(dragStarts.first?.y == 140)
    }

    @Test("a drag start is reported only once")
    func dragStartsOnce() {
        let view = PetContentView(frame: CGRect(origin: .zero, size: Constants.petWindowSize))
        var dragStarts = 0
        view.onDragStart = { _ in dragStarts += 1 }

        view.mouseDown(with: MouseEventFactory.down(at: CGPoint(x: 100, y: 200)))
        for x in stride(from: 140.0, to: 200.0, by: 10) {
            view.mouseDragged(with: MouseEventFactory.dragged(at: CGPoint(x: x, y: 200)))
        }
        #expect(dragStarts == 1)
    }

    @Test("small jitter during a press does not start a drag")
    func jitterIsNotADrag() {
        let view = PetContentView(frame: CGRect(origin: .zero, size: Constants.petWindowSize))
        var dragStarts = 0
        var clicks = 0
        view.onDragStart = { _ in dragStarts += 1 }
        view.onClick = { clicks += 1 }

        view.mouseDown(with: MouseEventFactory.down(at: CGPoint(x: 100, y: 200)))
        view.mouseDragged(with: MouseEventFactory.dragged(at: CGPoint(x: 104, y: 203)))
        view.mouseUp(with: MouseEventFactory.up(at: CGPoint(x: 104, y: 203)))

        #expect(dragStarts == 0)
        #expect(clicks == 1)
    }

    @Test("dragging moves the window and keeps it in the work area")
    func dragMovesWindowClamped() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.startDrag(offset: CGPoint(x: 110, y: 170))
        #expect(controller.isDragging)

        // The window follows the real cursor, so assert the invariant that
        // matters: it stays inside a visible work area.
        let bounds = controller.globalBounds
        let clamped = DisplayGeometry.visibleBounds(
            displays: ScreenBridge.displays,
            primaryDisplay: ScreenBridge.primaryDisplay,
            bounds: bounds
        )
        #expect(clamped == bounds)

        controller.stopDrag()
        #expect(!controller.isDragging)
    }

    @Test("a drag forces interactivity and releases it on completion")
    func dragForcesInteractivity() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.startDrag(offset: .zero)
        #expect(!controller.window.ignoresMouseEvents)

        controller.stopDrag()
        controller.mouseTracker.update(cursor: CGPoint(x: -5000, y: -5000))
        #expect(controller.window.ignoresMouseEvents)
    }

    @Test("finishing a drag reports a position to persist")
    func dragPersistsPosition() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        var saved: SavedWindowPosition?
        controller.onPositionChanged = { saved = $0 }

        controller.startDrag(offset: .zero)
        controller.stopDrag()

        let position = try #require(saved, "drag end should report a position")
        #expect(position.displayId != nil)
        #expect((position.relativeX ?? -1) >= 0)
        #expect((position.relativeY ?? -1) >= 0)
    }

    @Test("stopping without a drag reports nothing")
    func noDragNoPersist() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        var reported = 0
        controller.onPositionChanged = { _ in reported += 1 }
        controller.stopDrag()
        #expect(reported == 0)
    }

    @Test("dragging is refused while blocked")
    func dragBlocked() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.isDragBlocked = { true }
        controller.startDrag(offset: .zero)
        #expect(!controller.isDragging)
    }

    @Test("hiding the pet cancels an active drag")
    func hideCancelsDrag() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()

        controller.startDrag(offset: .zero)
        #expect(controller.isDragging)
        controller.hide()
        #expect(!controller.isDragging)
    }

    @Test("clamping into the visible area reports a position")
    func clampReportsPosition() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        var saved: SavedWindowPosition?
        controller.onPositionChanged = { saved = $0 }

        // Push the pet far off any display, then clamp it back.
        controller.setGlobalBounds(GlobalRect(x: 99_000, y: 99_000, width: 220, height: 340))
        controller.clampIntoVisibleArea()

        #expect(saved != nil)
        let bounds = controller.globalBounds
        let clamped = DisplayGeometry.visibleBounds(
            displays: ScreenBridge.displays,
            primaryDisplay: ScreenBridge.primaryDisplay,
            bounds: bounds
        )
        #expect(clamped == bounds)
    }

    @Test("right-click is reported to the context menu hook")
    func rightClickReported() {
        let view = PetContentView(frame: CGRect(origin: .zero, size: Constants.petWindowSize))
        var events = 0
        view.onRightClick = { _ in events += 1 }
        view.rightMouseDown(with: MouseEventFactory.rightDown(at: CGPoint(x: 110, y: 170)))
        #expect(events == 1)
    }
}

/// Synthesises the mouse events the view expects. `locationInWindow` is in
/// Cocoa (bottom-left) coordinates, which is what AppKit would deliver.
enum MouseEventFactory {
    static func make(type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    static func down(at point: CGPoint) -> NSEvent { make(type: .leftMouseDown, at: point) }
    static func dragged(at point: CGPoint) -> NSEvent { make(type: .leftMouseDragged, at: point) }
    static func up(at point: CGPoint) -> NSEvent { make(type: .leftMouseUp, at: point) }
    static func rightDown(at point: CGPoint) -> NSEvent { make(type: .rightMouseDown, at: point) }
}
