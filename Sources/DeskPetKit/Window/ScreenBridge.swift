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

    // MARK: - Notch

    /// The built-in display reporting a non-zero top safe-area inset — the
    /// supported (macOS 12+) way to detect a camera-housing notch. `nil` on
    /// Macs without one and on external-monitor-only setups.
    public static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// Geometry describing the notch on `notchScreen`, in Cocoa (bottom-left)
    /// coordinates, kept together so callers do not re-derive it piecemeal.
    struct NotchGeometry {
        /// Full width of the notch cutout itself (the camera housing), derived
        /// from the gap between the two auxiliary menu-bar areas.
        var notchWidth: Double
        /// Horizontal centre of the notch, in the screen's local Cocoa space.
        var centerX: Double
        /// Top edge of the screen, in the screen's local Cocoa space.
        var screenMaxY: Double
        /// Height of the safe-area inset — how far the notch extends down from
        /// the top edge (i.e. the menu-bar band height on a notched Mac).
        var insetTop: Double
    }

    /// Pulls the geometry AppKit already computes for the notch: the two
    /// menu-bar areas flanking the camera housing bound the notch itself, and
    /// `safeAreaInsets.top` gives its height.
    static func notchGeometry(for screen: NSScreen) -> NotchGeometry? {
        guard screen.safeAreaInsets.top > 0 else { return nil }
        let frame = screen.frame
        // With no camera housing these areas are empty rects; on a notched Mac
        // they span from the screen's side edges to the notch's left/right edge.
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let notchMinX = left?.maxX ?? frame.midX
        let notchMaxX = right?.minX ?? frame.midX
        let width = max(0, notchMaxX - notchMinX)
        return NotchGeometry(
            notchWidth: width,
            centerX: (notchMinX + notchMaxX) / 2,
            screenMaxY: frame.maxY,
            insetTop: Double(screen.safeAreaInsets.top)
        )
    }

    /// Where the pet should hang in Notch Mode: centred under the notch,
    /// gripping its bottom edge, in DeskPet's global (top-left) coordinate
    /// space. `nil` when there is no notch to hang from.
    public static func notchHangRect(size: CGSize) -> GlobalRect? {
        guard let screen = notchScreen, let geometry = notchGeometry(for: screen) else {
            return nil
        }
        // The notch's own rect in Cocoa space: full inset height, centred
        // horizontally, spanning its own width — DisplayGeometry.notchHangBounds
        // does the actual centring/rounding so there is exactly one
        // implementation of that math (shared with the drag/clamp call sites).
        let notchCocoaRect = CGRect(
            x: geometry.centerX - geometry.notchWidth / 2,
            y: geometry.screenMaxY - geometry.insetTop,
            width: geometry.notchWidth,
            height: geometry.insetTop
        )
        let notchGlobalRect = globalRect(from: notchCocoaRect)
        return DisplayGeometry.notchHangBounds(
            petSize: size,
            notchRect: notchGlobalRect,
            spriteTopInset: Double(Constants.notchSpriteTopInset)
        )
    }

    /// Parked above the screen, so the pet is fully hidden until a reminder
    /// slides it down to `notchHangRect`.
    public static func notchRestRect(size: CGSize) -> GlobalRect? {
        guard var shown = notchHangRect(size: size) else { return nil }
        let spriteTop = shown.y + Double(Constants.notchSpriteTopInset)
        // Extra points keep the outline from sitting on the top edge of the screen.
        shown.y -= spriteTop + Double(Constants.petSpriteSize.height) + 4
        return shown
    }
}
