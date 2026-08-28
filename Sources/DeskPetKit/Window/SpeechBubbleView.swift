import AppKit

/// Geometry and colours transcribed from `.speech-bubble` and `.bubble-button`
/// in `src/renderer/src/styles.css`.
enum BubbleStyle {
    static let width: CGFloat = 210          // min-width: 210px
    static let cornerRadius: CGFloat = 16
    static let padding: CGFloat = 12
    /// Distance from the bottom of the pet window to the bubble's bottom edge.
    static let bottomInset: CGFloat = 154
    /// The downward tail: 9px each side, 10px tall.
    static let tailHalfWidth: CGFloat = 9
    static let tailHeight: CGFloat = 10

    static let messageFontSize: CGFloat = 13
    static let messageLineHeightMultiple: CGFloat = 1.35
    static let actionsTopMargin: CGFloat = 10
    static let actionSpacing: CGFloat = 6
    static let buttonHeight: CGFloat = 28
    static let buttonFontSize: CGFloat = 12
    static let buttonHorizontalPadding: CGFloat = 10

    static let background = NSColor(srgbRed: 255 / 255, green: 252 / 255, blue: 244 / 255, alpha: 0.96)
    static let border = NSColor(srgbRed: 76 / 255, green: 57 / 255, blue: 39 / 255, alpha: 0.14)
    static let messageColour = NSColor(srgbRed: 59 / 255, green: 48 / 255, blue: 37 / 255, alpha: 1)

    static let secondaryFill = NSColor(srgbRed: 243 / 255, green: 238 / 255, blue: 229 / 255, alpha: 1)
    static let secondaryBorder = NSColor(srgbRed: 45 / 255, green: 38 / 255, blue: 31 / 255, alpha: 0.12)
    static let primaryFill = NSColor(srgbRed: 36 / 255, green: 78 / 255, blue: 69 / 255, alpha: 1)
    static let primaryText = NSColor(srgbRed: 255 / 255, green: 250 / 255, blue: 240 / 255, alpha: 1)
    static let dangerFill = NSColor(srgbRed: 242 / 255, green: 217 / 255, blue: 209 / 255, alpha: 1)

    static func fill(for kind: BubbleActionKind) -> NSColor {
        switch kind {
        case .primary: return primaryFill
        case .secondary: return secondaryFill
        case .danger: return dangerFill
        }
    }

    static func textColour(for kind: BubbleActionKind) -> NSColor {
        // Only the primary button inverts its text; danger keeps the default.
        kind == .primary ? primaryText : messageColour
    }
}

/// The pet's speech bubble: a rounded panel with a downward tail, a centred
/// message, and up to three pill buttons.
///
/// An AppKit view rather than SwiftUI because it lives inside the pet's
/// `NSWindow` and has to participate in the same hit-testing that drives
/// click-through.
public final class SpeechBubbleView: NSView {
    /// Invoked with the tapped action's identifier.
    public var onAction: (String) -> Void = { _ in }

    private let messageLabel = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []
    private var actionsByTag: [Int: String] = [:]

