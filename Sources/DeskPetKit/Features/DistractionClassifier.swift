import Foundation

/// The frontmost application and its focused window title.
public struct ActiveWindowInfo: Equatable, Sendable {
    public let appName: String
    public let windowTitle: String

    public init(appName: String, windowTitle: String = "") {
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

/// Rule matching for distraction detection.
///
/// Ported from `classifyDistraction` in `src/main/distraction.ts`.
public enum DistractionClassifier {
    /// Never treat the pet's own app as a distraction.
    ///
    /// "Electron" is vestigial — it was the process name of unpackaged
    /// development builds — but it is kept for parity.
    public static let ignoredApps = ["DeskPet", "Electron"]

    /// Prefixes on a match, so the caller can tell which list matched.
    public static let appPrefix = "app:"
    public static let keywordPrefix = "keyword:"

    static func normalizeRule(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Returns `app:<rule>` or `keyword:<rule>`, or nil when nothing matches.
    ///
    /// The returned rule is the *normalized* (trimmed, lowercased) form, which is
    /// what the original produced and therefore what the warning message shows.
    public static func classify(_ active: ActiveWindowInfo, settings: Settings) -> String? {
        let appName = active.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = active.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let appNameLower = appName.lowercased()
        let titleLower = title.lowercased()

        // Exact name match, not a substring, so an app merely *mentioning*
        // DeskPet is still checked.
        if ignoredApps.contains(where: { $0.lowercased() == appNameLower }) {
            return nil
        }

        // Blocked apps match against the app name only.
        if let rule = settings.distractionBlockedApps
            .map(normalizeRule)
            .first(where: { !$0.isEmpty && appNameLower.contains($0) }) {
            return appPrefix + rule
        }

        // Blocked keywords match the window title *or* the app name, which is
        // how a browser tab and a native client both get caught.
        if let rule = settings.distractionBlockedKeywords
            .map(normalizeRule)
            .first(where: { !$0.isEmpty && (titleLower.contains($0) || appNameLower.contains($0)) }) {
            return keywordPrefix + rule
        }

        return nil
    }

    /// Strips the `app:` / `keyword:` prefix for display in the warning bubble.
    public static func displayRule(_ match: String) -> String {
        if match.hasPrefix(appPrefix) {
            return String(match.dropFirst(appPrefix.count))
        }
        if match.hasPrefix(keywordPrefix) {
            return String(match.dropFirst(keywordPrefix.count))
        }
        return match
    }

    /// Whether a detected match should raise a warning now.
    ///
    /// Ported from the guards in `checkDistractionNow`: only while focused, never
    /// on top of an existing focus warning, and no more than once per cooldown.
    public static func shouldWarn(
        matchedRule: String?,
        focusActive: Bool,
        blockingMode: BlockingMode?,
        lastWarningAt: Date?,
        now: Date,
        cooldown: TimeInterval = Constants.distractionWarningCooldown
    ) -> Bool {
        guard matchedRule != nil else { return false }
        guard focusActive else { return false }
        guard blockingMode != .focusWarning else { return false }
        if let lastWarningAt, now.timeIntervalSince(lastWarningAt) < cooldown {
            return false
        }
        return true
    }
}

/// What the detector is currently doing, surfaced in settings.
public struct DistractionStatus: Equatable, Sendable {
    /// The Electron build also had an `unsupported` state for Windows, which has
    /// no meaning in a macOS-only app and is dropped.
    public enum State: String, Sendable {
        case idle
        case watching
        case permissionNeeded
        case error
    }

    public var state: State = .idle
    public var activeApp: String = ""
    public var activeWindowTitle: String = ""
    /// Display form, with the `app:`/`keyword:` prefix removed.
    public var matchedRule: String?
    public var lastCheckedAt: Date?
    public var lastWarningAt: Date?
    public var error: String?

    public init() {}
}
