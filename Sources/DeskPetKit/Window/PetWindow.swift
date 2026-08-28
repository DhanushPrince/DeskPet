import AppKit

/// The pet's window: borderless, fully transparent, above normal windows, and
/// present on every Space.
///
/// Replaces the Electron `BrowserWindow` created in `createPetWindow()`.
public final class PetWindow: NSWindow {
    public init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // `.floating` sits above normal windows but below system UI such as the
        // menu bar, matching Electron's alwaysOnTop "floating" level.
        level = .floating
        // canJoinAllSpaces keeps the pet present when switching Spaces;
        // fullScreenAuxiliary lets it show over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Dragging is driven explicitly from mouse events so the window can be
        // clamped to the work area on every step.
        isMovableByWindowBackground = false
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // Excluded from window cycling and from Mission Control's window list.
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    /// The pet must never take keyboard focus away from the user's work.
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Borderless windows have no close box, so AppKit's `performClose:` is a
    /// no-op. `NSApp.terminate` then aborts because this window is still open.
    public override func performClose(_ sender: Any?) {
        close()
    }
}
