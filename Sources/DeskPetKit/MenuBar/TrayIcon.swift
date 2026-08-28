import AppKit

/// The menu bar icon, drawn in code rather than shipped as an asset.
///
/// Ported from `src/main/trayIcon.ts`, which composed the paw from five filled
/// circles in a 22×22 RGBA buffer. As a template image macOS recolours it for
/// light and dark menu bars automatically, so the explicit `nativeTheme`
/// re-render the Electron build needed on Windows has no equivalent here.
public enum TrayIcon {
    static let size: CGFloat = 22

    /// Circle centres and radii from the original buffer, in its top-left-origin
    /// coordinates: four toes and the pad.
    static let circles: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [
        (5, 4, 2.4),
        (11, 2.5, 2.4),
        (17, 4, 2.4),
        (3, 9, 2.4),
        (11, 15, 7)
    ]

    public static func make() -> NSImage {
        let image = NSImage(
            size: CGSize(width: size, height: size),
            flipped: false
        ) { _ in
            NSColor.black.setFill()
            for circle in circles {
                // The source coordinates are y-down; Cocoa draws y-up.
                let rect = CGRect(
                    x: circle.x - circle.radius,
                    y: size - circle.y - circle.radius,
                    width: circle.radius * 2,
                    height: circle.radius * 2
                )
                NSBezierPath(ovalIn: rect).fill()
            }
            return true
        }
        // Template images are tinted by the system to match the menu bar.
        image.isTemplate = true
        return image
    }
}
