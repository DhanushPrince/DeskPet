import Foundation

/// Visual weight of a bubble button, ported from the `.bubble-button`
/// modifier classes.
public enum BubbleActionKind: String, Equatable, Sendable {
    case primary
    case secondary
    case danger
}

/// One button in a speech bubble.
public struct BubbleAction: Equatable, Identifiable, Sendable {
    /// Stable identifier routed back to the app, e.g. `break:snooze`.
    public let id: String
    public let label: String
    public let kind: BubbleActionKind

    public init(id: String, label: String, kind: BubbleActionKind = .secondary) {
        self.id = id
        self.label = label
        self.kind = kind
    }
}

/// A message shown above the pet, optionally with actions.
public struct SpeechBubble: Equatable, Identifiable, Sendable {
    /// Identifies the bubble so a later update can replace rather than stack.
    public let id: String
    public let message: String
    public let actions: [BubbleAction]
    /// Seconds until the bubble disappears on its own. Nil means it stays until
    /// dismissed or replaced.
    public let autoDismissAfter: TimeInterval?

    public init(
        id: String,
        message: String,
        actions: [BubbleAction] = [],
        autoDismissAfter: TimeInterval? = nil
    ) {
        self.id = id
        self.message = message
        self.actions = actions
        self.autoDismissAfter = autoDismissAfter
    }
}

/// Action identifiers, matching the strings the Electron renderer sent over
/// `bubble:action`.
public enum BubbleActionID {
    public static let breakDone = "break:done"
    public static let breakSnooze = "break:snooze"
    public static let breakMute = "break:mute"
    public static let breakRunDone = "break-run:done"
    public static let hydrationDone = "hydration:done"
    public static let hydrationSnooze = "hydration:snooze"
    public static let focusBack = "focus:back"
    public static let focusEnd = "focus:end"
    public static let openReleaseNotes = "app:open-release-notes"
    public static let installUpdate = "app:install-update"
    public static let dismissUpdate = "app:dismiss-update"
}

/// Bubble identifiers, also matching the originals.
public enum BubbleID {
    public static let happy = "happy"
    public static let breakPrompt = "break"
    public static let breakRun = "break-run"
    public static let breakRunComplete = "break-run-complete"
    public static let breakMuted = "break-muted"
    public static let hydrationPrompt = "hydration"
    public static let hydrationComplete = "hydration-complete"
    public static let focusStart = "focus-start"
    public static let focusWarning = "focus-warning"
    public static let focusComplete = "focus-complete"
    public static let focusBack = "focus-back"
    public static let updateAvailable = "update-available"
}
