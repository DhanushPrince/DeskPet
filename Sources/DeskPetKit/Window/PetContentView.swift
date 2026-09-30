import AppKit
import QuartzCore

/// Hosts the pet's animation layer and turns raw mouse events into pet
/// interactions.
///
/// Deliberately a plain `NSView` + `CALayer` rather than an `NSHostingView`:
/// the pet is a single animated bitmap with bespoke hit testing, and SwiftUI
/// adds a layout system this does not need.
public final class PetContentView: NSView {
    /// Sublayer holding the animation, so the facing flip can be applied to the
    /// pet without transforming any future sibling layers.
    public let petLayer = CALayer()
    public private(set) lazy var animator = PetAnimator(layer: petLayer)

    /// Sits above the pet. Hidden until a bubble is presented.
    public let bubbleView = SpeechBubbleView(frame: .zero)
    /// Bottom-centre countdown, shown only during a focus session.
    public let focusBadge = FocusBadgeView(frame: .zero)

    // MARK: Interaction callbacks

    /// A press and release with no meaningful travel.
    public var onClick: () -> Void = {}
    /// Travel exceeded the drag threshold. The offset is the press position in
    /// top-left window coordinates, matching `petDragStart`.
    public var onDragStart: (CGPoint) -> Void = { _ in }
    /// Drag finished or was cancelled.
    public var onDragEnd: () -> Void = {}
    public var onRightClick: (NSEvent) -> Void = { _ in }

    private struct DragTracking {
        let start: CGPoint
        var isDragging: Bool
    }
    private var drag: DragTracking?

