import AppKit
import Foundation

/// Keeps `window.ignoresMouseEvents` in sync with whether the cursor is over
/// the pet.
///
/// ## Why not `hitTest` alone
///
/// Returning `nil` from the content view's `hitTest(_:)` stops *the view* from
/// receiving an event, but the window still consumes it, so the click never
/// reaches the application underneath. Real click-through on macOS needs
/// `ignoresMouseEvents`, which is a window-level flag and therefore has to be
/// decided before the event is dispatched — hence tracking the cursor.
///
/// This mirrors the Electron implementation, which toggled
/// `setIgnoreMouseEvents` from the renderer's `mousemove` handler over the same
/// hitbox. `PetContentView.hitTest` still applies the hitbox as a second check,
/// covering the window between a fast cursor movement and the next event.
///
/// Global monitors fire for *every* mouse move on the machine. Without a
/// proximity early-out and a throttle, that work on the main thread makes the
/// whole UI feel laggy while DeskPet is running.
public final class PetMouseTracker {
    /// Extra regions that should also be treated as interactive — the speech
    /// bubble registers itself here in Task 12.
    public var additionalInteractiveRects: () -> [CGRect] = { [] }

    /// Forces interactivity on regardless of cursor position, used while a drag
    /// is in progress so the pet keeps receiving events.
    public var forceInteractive = false {
        didSet { updateImmediately() }
    }

    private weak var window: NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Mirrors `petMouseInteractive` in main.ts: only touch the window when the
    /// value actually changes.
    private var isInteractive: Bool?
    private var lastPollAt: CFAbsoluteTime = 0
    /// Cap global-monitor work; 30 Hz is enough to catch the hitbox edge.
    private static let minPollInterval: CFTimeInterval = 1.0 / 30.0
    /// Cocoa padding around the window before we bother with sprite math.
    private static let proximityPadding: CGFloat = 48

    public init(window: NSWindow) {
        self.window = window
    }

    deinit {
        stop()
    }

    public func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        // Global: fires while the pet is click-through and events go to other
        // apps. Mouse-position monitoring needs no special permission.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.pollFromMonitor()
        }
        // Local: fires once the pet itself is interactive and receiving events.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.pollFromMonitor()
            return event
        }
        // Establish the initial state rather than waiting for the first move.
        updateImmediately()
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// Recomputes interactivity from the live cursor position (throttled).
    public func update() {
        pollFromMonitor()
    }

    /// Unthrottled recompute — bubble show/hide, tests, drag start/end.
    public func updateImmediately() {
        lastPollAt = 0
        update(cursor: ScreenBridge.cursorLocation)
    }

    /// Decision entry point taking an explicit cursor position, in DeskPet's
    /// global top-left space. Exposed so tests can drive it directly.
    public func update(cursor: CGPoint) {
        setInteractive(shouldBeInteractive(cursor: cursor))
    }

    public func shouldBeInteractive(cursor: CGPoint) -> Bool {
        if forceInteractive { return true }
        guard let window, window.isVisible else { return false }

        let bounds = ScreenBridge.globalRect(from: window.frame)
        let local = CGPoint(x: cursor.x - bounds.x, y: cursor.y - bounds.y)
        // Hit-test against the bottom-centred sprite, not the full transparent
        // window — matching Electron's `.pet-button` rect.
        let sprite = Constants.petSpriteFrameTopLeft(inWindowSize: bounds.size)

        if PetHitbox.contains(local, in: sprite) { return true }
        return additionalInteractiveRects().contains { $0.contains(local) }
    }

    private func pollFromMonitor() {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastPollAt < Self.minPollInterval { return }
        lastPollAt = now

        if forceInteractive {
            setInteractive(true)
            return
        }
        guard let window, window.isVisible else {
            setInteractive(false)
            return
        }

        // Cheap Cocoa-space reject: most mouse moves are nowhere near the pet.
        let cocoaCursor = NSEvent.mouseLocation
        let padded = window.frame.insetBy(
            dx: -Self.proximityPadding,
            dy: -Self.proximityPadding
        )
        if !padded.contains(cocoaCursor) {
            setInteractive(false)
            return
        }

        update(cursor: ScreenBridge.cursorLocation)
    }

    private func setInteractive(_ interactive: Bool) {
        guard isInteractive != interactive else { return }
        isInteractive = interactive
        window?.ignoresMouseEvents = !interactive
    }

    /// Current state, or nil before the first evaluation.
    public var interactive: Bool? { isInteractive }
}
