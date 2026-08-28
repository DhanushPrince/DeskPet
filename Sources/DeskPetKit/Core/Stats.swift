import Foundation

/// One day's counters. Field names match the persisted JSON from the Electron
/// build.
public struct DayStats: Equatable, Codable, Sendable {
    public var date: String
    public var breaksTaken: Int
    public var watersLogged: Int
    public var focusMinutes: Int
    public var focusWarnings: Int

    public init(
        date: String,
        breaksTaken: Int = 0,
        watersLogged: Int = 0,
        focusMinutes: Int = 0,
        focusWarnings: Int = 0
    ) {
        self.date = date
        self.breaksTaken = breaksTaken
        self.watersLogged = watersLogged
        self.focusMinutes = focusMinutes
        self.focusWarnings = focusWarnings
    }

    /// Ported from `createEmptyStats`.
    public static func empty(date: String) -> DayStats {
        DayStats(date: date)
    }
}

/// Keyed by `YYYY-MM-DD`, matching `StatsHistory`.
public typealias StatsHistory = [String: DayStats]

public enum StatsDate {
    /// Ported from `todayKey`: local-time `YYYY-MM-DD`.
    ///
    /// Built from `Calendar.current` rather than a `DateFormatter` so it follows
    /// the user's time zone the way `Date.getFullYear()` did, without being
    /// affected by locale-specific numbering.
    public static func key(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// On-disk shape of `stats.json`.
///
/// ADR-4: settings live in `UserDefaults` because they are bounded key-value
/// data, while stats history grows one entry per day and is therefore kept in a
/// file.
struct StatsFile: Codable {
    var current: DayStats
    var history: StatsHistory
}
