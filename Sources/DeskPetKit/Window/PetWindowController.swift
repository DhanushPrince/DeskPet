import AppKit
import Foundation

/// Owns the pet window: creation, placement, and rendering the current state.
public final class PetWindowController {
    public let window: PetWindow
    public let contentView: PetContentView

    /// Appearance currently rendered. Task 10 drives this from AppState.
    public var appearance: PetAppearanceID = .lineDog {
        didSet { renderCurrentState(forceVariant: true) }
    }
    public var customAppearance: CustomPetAppearance? {
        didSet { renderCurrentState(forceVariant: true) }
    }

    public private(set) var state: PetState = .idle
    private var variant = 0
    /// Rotates variants for long-lived states such as idle.
    private var rotationTimer: Timer?
    /// Decides when the pet is clickable versus click-through.
    public let mouseTracker: PetMouseTracker

    // MARK: Interaction hooks

    /// A click on the pet's body. Task 13 wires this to the happy reaction.
    public var onPetClicked: () -> Void = {}
    /// A bubble button was tapped, identified by its action id.
    public var onBubbleAction: (String) -> Void = { _ in }
    /// Right-click on the pet. Task 10 replaces the placeholder menu.
    public var onContextMenu: ((NSEvent) -> Void)?
    /// Fires when a drag finishes, with the position to persist.
    public var onPositionChanged: ((SavedWindowPosition) -> Void)?
    /// Blocks dragging while true. Set during the break run, which owns the
    /// pet's position (`blockingMode === "breakRun"` in the Electron build).
    public var isDragBlocked: () -> Bool = { false }

    // MARK: Drag state

    private var dragOffset: CGPoint = .zero
    private var dragTimer: Timer?
    private var dragSafetyTimer: Timer?
    private var bubbleTimer: Timer?

    public init(savedPosition: SavedWindowPosition? = nil) {
        let displays = ScreenBridge.displays
        let primary = ScreenBridge.primaryDisplay
        let globalBounds = DisplayGeometry.initialBounds(
            displays: displays,
            primaryDisplay: primary,
            size: Constants.petWindowSize,
            saved: savedPosition
        )

        window = PetWindow(contentRect: ScreenBridge.cocoaRect(from: globalBounds))
        contentView = PetContentView(frame: CGRect(origin: .zero, size: Constants.petWindowSize))
        window.contentView = contentView
        mouseTracker = PetMouseTracker(window: window)

        contentView.onClick = { [weak self] in self?.onPetClicked() }
        contentView.onDragStart = { [weak self] offset in self?.startDrag(offset: offset) }
        contentView.onDragEnd = { [weak self] in self?.stopDrag() }
        contentView.onRightClick = { [weak self] event in self?.handleRightClick(event) }
        contentView.bubbleView.onAction = { [weak self] id in self?.onBubbleAction(id) }

        // Keep the bubble clickable even where it extends past the pet's hitbox.
        mouseTracker.additionalInteractiveRects = { [weak self] in
            self?.contentView.additionalInteractiveRects ?? []
        }
    }

    deinit {
        rotationTimer?.invalidate()
        dragTimer?.invalidate()
        dragSafetyTimer?.invalidate()
        bubbleTimer?.invalidate()
        mouseTracker.stop()
    }

    /// Shows the pet without taking focus from the frontmost app — the
    /// equivalent of Electron's `showInactive()`.
    public func show() {
        window.orderFrontRegardless()
        renderCurrentState(forceVariant: true)
        mouseTracker.start()
        let bounds = globalBounds
        NSLog(String(
            format: "DeskPet: pet window at global %.0f,%.0f %.0fx%.0f (visible: %@)",
            bounds.x, bounds.y, bounds.width, bounds.height,
            window.isVisible ? "yes" : "no"
        ))
    }

    public func hide() {
        stopDrag()
        hideBubble()
        window.orderOut(nil)
        mouseTracker.stop()
        rotationTimer?.invalidate()
        rotationTimer = nil
    }

    public var isVisible: Bool { window.isVisible }

    public var facing: PetFacing {
        get { contentView.facing }
        set { contentView.facing = newValue }
    }

    /// Current window position in DeskPet's global (top-left) space.
    public var globalBounds: GlobalRect {
        ScreenBridge.globalRect(from: window.frame)
    }

    public func setGlobalBounds(_ rect: GlobalRect) {
        let cocoa = ScreenBridge.cocoaRect(from: rect)
        // `display: true` forces a full redraw every call; drag and break-run
        // move the window at ~60 Hz, so only relocate unless the size changed.
        if cocoa.size == window.frame.size {
            window.setFrameOrigin(cocoa.origin)
        } else {
            window.setFrame(cocoa, display: false)
        }
    }

    // MARK: State rendering

    public func setState(_ next: PetState) {
        // A repeated state assignment re-rolls the variant, matching the
        // renderer's `stateSignal` effect.
        state = next
        renderCurrentState(forceVariant: true)
    }

    private func renderCurrentState(forceVariant: Bool) {
        let definition = PetAppearances.assetDefinition(
            appearance: appearance,
            state: state,
            custom: customAppearance
        )
        if forceVariant {
            variant = PetVariantSelector.variant(count: definition.paths.count)
        }

        if !contentView.animator.play(definition: definition, variant: variant) {
            // Asset missing or undecodable: fall back to the appearance's own
            // fallback animation rather than showing an empty window.
            let fallback = PetAppearances.manifest(appearance.builtIn).fallback
            contentView.animator.play(definition: fallback)
        }

        scheduleVariantRotation(variantCount: definition.paths.count)
    }

