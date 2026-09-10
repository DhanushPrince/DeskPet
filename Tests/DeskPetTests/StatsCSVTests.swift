import Foundation
import Testing
@testable import DeskPetKit

@Suite("Stats CSV export")
struct StatsCSVTests {

    @Test("export writes a header and one row per day, most recent first")
    func exportOrdersAndFormats() {
        let days = [
            DayStats(date: "2026-09-08", breaksTaken: 1, watersLogged: 4, focusMinutes: 10, focusWarnings: 2, waterMilliliters: 1000, waterTargetMilliliters: 2000),
            DayStats(date: "2026-09-10", breaksTaken: 0, watersLogged: 8, focusMinutes: 0, focusWarnings: 0, waterMilliliters: 2000, waterTargetMilliliters: 2000)
        ]
        let csv = StatsCSV.export(days)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        #expect(lines[0] == StatsCSV.header)
        // Most recent first.
        #expect(lines[1] == "2026-09-10,0,8,2000,2000,0,0")
        #expect(lines[2] == "2026-09-08,1,4,1000,2000,10,2")
    }

    @Test("export skips days with an empty date")
    func exportSkipsEmpty() {
        let days = [
            DayStats(date: ""),
            DayStats(date: "2026-09-10", watersLogged: 1, waterMilliliters: 250)
        ]
        let csv = StatsCSV.export(days)
        let rows = csv.split(separator: "\n").dropFirst()
        #expect(rows.count == 1)
    }

    @Test("export of no days is just the header")
    func exportEmpty() {
        #expect(StatsCSV.export([]) == StatsCSV.header + "\n")
    }
}
