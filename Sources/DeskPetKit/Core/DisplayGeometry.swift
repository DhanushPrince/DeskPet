import CoreGraphics
import Foundation

/// A rectangle in DeskPet's *global* coordinate space: origin at the top-left
/// of the primary display, y increasing downward.
///
/// This is Electron's `screen` convention, not Cocoa's. It is kept because the
/// positioning logic below is a direct port and its behavior is pinned by
/// ported tests; converting to Cocoa's bottom-left origin happens once, at the
/// `NSWindow` boundary, via `CoordinateSpace`.
public struct GlobalRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(origin: CGPoint, size: CGSize) {
        self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var size: CGSize { CGSize(width: width, height: height) }
}

public struct DisplayBounds: Equatable, Sendable {
    /// `CGDirectDisplayID`, widened to `Int` to match the persisted format.
    public let id: Int
    /// Area excluding the menu bar and Dock — Electron's `workArea`, Cocoa's
    /// `visibleFrame`.
    public let workArea: GlobalRect

    public init(id: Int, workArea: GlobalRect) {
        self.id = id
        self.workArea = workArea
    }
}

/// Persisted pet position. Absolute coordinates are kept for the case where the
/// saved display is gone; the relative pair restores position proportionally
/// after a resolution change.
public struct SavedWindowPosition: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var displayId: Int?
    public var relativeX: Double?
    public var relativeY: Double?

    public init(x: Double, y: Double, displayId: Int? = nil, relativeX: Double? = nil, relativeY: Double? = nil) {
        self.x = x
        self.y = y
        self.displayId = displayId
        self.relativeX = relativeX
        self.relativeY = relativeY
    }
}

/// Direct port of `src/main/displayPosition.ts`.
public enum DisplayGeometry {
    /// JavaScript's `Math.round` semantics (half rounds toward +∞), which
    /// differs from Swift's `rounded()` for negative halves. Coordinates can be
    /// negative when a display sits left of or above the primary one.
    static func jsRound(_ value: Double) -> Double {
        (value + 0.5).rounded(.down)
    }

