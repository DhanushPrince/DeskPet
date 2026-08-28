import AppKit
import SwiftUI

/// Hosts `SettingsView` in a real window.
///
/// An `NSWindow` with an `NSHostingView` rather than a SwiftUI `Window` scene:
/// the app runs an AppKit lifecycle (`NSApplication.run` with a delegate) so that
/// the pet window can be a bespoke `NSWindow`, and scene-based windows are only
/// available inside a SwiftUI `App`.
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let state: AppState

    public init(state: AppState) {
        self.state = state
        super.init()
    }

    /// Shows the window, creating it on first use and focusing it afterwards.
    ///
    /// Ported from `createSettingsWindow`, which focused an existing window
    /// rather than opening a second one.
    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Constants.settingsWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "\(Constants.appName) \(Strings.SettingsLabels.title)"
        window.isReleasedWhenClosed = false
        window.delegate = self

        // Default `sizingOptions` include `.intrinsicContentSize`, so the
        // hosting view grows to the unrolled form and the window clips it.
        // Reminders / Focus then sit below the fold with no scrollbar.
        let hosting = NSHostingView(rootView: SettingsView(state: state))
        hosting.sizingOptions = .minSize
        window.contentView = hosting
        window.backgroundColor = NSColor(
            srgbRed: 250 / 255, green: 246 / 255, blue: 238 / 255, alpha: 1
        )
        // The palette is a fixed cream, transcribed from the Electron window's
        // CSS. Without pinning the appearance, Dark Mode gives SwiftUI's controls
        // light labels, which are invisible on it — button titles disappeared
        // entirely before this was set.
        window.appearance = NSAppearance(named: .aqua)
        // `titleBarStyle: "hiddenInset"` in the Electron build.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Width was fixed in the original; only the height resizes.
        window.minSize = CGSize(
            width: Constants.settingsWindowSize.width,
            height: Constants.settingsWindowMinHeight
        )
        window.maxSize = CGSize(
            width: Constants.settingsWindowSize.width,
            height: .greatestFiniteMagnitude
        )

        window.center()
        window.makeKeyAndOrderFront(nil)
        // An accessory app has to activate explicitly to take focus.
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    public func close() {
        window?.close()
    }

    public var isVisible: Bool { window?.isVisible ?? false }
    /// Exposed for tests.
    public var currentWindow: NSWindow? { window }

    public func windowWillClose(_ notification: Notification) {
        // Keep the instance so reopening restores the same window; the pet and
        // menu bar keep the process alive.
    }
}
