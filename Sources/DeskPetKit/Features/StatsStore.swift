import Foundation

/// Today's counters plus the per-day history.
///
/// Ported from `src/main/statsStore.ts`. The rollover behaviour is the subtle
/// part: reading the current stats on a new day archives the previous day before
/// starting a fresh one, so no counters are lost when the app runs past
/// midnight.
public final class StatsStore {
    private let persistence: Persistence
    private let clock: DeskPetClock

    public init(persistence: Persistence, clock: DeskPetClock = SystemClock()) {
        self.persistence = persistence
        self.clock = clock
    }

    public var history: StatsHistory {
        persistence.statsHistory
    }

    /// Ported from `isSameStats`, used to avoid rewriting an unchanged entry.
    public static func isSame(_ left: DayStats?, _ right: DayStats) -> Bool {
        guard let left else { return false }
        return left == right
    }

    /// Ported from `saveStatsToHistory`.
    func saveToHistory(_ stats: DayStats) {
        guard !stats.date.isEmpty else { return }
        var file = persistence.statsFile
        guard !Self.isSame(file.history[stats.date], stats) else { return }
        file.history[stats.date] = stats
        persistence.statsFile = file
    }

    /// Ported from `getCurrentStats`: rolls the day over when the stored date is
    /// stale, reusing an existing history entry for the new day if the app was
    /// already open earlier that day.
    @discardableResult
    public func current(on date: String? = nil) -> DayStats {
        let today = date ?? StatsDate.key(for: clock.now)
        var file = persistence.statsFile

        guard file.current.date != today else {
            saveToHistory(file.current)
            return file.current
        }

        // Archive the outgoing day, then adopt the new one.
        saveToHistory(file.current)
        file = persistence.statsFile
        let next = file.history[today] ?? .empty(date: today)
        file.current = next
        persistence.statsFile = file
        saveToHistory(next)
        return next
    }

    /// Ported from `updateCurrentStats`.
    @discardableResult
    public func update(_ mutate: (inout DayStats) -> Void) -> DayStats {
        var next = current()
        mutate(&next)
        var file = persistence.statsFile
        file.current = next
        persistence.statsFile = file
        saveToHistory(next)
        return next
    }

    /// Ported from `resetCurrentStats`.
    @discardableResult
    public func resetToday() -> DayStats {
        let reset = DayStats.empty(date: StatsDate.key(for: clock.now))
        var file = persistence.statsFile
        file.current = reset
        persistence.statsFile = file
        saveToHistory(reset)
        return reset
    }
}
