import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import DeskPetKit

/// Ported from `tests/petHitbox.test.ts`.
@Suite("Pet hitbox")
struct PetHitboxTests {
    static let petRect = CGRect(x: 0, y: 0, width: 220, height: 340)

    @Test("the centre is inside the hitbox")
    func centreIsInside() {
        #expect(PetHitbox.contains(CGPoint(x: 110, y: 170), in: Self.petRect))
    }

    @Test("corners are outside the 80% hitbox")
    func cornersAreOutside() {
        // Inset is 10% per side: x < 22 or x > 198, y < 34 or y > 306.
        #expect(!PetHitbox.contains(CGPoint(x: 0, y: 0), in: Self.petRect))
        #expect(!PetHitbox.contains(CGPoint(x: 219, y: 339), in: Self.petRect))
        #expect(!PetHitbox.contains(CGPoint(x: 10, y: 170), in: Self.petRect))
        #expect(!PetHitbox.contains(CGPoint(x: 110, y: 10), in: Self.petRect))
    }

    @Test("the hitbox edges are inclusive")
    func edgesAreInclusive() {
        // 220 * 0.1 = 22, 340 * 0.1 = 34.
        #expect(PetHitbox.contains(CGPoint(x: 22, y: 34), in: Self.petRect))
        #expect(PetHitbox.contains(CGPoint(x: 198, y: 306), in: Self.petRect))
        #expect(!PetHitbox.contains(CGPoint(x: 21.9, y: 170), in: Self.petRect))
        #expect(!PetHitbox.contains(CGPoint(x: 110, y: 306.1), in: Self.petRect))
    }

    @Test("a rect offset from the origin shifts the hitbox with it")
    func respectsRectOrigin() {
        let offset = CGRect(x: 100, y: 200, width: 220, height: 340)
        #expect(PetHitbox.contains(CGPoint(x: 210, y: 370), in: offset))
        #expect(!PetHitbox.contains(CGPoint(x: 110, y: 170), in: offset))
    }

    @Test("a degenerate rect never contains a point")
    func degenerateRect() {
        #expect(!PetHitbox.contains(.zero, in: CGRect(x: 0, y: 0, width: 0, height: 340)))
        #expect(!PetHitbox.contains(.zero, in: CGRect(x: 0, y: 0, width: 220, height: 0)))
        #expect(!PetHitbox.contains(.zero, in: CGRect(x: 0, y: 0, width: -220, height: -340)))
    }

    @Test("scales outside (0, 1] are rejected rather than clamped")
    func invalidScales() {
        let centre = CGPoint(x: 110, y: 170)
        #expect(!PetHitbox.contains(centre, in: Self.petRect, scale: 0))
        #expect(!PetHitbox.contains(centre, in: Self.petRect, scale: -0.5))
        #expect(!PetHitbox.contains(centre, in: Self.petRect, scale: 1.5))
        // Exactly 1 is valid and covers the whole rect.
        #expect(PetHitbox.contains(CGPoint(x: 0, y: 0), in: Self.petRect, scale: 1))
    }

    @Test("the derived hitbox rect matches the containment test")
    func hitboxRectAgreesWithContains() {
        let box = PetHitbox.rect(in: Self.petRect)
        // 1 - 0.8 is not exact in binary floating point, so compare with a
        // tolerance. `contains` derives its bounds from the same expression, so
        // the two stay consistent regardless.
        #expect(abs(box.width - 176) < 1e-9)     // 220 * 0.8
        #expect(abs(box.height - 272) < 1e-9)    // 340 * 0.8
        #expect(abs(box.minX - 22) < 1e-9)
        #expect(abs(box.minY - 34) < 1e-9)

        // The rect and the predicate agree everywhere except on the far edges,
        // which `contains` treats as inclusive and `CGRect.contains` does not.
        for x in stride(from: 1.0, to: 219.0, by: 7) {
            for y in stride(from: 1.0, to: 339.0, by: 11) {
                let point = CGPoint(x: x, y: y)
                #expect(
                    PetHitbox.contains(point, in: Self.petRect) == box.contains(point),
                    "disagreement at \(point)"
                )
            }
        }
    }
}

@Suite("Click-through", .serialized)
@MainActor
struct ClickThroughTests {

