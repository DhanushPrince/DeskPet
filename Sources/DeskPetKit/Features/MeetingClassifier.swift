import Foundation

/// Decides whether a set of Teams window titles means a call is in progress.
public enum MeetingClassifier {
    public static let teamsBundleIDs: Set<String> = [
        "com.microsoft.teams2",
        "com.microsoft.teams"
    ]

    /// Case-insensitive substrings for explicit call / meeting wording.
    public static let titleKeywords = [
        "meeting",
        "call",
        "calling",
        "calling you",
        "is calling",
        "incoming call"
    ]

    /// Exact (case-insensitive) main-window / chrome titles, not an active call.
    public static let chromeTitles: Set<String> = [
        "microsoft teams",
        "teams",
        "calendar",
        "activity",
        "chat",
        "calls",
        "files",
        "apps",
        "help",
        "settings",
        "new chat"
    ]

    public static func isTeamsBundleID(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return teamsBundleIDs.contains(bundleID)
    }

    /// Chat tabs and shell windows: `"Jane | Microsoft Teams"`, bare `Calendar`, etc.
    public static func isTeamsChromeOrChatTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        if chromeTitles.contains(lower) { return true }
        if lower.contains(" | microsoft teams") || lower.contains(" | teams") {
            return true
        }
        return false
    }

    public static func titleLooksLikeMeeting(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        let chrome = isTeamsChromeOrChatTitle(trimmed)
        let keywordHit = titleKeywords.contains { lower.contains($0) }

        if keywordHit {
            // Bare "Calls" contains "call" but is shell chrome, not an active call.
            if chrome && chromeTitles.contains(lower) {
                return false
            }
            return true
        }

        // After Accept, 1:1 call windows are often just the person's name.
        return !chrome
    }

    public static func isInMeeting(titles: [String]) -> Bool {
        titles.contains { titleLooksLikeMeeting($0) }
    }
}