    private func scheduleVariantRotation(variantCount: Int) {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard PetVariantSelector.rotates(state, variantCount: variantCount) else { return }

        let timer = Timer(
            timeInterval: Constants.continuousAssetRotation,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            self.variant = PetVariantSelector.variant(count: variantCount, previous: self.variant)
            self.renderCurrentState(forceVariant: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        rotationTimer = timer
    }

    // MARK: - Dragging

    public var isDragging: Bool { dragTimer != nil }

    /// Begins a drag anchored at `offset` (top-left window coordinates).
    public func startDrag(offset: CGPoint) {
        guard !isDragBlocked() else { return }

        dragOffset = PetDragMath.clampOffset(offset, in: Constants.petWindowSize)
        stopDragTimers()
        // Keep the window interactive for the whole drag, even when the cursor
        // runs outside the pet's hitbox.
        mouseTracker.forceInteractive = true

        moveWithCursor()
        let timer = Timer(timeInterval: Constants.breakRunTick, repeats: true) { [weak self] _ in
            self?.moveWithCursor()
        }
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer

        // Safety net: if the mouse-up is never delivered (the window losing the
        // event, a Space switch mid-drag), the pet would otherwise follow the
        // cursor forever.
        let safety = Timer(
            timeInterval: Constants.dragSafetyTimeout,
            repeats: false
        ) { [weak self] _ in
            NSLog("DeskPet: drag safety timeout reached, ending drag")
            self?.stopDrag()
        }
        RunLoop.main.add(safety, forMode: .common)
        dragSafetyTimer = safety
    }

    public func stopDrag() {
        let wasDragging = dragTimer != nil || dragSafetyTimer != nil
        stopDragTimers()
        mouseTracker.forceInteractive = false
        guard wasDragging else { return }

        contentView.cancelDrag()
        persistPosition()
    }

    private func stopDragTimers() {
        dragTimer?.invalidate()
        dragTimer = nil
        dragSafetyTimer?.invalidate()
        dragSafetyTimer = nil
    }

    /// One drag step: put the anchor under the cursor, clamped to the work area
    /// of whichever display the pet is nearest.
    private func moveWithCursor() {
        let previousX = globalBounds.x
        let target = PetDragMath.targetBounds(
            cursor: ScreenBridge.cursorLocation,
            offset: dragOffset,
            size: Constants.petWindowSize
        )
        let clamped = DisplayGeometry.visibleBounds(
            displays: ScreenBridge.displays,
            primaryDisplay: ScreenBridge.primaryDisplay,
            bounds: target
        )
        setGlobalBounds(clamped)
        facing = PetDragMath.facing(fromDeltaX: clamped.x - previousX, current: facing)
    }

    /// Pulls the pet back into a visible work area, for display changes.
    public func clampIntoVisibleArea() {
        let current = globalBounds
        let clamped = DisplayGeometry.visibleBounds(
            displays: ScreenBridge.displays,
            primaryDisplay: ScreenBridge.primaryDisplay,
            bounds: current
        )
        if clamped != current {
            setGlobalBounds(clamped)
        }
        persistPosition()
    }

    private func persistPosition() {
        let saved = DisplayGeometry.savedPosition(
            displays: ScreenBridge.displays,
            bounds: globalBounds,
            fallback: ScreenBridge.primaryDisplay
        )
        onPositionChanged?(saved)
    }

    // MARK: - Speech bubble

    /// Shows a bubble, replacing any current one and restarting the auto-dismiss
    /// timer. Ported from `showBubble`.
    public func showBubble(_ bubble: SpeechBubble) {
        bubbleTimer?.invalidate()
        bubbleTimer = nil

        contentView.presentBubble(bubble)
        // The bubble extends past the pet's hitbox, so re-evaluate immediately
        // rather than waiting for the next mouse move.
        mouseTracker.updateImmediately()

        guard let dismissAfter = bubble.autoDismissAfter, dismissAfter > 0 else { return }
        let timer = Timer(timeInterval: dismissAfter, repeats: false) { [weak self] _ in
            self?.hideBubble()
        }
        RunLoop.main.add(timer, forMode: .common)
        bubbleTimer = timer
    }

    /// Ported from `hideBubble`.
    public func hideBubble() {
        bubbleTimer?.invalidate()
        bubbleTimer = nil
        contentView.dismissBubble()
        mouseTracker.updateImmediately()
    }

    public var isBubbleVisible: Bool { contentView.isBubbleVisible }
    public var currentBubble: SpeechBubble? { contentView.bubbleView.bubble }

    // MARK: - Focus badge

    public func showFocusBadge(remainingSeconds: Int) {
        contentView.showFocusBadge(remainingSeconds: remainingSeconds)
        mouseTracker.updateImmediately()
    }

    public func hideFocusBadge() {
        contentView.hideFocusBadge()
        mouseTracker.updateImmediately()
    }

    public var isFocusBadgeVisible: Bool { contentView.isFocusBadgeVisible }

    // MARK: - Context menu

    private func handleRightClick(_ event: NSEvent) {
        if let onContextMenu {
            onContextMenu(event)
            return
        }
        // Placeholder until Task 10 supplies the real menu.
        let menu = NSMenu()
        menu.addItem(withTitle: "DeskPet", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit DeskPet",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }
}
