import AppKit

/// Geometry and colours transcribed from `.focus-badge` in `styles.css`.
enum FocusBadgeStyle {
    static let bottomInset: CGFloat = 8
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 4
    /// `gap: 6px` between the label and the countdown.
    static let gap: CGFloat = 6
    static let fontSize: CGFloat = 11

    static let background = NSColor(srgbRed: 255 / 255, green: 252 / 255, blue: 244 / 255, alpha: 0.86)
    static let border = NSColor(srgbRed: 36 / 255, green: 78 / 255, blue: 69 / 255, alpha: 0.14)
    static let labelColour = NSColor(srgbRed: 36 / 255, green: 78 / 255, blue: 69 / 255, alpha: 1)
    static let countdownColour = NSColor(srgbRed: 45 / 255, green: 38 / 255, blue: 31 / 255, alpha: 1)

    /// `font-weight: 650` sits between semibold and bold; semibold is the
    /// closest system weight.
    static var labelFont: NSFont {
        .systemFont(ofSize: fontSize, weight: .semibold)
    }

    /// Tabular figures stop the badge resizing as the digits change.
    static var countdownFont: NSFont {
        .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
    }
}

/// A small pill at the bottom of the pet window showing the remaining focus
/// time, mirroring the renderer's `.focus-badge`.
///
/// The label and the countdown are separate fields, as they were separate
/// elements in the original markup; a single attributed string measured wider
/// than it drew, silently clipping the countdown.
public final class FocusBadgeView: NSView {
    private let labelField = NSTextField(labelWithString: Strings.focusBadgeLabel)
    private let countdownField = NSTextField(labelWithString: "00:00:00")

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = FocusBadgeStyle.background.cgColor
        layer?.borderColor = FocusBadgeStyle.border.cgColor
        layer?.borderWidth = 1

        for field in [labelField, countdownField] {
            field.isEditable = false
            field.isBordered = false
            field.drawsBackground = false
            field.lineBreakMode = .byClipping
            addSubview(field)
        }

        labelField.font = FocusBadgeStyle.labelFont
        labelField.textColor = FocusBadgeStyle.labelColour
        countdownField.font = FocusBadgeStyle.countdownFont
        countdownField.textColor = FocusBadgeStyle.countdownColour
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var isOpaque: Bool { false }

    /// Formats remaining seconds as `HH:MM:SS`.
    ///
    /// Ported from `formatFocusCountdown`, which zero-padded all three
    /// components regardless of magnitude.
    public static func countdownText(remainingSeconds: Int) -> String {
        let clamped = max(0, remainingSeconds)
        return String(
            format: "%02d:%02d:%02d",
            clamped / 3600,
            (clamped % 3600) / 60,
            clamped % 60
        )
    }

    /// Updates the countdown and resizes to fit, staying centred above the
    /// bottom edge of `container`.
    public func update(remainingSeconds: Int, in container: CGRect) {
        countdownField.stringValue = Self.countdownText(remainingSeconds: remainingSeconds)

        labelField.sizeToFit()
        countdownField.sizeToFit()

        // Width comes from the laid-out fields rather than a separate
        // measurement: `sizeToFit` produces fractional widths, and rounding a
        // parallel calculation left the countdown half a point outside the pill.
        let contentWidth = labelField.frame.width + FocusBadgeStyle.gap
            + countdownField.frame.width
        let contentHeight = max(labelField.frame.height, countdownField.frame.height)
        let width = (contentWidth + FocusBadgeStyle.horizontalPadding * 2).rounded(.up)
        let height = (contentHeight + FocusBadgeStyle.verticalPadding * 2).rounded(.up)

        frame = CGRect(
            x: ((container.width - width) / 2).rounded(),
            y: FocusBadgeStyle.bottomInset,
            width: width,
            height: height
        )
        // border-radius: 999px reads as a pill.
        layer?.cornerRadius = height / 2

        labelField.frame = CGRect(
            x: FocusBadgeStyle.horizontalPadding,
            y: ((height - labelField.frame.height) / 2).rounded(),
            width: labelField.frame.width,
            height: labelField.frame.height
        )
        countdownField.frame = CGRect(
            x: labelField.frame.maxX + FocusBadgeStyle.gap,
            y: ((height - countdownField.frame.height) / 2).rounded(),
            width: countdownField.frame.width,
            height: countdownField.frame.height
        )
    }

    /// Current countdown text, for tests.
    public var countdownText: String { countdownField.stringValue }
}