    static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        // Preserves the original guard: a window wider than the work area
        // pins to the work area origin rather than inverting.
        if maximum < minimum { return minimum }
        return Swift.min(Swift.max(value, minimum), maximum)
    }

    static func center(of bounds: GlobalRect) -> CGPoint {
        CGPoint(
            x: bounds.x + jsRound(bounds.width / 2),
            y: bounds.y + jsRound(bounds.height / 2)
        )
    }

    static func contains(_ workArea: GlobalRect, _ point: CGPoint) -> Bool {
        point.x >= workArea.x && point.x <= workArea.maxX
            && point.y >= workArea.y && point.y <= workArea.maxY
    }

    private static func axisDistance(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        if value < minimum { return minimum - value }
        if value > maximum { return value - maximum }
        return 0
    }

    static func distance(from workArea: GlobalRect, to point: CGPoint) -> Double {
        let dx = axisDistance(point.x, workArea.x, workArea.maxX)
        let dy = axisDistance(point.y, workArea.y, workArea.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The display containing the window's centre, else the nearest one, else
    /// the supplied fallback.
    public static func displayForBounds(
        displays: [DisplayBounds],
        bounds: GlobalRect,
        fallback: DisplayBounds
    ) -> DisplayBounds {
        let point = center(of: bounds)
        if let containing = displays.first(where: { contains($0.workArea, point) }) {
            return containing
        }
        // `min(by:)` is stable for equal distances in the same way the original
        // sort was: the earliest display wins.
        guard let nearest = displays.min(by: {
            distance(from: $0.workArea, to: point) < distance(from: $1.workArea, to: point)
        }) else {
            return fallback
        }
        return nearest
    }

    public static func clampToWorkArea(_ bounds: GlobalRect, _ workArea: GlobalRect) -> GlobalRect {
        var result = bounds
        result.x = clamp(bounds.x, workArea.x, workArea.maxX - bounds.width)
        result.y = clamp(bounds.y, workArea.y, workArea.maxY - bounds.height)
        return result
    }

    public static func savedPosition(
        displays: [DisplayBounds],
        bounds: GlobalRect,
        fallback: DisplayBounds
    ) -> SavedWindowPosition {
        let display = displayForBounds(displays: displays, bounds: bounds, fallback: fallback)
        let maxX = Swift.max(1, display.workArea.width - bounds.width)
        let maxY = Swift.max(1, display.workArea.height - bounds.height)

        return SavedWindowPosition(
            x: bounds.x,
            y: bounds.y,
            displayId: display.id,
            relativeX: clamp((bounds.x - display.workArea.x) / maxX, 0, 1),
            relativeY: clamp((bounds.y - display.workArea.y) / maxY, 0, 1)
        )
    }

    /// Where the pet window should open. With no saved position it sits
    /// bottom-centre of the primary display.
    public static func initialBounds(
        displays: [DisplayBounds],
        primaryDisplay: DisplayBounds,
        size: CGSize,
        saved: SavedWindowPosition?
    ) -> GlobalRect {
        let work = primaryDisplay.workArea
        let fallback = GlobalRect(
            x: jsRound(work.x + work.width / 2 - size.width / 2),
            y: work.y + work.height - size.height,
            width: size.width,
            height: size.height
        )

        guard let saved else { return fallback }

        let savedDisplay = saved.displayId.flatMap { id in
            displays.first { $0.id == id }
        }
        var probe = fallback
        probe.x = saved.x
        probe.y = saved.y
        let targetDisplay = savedDisplay
            ?? displayForBounds(displays: displays, bounds: probe, fallback: primaryDisplay)

        let hasRelative = (saved.relativeX?.isFinite ?? false) && (saved.relativeY?.isFinite ?? false)

        var restored = fallback
        if savedDisplay != nil, hasRelative {
            // Proportional restore: survives a resolution change on the same
            // display.
            let area = targetDisplay.workArea
            restored.x = jsRound(
                area.x + clamp(saved.relativeX ?? 0, 0, 1) * Swift.max(0, area.width - size.width)
            )
            restored.y = jsRound(
                area.y + clamp(saved.relativeY ?? 0, 0, 1) * Swift.max(0, area.height - size.height)
            )
        } else {
            restored.x = saved.x
            restored.y = saved.y
        }

        return clampToWorkArea(restored, targetDisplay.workArea)
    }

    /// Pulls a window back inside whichever display it is nearest to.
    public static func visibleBounds(
        displays: [DisplayBounds],
        primaryDisplay: DisplayBounds,
        bounds: GlobalRect
    ) -> GlobalRect {
        let target = displayForBounds(displays: displays, bounds: bounds, fallback: primaryDisplay)
        return clampToWorkArea(bounds, target.workArea)
    }
}

/// Conversion between DeskPet's top-left global space and Cocoa's bottom-left
/// space. Pure so the round trip can be tested without a display.
public enum CoordinateSpace {
    /// - Parameter primaryFrameHeight: full `frame` height of the primary
    ///   display (not `visibleFrame`); the primary display's Cocoa frame origin
    ///   is by definition `(0, 0)`.
    public static func globalRect(fromCocoa rect: CGRect, primaryFrameHeight: Double) -> GlobalRect {
        GlobalRect(
            x: rect.minX,
            y: primaryFrameHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public static func cocoaRect(fromGlobal rect: GlobalRect, primaryFrameHeight: Double) -> CGRect {
        CGRect(
            x: rect.x,
            y: primaryFrameHeight - rect.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    public static func globalPoint(fromCocoa point: CGPoint, primaryFrameHeight: Double) -> CGPoint {
        CGPoint(x: point.x, y: primaryFrameHeight - point.y)
    }

    public static func cocoaPoint(fromGlobal point: CGPoint, primaryFrameHeight: Double) -> CGPoint {
        CGPoint(x: point.x, y: primaryFrameHeight - point.y)
    }
}