    public private(set) var bubble: SpeechBubble?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        messageLabel.isEditable = false
        messageLabel.isBordered = false
        messageLabel.drawsBackground = false
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.cell?.wraps = true
        messageLabel.cell?.isScrollable = false
        addSubview(messageLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var isOpaque: Bool { false }

    /// The pet window never becomes key, so without this the first click on the
    /// bubble is discarded instead of reaching a button.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Content

    public func present(_ bubble: SpeechBubble) {
        self.bubble = bubble
        messageLabel.attributedStringValue = Self.attributedMessage(bubble.message)
        rebuildButtons(for: bubble.actions)
        needsDisplay = true
    }

    static func attributedMessage(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = BubbleStyle.messageLineHeightMultiple
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: BubbleStyle.messageFontSize),
            .foregroundColor: BubbleStyle.messageColour,
            .paragraphStyle: paragraph
        ])
    }

    private func rebuildButtons(for actions: [BubbleAction]) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        actionsByTag = [:]

        for (index, action) in actions.enumerated() {
            let button = BubbleButton(title: action.label, target: self, action: #selector(handleTap(_:)))
            button.isBordered = false
            button.wantsLayer = true
            button.tag = index
            button.attributedTitle = NSAttributedString(string: action.label, attributes: [
                .font: NSFont.systemFont(ofSize: BubbleStyle.buttonFontSize, weight: .medium),
                .foregroundColor: BubbleStyle.textColour(for: action.kind)
            ])
            button.layer?.backgroundColor = BubbleStyle.fill(for: action.kind).cgColor
            // border-radius: 999px reads as a pill.
            button.layer?.cornerRadius = BubbleStyle.buttonHeight / 2
            if action.kind == .secondary {
                button.layer?.borderWidth = 1
                button.layer?.borderColor = BubbleStyle.secondaryBorder.cgColor
            }
            actionsByTag[index] = action.id
            addSubview(button)
            buttons.append(button)
        }
    }

    @objc private func handleTap(_ sender: NSButton) {
        guard let id = actionsByTag[sender.tag] else { return }
        onAction(id)
    }

    // MARK: Layout

    /// Height the bubble needs for its current content, excluding the tail.
    public static func height(for bubble: SpeechBubble) -> CGFloat {
        let textWidth = width - padding * 2
        let messageHeight = attributedMessage(bubble.message).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height.rounded(.up)

        var height = padding * 2 + messageHeight
        if !bubble.actions.isEmpty {
            let rows = buttonRows(for: bubble.actions).count
            height += BubbleStyle.actionsTopMargin
            height += CGFloat(rows) * BubbleStyle.buttonHeight
            height += CGFloat(max(0, rows - 1)) * BubbleStyle.actionSpacing
        }
        return height
    }

    private static var width: CGFloat { BubbleStyle.width }
    private static var padding: CGFloat { BubbleStyle.padding }

    /// Splits actions into rows that fit the bubble width, matching
    /// `flex-wrap: wrap`.
    static func buttonRows(for actions: [BubbleAction]) -> [[BubbleAction]] {
        let available = width - padding * 2
        var rows: [[BubbleAction]] = []
        var current: [BubbleAction] = []
        var currentWidth: CGFloat = 0

        for action in actions {
            let buttonWidth = buttonWidth(for: action)
            let needed = current.isEmpty
                ? buttonWidth
                : currentWidth + BubbleStyle.actionSpacing + buttonWidth

            if !current.isEmpty, needed > available {
                rows.append(current)
                current = [action]
                currentWidth = buttonWidth
            } else {
                current.append(action)
                currentWidth = needed
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    static func buttonWidth(for action: BubbleAction) -> CGFloat {
        let title = NSAttributedString(string: action.label, attributes: [
            .font: NSFont.systemFont(ofSize: BubbleStyle.buttonFontSize, weight: .medium)
        ])
        return (title.size().width + BubbleStyle.buttonHorizontalPadding * 2).rounded(.up)
    }

    public override func layout() {
        super.layout()
        guard let bubble else { return }

        let contentWidth = bounds.width - BubbleStyle.padding * 2
        let rows = Self.buttonRows(for: bubble.actions)
        // The panel sits above the tail, so all content is offset upward by it.
        let contentBottom = BubbleStyle.tailHeight + BubbleStyle.padding
        let rowStride = BubbleStyle.buttonHeight + BubbleStyle.actionSpacing

        // Rows are indexed from the top, but Cocoa's y grows upward, so row 0
        // gets the highest origin. Buttons are consumed in action order so each
        // one receives the frame computed for its own label.
        var buttonIndex = 0
        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = row.reduce(CGFloat(0)) { $0 + Self.buttonWidth(for: $1) }
                + CGFloat(max(0, row.count - 1)) * BubbleStyle.actionSpacing
            var x = BubbleStyle.padding + (contentWidth - rowWidth) / 2
            let y = contentBottom + CGFloat(rows.count - 1 - rowIndex) * rowStride

            for action in row {
                guard buttonIndex < buttons.count else { break }
                let width = Self.buttonWidth(for: action)
                buttons[buttonIndex].frame = CGRect(
                    x: x, y: y, width: width, height: BubbleStyle.buttonHeight
                )
                x += width + BubbleStyle.actionSpacing
                buttonIndex += 1
            }
        }

        // The message fills whatever remains above the action block.
        var messageBottom = contentBottom
        if !rows.isEmpty {
            let actionsHeight = CGFloat(rows.count) * BubbleStyle.buttonHeight
                + CGFloat(max(0, rows.count - 1)) * BubbleStyle.actionSpacing
            messageBottom += actionsHeight + BubbleStyle.actionsTopMargin
        }
        let messageTop = bounds.height - BubbleStyle.padding
        messageLabel.frame = CGRect(
            x: BubbleStyle.padding,
            y: messageBottom,
            width: contentWidth,
            height: max(0, messageTop - messageBottom)
        )
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        // The tail occupies the bottom strip of the view's bounds.
        let panel = CGRect(
            x: 0,
            y: BubbleStyle.tailHeight,
            width: bounds.width,
            height: bounds.height - BubbleStyle.tailHeight
        )

        let path = NSBezierPath(roundedRect: panel, xRadius: BubbleStyle.cornerRadius,
                               yRadius: BubbleStyle.cornerRadius)

        // Downward tail, centred.
        let tail = NSBezierPath()
        let midX = bounds.midX
        tail.move(to: CGPoint(x: midX - BubbleStyle.tailHalfWidth, y: panel.minY + 1))
        tail.line(to: CGPoint(x: midX + BubbleStyle.tailHalfWidth, y: panel.minY + 1))
        tail.line(to: CGPoint(x: midX, y: 0))
        tail.close()

        BubbleStyle.background.setFill()
        path.fill()
        tail.fill()

        BubbleStyle.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// The whole bubble is interactive, so buttons near the edges still receive
    /// clicks.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard bubble != nil else { return nil }
        return super.hitTest(point)
    }
}

/// `NSButton` ignores the first click in a window that cannot become key.
private final class BubbleButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
