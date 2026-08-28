import AppKit
import Foundation

/// The only place that knows about `NSScreen`. Everything above it works in
/// DeskPet's top-left global space.
public enum ScreenBridge {
    /// Brief cache so drag / break-run ticks (≈60 Hz) do not re-enumerate
    /// `NSScreen.screens` on every frame.
    private static var displayCache: (height: Double, displays: [DisplayBounds], at: CFAbsoluteTime)?
    private static let displayCacheTTL: CFTimeInterval = 0.25

    public static func invalidateDisplayCache() {
        displayCache = nil
    }

    /// The primary display is the one whose Cocoa frame origin is `(0, 0)`.
    ///
    /// Deliberately not `NSScreen.main`, which returns the screen holding the
    /// key window and therefore changes as focus moves.
    public static var primaryScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }

    /// Height of the primary display's full frame — the pivot for every
    /// top-left ↔ bottom-left conversion.
    public static var primaryFrameHeight: Double {
        Double(primaryScreen?.frame.height ?? 0)
    }

    public static func displayID(of screen: NSScreen) -> Int {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return 0 }
        return number.intValue
    }

    public static func displayBounds(for screen: NSScreen, primaryFrameHeight: Double) -> DisplayBounds {
        DisplayBounds(
            id: displayID(of: screen),
            workArea: CoordinateSpace.globalRect(
                fromCocoa: screen.visibleFrame,
                primaryFrameHeight: primaryFrameHeight
            )
        )
    }

    public static var displays: [DisplayBounds] {
        let height = primaryFrameHeight
        let now = CFAbsoluteTimeGetCurrent()
        if let displayCache,
           now - displayCache.at < displayCacheTTL,
           displayCache.height == height {
            return displayCache.displays
        }
        let screens = NSScreen.screens.map { displayBounds(for: $0, primaryFrameHeight: height) }
        displayCache = (height, screens, now)
        return screens
    }

    public static var primaryDisplay: DisplayBounds {
        let height = primaryFrameHeight
        guard let screen = primaryScreen else {
            // No displays attached: hand back a plausible unit rect so callers
            // still have a fallback to clamp against.
            return DisplayBounds(id: 0, workArea: GlobalRect(x: 0, y: 0, width: 1440, height: 900))
        }
        return displayBounds(for: screen, primaryFrameHeight: height)
    }

    /// Cursor position in global top-left coordinates.
    public static var cursorLocation: CGPoint {
        CoordinateSpace.globalPoint(
            fromCocoa: NSEvent.mouseLocation,
            primaryFrameHeight: primaryFrameHeight
        )
    }

    public static func cocoaRect(from rect: GlobalRect) -> CGRect {
        CoordinateSpace.cocoaRect(fromGlobal: rect, primaryFrameHeight: primaryFrameHeight)
    }

    public static func globalRect(from rect: CGRect) -> GlobalRect {
        CoordinateSpace.globalRect(fromCocoa: rect, primaryFrameHeight: primaryFrameHeight)
    }
}