    @Test("the pet starts click-through before any cursor evaluation")
    func startsClickThrough() {
        let controller = PetWindowController()
        #expect(controller.window.ignoresMouseEvents)
        #expect(controller.mouseTracker.interactive == nil)
    }

    @Test("cursor over the pet body makes the window interactive")
    func cursorOnBodyEnablesInteraction() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        let bounds = controller.globalBounds
        let sprite = Constants.petSpriteFrameTopLeft()
        let centre = CGPoint(
            x: bounds.x + sprite.midX,
            y: bounds.y + sprite.midY
        )

        controller.mouseTracker.update(cursor: centre)
        #expect(controller.mouseTracker.interactive == true)
        #expect(!controller.window.ignoresMouseEvents)
    }

    @Test("cursor in the transparent margin restores click-through")
    func cursorInMarginRestoresClickThrough() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        let bounds = controller.globalBounds
        let sprite = Constants.petSpriteFrameTopLeft()
        let centre = CGPoint(
            x: bounds.x + sprite.midX,
            y: bounds.y + sprite.midY
        )
        let corner = CGPoint(x: bounds.x + 2, y: bounds.y + 2)

        controller.mouseTracker.update(cursor: centre)
        #expect(!controller.window.ignoresMouseEvents)

        controller.mouseTracker.update(cursor: corner)
        #expect(controller.mouseTracker.interactive == false)
        #expect(controller.window.ignoresMouseEvents)
    }

    @Test("cursor far from the pet is click-through")
    func cursorAwayIsClickThrough() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.mouseTracker.update(cursor: CGPoint(x: -5000, y: -5000))
        #expect(controller.window.ignoresMouseEvents)
    }

    @Test("a hidden pet is never interactive")
    func hiddenPetIsNotInteractive() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        let bounds = controller.globalBounds
        let sprite = Constants.petSpriteFrameTopLeft()
        let centre = CGPoint(
            x: bounds.x + sprite.midX,
            y: bounds.y + sprite.midY
        )
        controller.hide()

        #expect(!controller.mouseTracker.shouldBeInteractive(cursor: centre))
    }

    @Test("forceInteractive overrides cursor position during a drag")
    func forceInteractiveOverrides() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.mouseTracker.forceInteractive = true
        controller.mouseTracker.update(cursor: CGPoint(x: -5000, y: -5000))
        #expect(!controller.window.ignoresMouseEvents)

        controller.mouseTracker.forceInteractive = false
        controller.mouseTracker.update(cursor: CGPoint(x: -5000, y: -5000))
        #expect(controller.window.ignoresMouseEvents)
    }

    @Test("additional interactive rects extend the clickable area")
    func additionalRectsAreInteractive() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        // A bubble occupying the top-left corner, outside the pet hitbox.
        controller.mouseTracker.additionalInteractiveRects = {
            [CGRect(x: 0, y: 0, width: 40, height: 20)]
        }

        let bounds = controller.globalBounds
        let inBubble = CGPoint(x: bounds.x + 5, y: bounds.y + 5)
        #expect(controller.mouseTracker.shouldBeInteractive(cursor: inBubble))

        // Still outside everything.
        let elsewhere = CGPoint(x: bounds.x + 5, y: bounds.y + 100)
        #expect(!controller.mouseTracker.shouldBeInteractive(cursor: elsewhere))
    }

    @Test("hitTest rejects the transparent margin and accepts the body")
    func hitTestUsesHitbox() {
        let view = PetContentView(frame: CGRect(origin: .zero, size: Constants.petWindowSize))
        let sprite = view.petSpriteFrame
        #expect(view.hitTest(CGPoint(x: sprite.midX, y: sprite.midY)) === view)
        #expect(view.hitTest(CGPoint(x: 2, y: 2)) == nil)
        // Above the bottom-centred sprite (Electron left this band for bubbles).
        #expect(view.hitTest(CGPoint(x: sprite.midX, y: sprite.maxY + 20)) == nil)
        #expect(view.hitTest(CGPoint(x: 218, y: 338)) == nil)
    }

    @Test("the pet sprite sits in the Electron bottom 184×184 slot")
    func petSpriteMatchesElectronLayout() {
        let view = PetContentView(frame: CGRect(origin: .zero, size: Constants.petWindowSize))
        view.layoutSubtreeIfNeeded()
        #expect(view.petLayer.frame == CGRect(x: 18, y: 0, width: 184, height: 184))
    }
}
