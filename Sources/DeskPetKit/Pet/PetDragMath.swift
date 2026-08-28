import CoreGraphics
import Foundation

/// Pure geometry behind pet dragging, split out from the AppKit event handling
/// so each rule can be tested directly.
///
/// Ported from `startPetDrag` / `movePetWithCursor` in `main.ts` and the pointer
/// handlers in `PetView.tsx`.
public enum PetDragMath {
    /// Where in the window the press landed, clamped to the window.
    ///
    /// The Electron build rounded and clamped to `[0, width]` / `[0, height]`
    /// (inclusive of the far edge) before using the value as a drag anchor.
    /// Expressed in top-left window coordinates.
    public static func clampOffset(_ offset: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: DisplayGeometry.clamp(DisplayGeometry.jsRound(offset.x), 0, size.width),
            y: DisplayGeometry.clamp(DisplayGeometry.jsRound(offset.y), 0, size.height)
        )
    }

    /// Whether the pointer has travelled far enough for this to be a drag
    /// rather than a click. `DRAG_START_DISTANCE_PX` is 10 and the comparison is
    /// strictly greater-than.
    public static func exceedsDragThreshold(
        from start: CGPoint,
        to current: CGPoint,
        threshold: Double = Constants.dragThreshold
    ) -> Bool {
        let dx = current.x - start.x
        let dy = current.y - start.y
        return (dx * dx + dy * dy).squareRoot() > threshold
    }

    /// Window rect that puts the drag anchor under the cursor, before clamping.
    /// Both `cursor` and the result are in the global top-left space.
    public static func targetBounds(
        cursor: CGPoint,
        offset: CGPoint,
        size: CGSize
    ) -> GlobalRect {
        GlobalRect(
            x: cursor.x - offset.x,
            y: cursor.y - offset.y,
            width: size.width,
            height: size.height
        )
    }

    /// Facing implied by horizontal travel. Zero movement leaves facing alone,
    /// so a purely vertical drag does not flip the pet.
    ///
    /// Note: the Electron build only ever set facing during the break run, not
    /// while dragging. Applying it to drags as well is a deliberate addition.
    public static func facing(fromDeltaX delta: Double, current: PetFacing) -> PetFacing {
        if delta > 0 { return .right }
        if delta < 0 { return .left }
        return current
    }
}
