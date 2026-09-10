import Foundation

/// Builds a CSV of daily stats for the "Export" button. Pure string assembly so
/// it can be unit-tested without a file panel; the view writes the result to a
/// user-chosen file.
public enum StatsCSV {
    public static let header = "date,breaks,waters,waterMilliliters,waterTargetMilliliters,focusMinutes,distractions"

    /// One CSV document, most recent day first. Dates are `YYYY-MM-DD` (no
    /// commas or quotes), and every field is an integer, so no escaping is
    /// needed.
    public static func export(_ days: [DayStats]) -> String {
        let sorted = days
            .filter { !$0.date.isEmpty }
            .sorted { $0.date > $1.date }
        let rows = sorted.map { day in
            [
                day.date,
                "\(day.breaksTaken)",
                "\(day.watersLogged)",
                "\(day.waterMilliliters)",
                "\(day.waterTargetMilliliters)",
                "\(day.focusMinutes)",
                "\(day.focusWarnings)"
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }
}