    public var facing: PetFacing = .right {
        didSet {
            guard facing != oldValue else { return }
            applyFacing()
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // A layer-backed view in a borderless window otherwise fills with black,
        // which shows through the GIF's transparent pixels as a slab.
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        petLayer.isOpaque = false
        petLayer.backgroundColor = nil
        layer?.addSublayer(petLayer)
        layoutPetLayer()
        petLayer.contentsScale = window?.backingScaleFactor ?? 2
        applyFacing()

        bubbleView.isHidden = true
        addSubview(bubbleView)
        focusBadge.isHidden = true
        addSubview(focusBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var isOpaque: Bool { false }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }

    /// The pet's window never becomes key, so without this the first click
    /// would be swallowed as an activation click instead of reaching the pet.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Rejects points outside the bottom-centred sprite (and its hitbox), but
    /// always accepts the bubble.
    ///
    /// This does not by itself produce click-through — the window consumes the
    /// event either way, which is why `PetMouseTracker` drives
    /// `ignoresMouseEvents`. It closes the gap when the cursor moves faster than
    /// the tracker updates, so a click landing in the margin is never mistaken
    /// for a click on the pet.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's space; for a content view that is
        // the window's coordinate space, matching `bounds` here.
        if !bubbleView.isHidden, bubbleView.frame.contains(point) {
            return super.hitTest(point)
        }
        guard PetHitbox.contains(point, in: petSpriteFrame) else { return nil }
        return super.hitTest(point)
    }

    /// How far the sprite is lifted so a notch reminder bubble can sit under it.
    private var petLift: CGFloat = 0
    /// Height of the bubble currently placed under the pet. Zero otherwise.
    public private(set) var bubbleDrop: CGFloat = 0

    /// Cocoa frame of the drawn pet, matching Electron's 184×184 bottom slot.
    public var petSpriteFrame: CGRect {
        Constants.petSpriteFrame(inWindowSize: bounds.size).offsetBy(dx: 0, dy: petLift)
    }

    // MARK: - Speech bubble

    /// Shows a bubble above the pet, sized to its content.
    ///
    /// `belowPet` places it under the sprite instead, and lifts the sprite by
    /// the same amount. The window controller shifts the window down to match,
    /// so the dog stays put and the bubble hangs below the image.
    public func presentBubble(_ bubble: SpeechBubble, belowPet: Bool = false) {
        bubbleView.present(bubble)
        let panelHeight = SpeechBubbleView.height(for: bubble)
        // The view's bounds include the tail, which points at the pet.
        let totalHeight = panelHeight + BubbleStyle.tailHeight
        let x = ((bounds.width - BubbleStyle.width) / 2).rounded()
        if belowPet {
            bubbleView.tailPointsUp = true
            petLift = totalHeight
            bubbleDrop = totalHeight
            bubbleView.frame = CGRect(x: x, y: 0, width: BubbleStyle.width, height: totalHeight)
        } else {
            bubbleView.tailPointsUp = false
            petLift = 0
            bubbleDrop = 0
            // Cap so a tall prompt stays inside the window; bottomInset pins the
            // panel just above the sprite (Electron `bottom: 154px`).
            let minY = min(
                BubbleStyle.bottomInset - BubbleStyle.tailHeight,
                max(0, bounds.height - totalHeight)
            )
            bubbleView.frame = CGRect(x: x, y: minY, width: BubbleStyle.width, height: totalHeight)
        }
        layoutPetLayer()
        bubbleView.isHidden = false
        bubbleView.needsLayout = true
        bubbleView.needsDisplay = true
    }

    public func dismissBubble() {
        bubbleView.isHidden = true
        bubbleView.tailPointsUp = false
        petLift = 0
        bubbleDrop = 0
        layoutPetLayer()
    }

    public var isBubbleVisible: Bool { !bubbleView.isHidden }

    // MARK: - Focus badge

    /// Shows or refreshes the focus countdown.
    public func showFocusBadge(remainingSeconds: Int) {
        focusBadge.update(remainingSeconds: remainingSeconds, in: bounds)
        focusBadge.isHidden = false
    }

    public func hideFocusBadge() {
        focusBadge.isHidden = true
    }

    public var isFocusBadgeVisible: Bool { !focusBadge.isHidden }

    /// Regions beyond the pet's hitbox that should still receive clicks,
    /// expressed in top-left window coordinates for `PetMouseTracker`.
    public var additionalInteractiveRects: [CGRect] {
        var rects: [CGRect] = []
        if !bubbleView.isHidden {
            rects.append(topLeftRect(bubbleView.frame))
        }
        if !focusBadge.isHidden {
            rects.append(topLeftRect(focusBadge.frame))
        }
        return rects
    }

    private func topLeftRect(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX,
            y: bounds.height - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    /// Layers do not participate in autoresizing, so mirror bounds manually.
    public override func layout() {
        super.layout()
        layoutPetLayer()
    }

    private func layoutPetLayer() {
        petLayer.frame = petSpriteFrame
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        petLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    private func applyFacing() {
        // `facing-right` was the unmodified CSS transform; `facing-left` was
        // scaleX(-1). The default anchor point mirrors about the layer centre.
        petLayer.transform = facing == .left
            ? CATransform3DMakeScale(-1, 1, 1)
            : CATransform3DIdentity
    }

    // MARK: - Mouse events

    /// Press position in top-left window coordinates, matching the `clientX` /
    /// `clientY` values the Electron renderer sent.
    private func topLeftLocation(of event: NSEvent) -> CGPoint {
        let location = convert(event.locationInWindow, from: nil)
        return CGPoint(x: location.x, y: bounds.height - location.y)
    }

    public override func mouseDown(with event: NSEvent) {
        drag = DragTracking(start: topLeftLocation(of: event), isDragging: false)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard var tracking = drag, !tracking.isDragging else { return }
        let current = topLeftLocation(of: event)
        guard PetDragMath.exceedsDragThreshold(from: tracking.start, to: current) else { return }

        tracking.isDragging = true
        drag = tracking
        // The anchor is the original press point, not the current one, so the
        // pet does not jump when the drag begins.
        onDragStart(tracking.start)
    }

    public override func mouseUp(with event: NSEvent) {
        finishDrag(clicked: true)
    }

    /// Losing the window or the mouse mid-drag ends the drag without a click.
    public override func mouseExited(with event: NSEvent) {
        guard drag?.isDragging == true else { return }
        finishDrag(clicked: false)
    }

    public override func rightMouseDown(with event: NSEvent) {
        onRightClick(event)
    }

    private func finishDrag(clicked: Bool) {
        guard let tracking = drag else { return }
        drag = nil
        if tracking.isDragging {
            onDragEnd()
        } else if clicked {
            onClick()
        }
    }

    /// Ends any drag in progress, for use when the pet is hidden or the app
    /// loses focus.
    public func cancelDrag() {
        finishDrag(clicked: false)
    }

    public var isDragging: Bool { drag?.isDragging == true }
}
