import AppKit
import Foundation
import Testing
@testable import DeskPetKit

@Suite("Reminder math")
struct ReminderMathTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a due date is the interval ahead of now")
    func nextDueDate() throws {
        let due = try #require(
            ReminderMath.nextDueDate(from: Self.now, intervalMinutes: 45, enabled: true)
        )
        #expect(due.timeIntervalSince(Self.now) == 45 * 60)
    }

    @Test("a disabled reminder has no due date")
    func disabledHasNoDueDate() {
        #expect(ReminderMath.nextDueDate(from: Self.now, intervalMinutes: 45, enabled: false) == nil)
    }

    @Test("non-positive intervals are refused rather than fired continuously")
    func nonPositiveIntervalsRefused() {
        // normalizeSettings deliberately leaves these unclamped, so the guard
        // lives here.
        #expect(ReminderMath.nextDueDate(from: Self.now, intervalMinutes: 0, enabled: true) == nil)
        #expect(ReminderMath.nextDueDate(from: Self.now, intervalMinutes: -5, enabled: true) == nil)
        #expect(ReminderMath.nextDueDate(from: Self.now, after: 0) == nil)
        #expect(ReminderMath.nextDueDate(from: Self.now, after: -60) == nil)
    }

    @Test("a date at or before now is due")
    func dueComparison() {
        #expect(ReminderMath.isDue(Self.now, at: Self.now), "exactly now counts as due")
        #expect(ReminderMath.isDue(Self.now.addingTimeInterval(-1), at: Self.now))
        #expect(!ReminderMath.isDue(Self.now.addingTimeInterval(1), at: Self.now))
        #expect(!ReminderMath.isDue(nil, at: Self.now))
    }

    @Test("break wins when both reminders are overdue")
    func overduePrefersBreak() {
        let schedule = ReminderSchedule(
            breakDueAt: Self.now.addingTimeInterval(-10),
            hydrationDueAt: Self.now.addingTimeInterval(-100)
        )
        let kind = ReminderMath.overdueReminder(
            in: schedule, at: Self.now, settings: .defaults, breakMuted: false
        )
        #expect(kind == .breakReminder)
    }

    @Test("a muted break falls through to hydration")
    func overdueSkipsMutedBreak() {
        let schedule = ReminderSchedule(
            breakDueAt: Self.now.addingTimeInterval(-10),
            hydrationDueAt: Self.now.addingTimeInterval(-5)
        )
        let kind = ReminderMath.overdueReminder(
            in: schedule, at: Self.now, settings: .defaults, breakMuted: true
        )
        #expect(kind == .hydration)
    }

    @Test("disabled reminders are never overdue")
    func overdueRespectsEnablement() {
        var settings = Settings.defaults
        settings.breakReminderEnabled = false
        settings.hydrationReminderEnabled = false

        let schedule = ReminderSchedule(
            breakDueAt: Self.now.addingTimeInterval(-10),
            hydrationDueAt: Self.now.addingTimeInterval(-10)
        )
        #expect(ReminderMath.overdueReminder(
            in: schedule, at: Self.now, settings: settings, breakMuted: false
        ) == nil)
    }

    @Test("nothing overdue when both are in the future")
    func nothingOverdue() {
        let schedule = ReminderSchedule(
            breakDueAt: Self.now.addingTimeInterval(60),
            hydrationDueAt: Self.now.addingTimeInterval(60)
        )
        #expect(ReminderMath.overdueReminder(
            in: schedule, at: Self.now, settings: .defaults, breakMuted: false
        ) == nil)
    }

    @Test("the next midnight is the start of tomorrow and always in the future")
    func nextMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let midday = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 22:13 UTC
        let midnight = ReminderMath.nextMidnight(after: midday, calendar: calendar)

        #expect(midnight > midday)
        let parts = calendar.dateComponents([.hour, .minute, .second], from: midnight)
        #expect(parts.hour == 0)
        #expect(parts.minute == 0)
        #expect(parts.second == 0)
        #expect(midnight.timeIntervalSince(midday) <= 24 * 60 * 60)
    }
}

@Suite("Reminder scheduler", .serialized)
struct ReminderSchedulerTests {

    /// A scheduler that never arms a real timer, so `tick()` is the only driver.
    private func makeScheduler(
        settings: Settings = .defaults
    ) -> (ReminderScheduler, TestClock, () -> [ReminderKind]) {
        let clock = TestClock()
        let scheduler = ReminderScheduler(settings: settings, clock: clock)
        var raised: [ReminderKind] = []
        scheduler.onReminderDue = { kind in
            raised.append(kind)
            return .accepted
        }
        // Populate due dates without starting the run-loop timer.
        scheduler.rescheduleAll()
        return (scheduler, clock, { raised })
    }

    @Test("default settings schedule both reminders")
    func schedulesBoth() throws {
        let (scheduler, clock, _) = makeScheduler()

        let breakDue = try #require(scheduler.breakDueAt)
        let hydrationDue = try #require(scheduler.hydrationDueAt)
        #expect(breakDue.timeIntervalSince(clock.now) == 45 * 60)
        #expect(hydrationDue.timeIntervalSince(clock.now) == 90 * 60)
    }

    @Test("a reminder fires once its due date passes")
    func firesWhenDue() {
        let (scheduler, clock, raised) = makeScheduler()

        clock.advance(by: 44 * 60)
        scheduler.tick()
        #expect(raised().isEmpty, "not due yet")

        clock.advance(by: 2 * 60)
        scheduler.tick()
        #expect(raised() == [.breakReminder])
        #expect(scheduler.breakDueAt == nil, "an accepted reminder clears its due date")
    }

    @Test("break and hydration are independent")
    func independentTimers() {
        let (scheduler, clock, raised) = makeScheduler()

        clock.advance(by: 46 * 60)
        scheduler.tick()
        #expect(raised() == [.breakReminder])
        // Hydration is still pending at 90 minutes.
        #expect(scheduler.hydrationDueAt != nil)

        clock.advance(by: 45 * 60)
        scheduler.tick()
        #expect(raised() == [.breakReminder, .hydration])
    }

    @Test("break takes precedence when both come due together")
    func breakWinsWhenSimultaneous() {
        var settings = Settings.defaults
        settings.breakIntervalMinutes = 10
        settings.hydrationIntervalMinutes = 10
        let (scheduler, clock, raised) = makeScheduler(settings: settings)

        clock.advance(by: 11 * 60)
        scheduler.tick()
        #expect(raised() == [.breakReminder], "only one prompt at a time")

        // Hydration remains due and fires on the next tick.
        scheduler.tick()
        #expect(raised() == [.breakReminder, .hydration])
    }

    // MARK: Sleep and wake

    @Test("a reminder that came due during sleep fires immediately on wake")
    func firesAfterSleep() {
        let (scheduler, clock, raised) = makeScheduler()

        // Two hours pass while the machine is asleep; the 45-minute break
        // reminder is long overdue.
        clock.advance(by: 2 * 60 * 60)
        scheduler.handleWake()

        #expect(raised() == [.breakReminder], "must not wait out the remaining interval")
    }

    @Test("a long sleep does not fire a reminder more than once")
    func doesNotStackAfterSleep() {
        let (scheduler, clock, raised) = makeScheduler()

        clock.advance(by: 10 * 60 * 60)
        scheduler.handleWake()
        scheduler.tick()
        scheduler.tick()

        // Break fired and cleared; hydration then fires once.
        #expect(raised().filter { $0 == .breakReminder }.count == 1)
        #expect(raised().filter { $0 == .hydration }.count == 1)
    }

    // MARK: Outcomes

    @Test("a deferred reminder keeps its due date so it reads as overdue")
    func deferredKeepsDueDate() throws {
        let clock = TestClock()
        let scheduler = ReminderScheduler(settings: .defaults, clock: clock)
        var attempts = 0
        scheduler.onReminderDue = { _ in
            attempts += 1
            return .deferred
        }
        scheduler.rescheduleAll()

        clock.advance(by: 46 * 60)
        scheduler.tick()

        #expect(attempts == 1)
        let due = try #require(scheduler.breakDueAt, "a deferred reminder must stay overdue")
        #expect(due <= clock.now)

        // The catch-up path picks it up later.
        #expect(scheduler.showOverdueReminder() == false, "still deferred")
        #expect(attempts == 2)
    }

    @Test("a suppressed reminder clears its due date")
    func suppressedClearsDueDate() {
        let clock = TestClock()
        let scheduler = ReminderScheduler(settings: .defaults, clock: clock)
        scheduler.onReminderDue = { _ in .suppressed }
        scheduler.rescheduleAll()

        clock.advance(by: 46 * 60)
        scheduler.tick()
        #expect(scheduler.breakDueAt == nil)
    }

    @Test("the catch-up path raises an overdue reminder and reports acceptance")
    func overdueCatchUp() {
        let (scheduler, clock, raised) = makeScheduler()

        clock.advance(by: 46 * 60)
        // No tick: the due date is simply in the past, as it would be after a
        // blocking mode ended.
        #expect(scheduler.showOverdueReminder())
        #expect(raised() == [.breakReminder])
    }

    @Test("the catch-up path reports nothing when no reminder is overdue")
    func overdueCatchUpNoop() {
        let (scheduler, _, raised) = makeScheduler()
        #expect(!scheduler.showOverdueReminder())
        #expect(raised().isEmpty)
    }

    // MARK: Snooze

    @Test("snoozing a break reschedules it 10 minutes out")
    func breakSnooze() throws {
        let (scheduler, clock, _) = makeScheduler()
        scheduler.snoozeBreak()
        let due = try #require(scheduler.breakDueAt)
        #expect(due.timeIntervalSince(clock.now) == 10 * 60)
    }

    @Test("snoozing hydration reschedules it 15 minutes out")
    func hydrationSnooze() throws {
        let (scheduler, clock, _) = makeScheduler()
        scheduler.snoozeHydration()
        let due = try #require(scheduler.hydrationDueAt)
        #expect(due.timeIntervalSince(clock.now) == 15 * 60)
    }

    @Test("a snoozed reminder fires when the snooze elapses")
    func snoozeFires() {
        let (scheduler, clock, raised) = makeScheduler()
        scheduler.snoozeBreak()

        clock.advance(by: 9 * 60)
        scheduler.tick()
        #expect(raised().isEmpty)

        clock.advance(by: 2 * 60)
        scheduler.tick()
        #expect(raised() == [.breakReminder])
    }

    // MARK: Mute

    @Test("muting clears the break due date and unmuting restores it")
    func muteClearsAndRestores() {
        let (scheduler, _, raised) = makeScheduler()

        scheduler.setBreakMuted(true)
        #expect(scheduler.breakDueAt == nil)

        scheduler.setBreakMuted(false)
        #expect(scheduler.breakDueAt != nil)
        #expect(raised().isEmpty)
    }

    @Test("a muted break never fires")
    func mutedNeverFires() {
        let (scheduler, clock, raised) = makeScheduler()
        scheduler.setBreakMuted(true)

        clock.advance(by: 5 * 60 * 60)
        scheduler.tick()
        #expect(!raised().contains(.breakReminder))
    }

    // MARK: Settings changes

    @Test("changing the interval reschedules without a restart")
    func settingsChangeReschedules() throws {
        let (scheduler, clock, _) = makeScheduler()

        var settings = Settings.defaults
        settings.breakIntervalMinutes = 5
        scheduler.update(settings: settings)

        let due = try #require(scheduler.breakDueAt)
        #expect(due.timeIntervalSince(clock.now) == 5 * 60)
    }

    @Test("disabling a reminder clears its due date")
    func disablingClearsDueDate() {
        let (scheduler, _, _) = makeScheduler()

        var settings = Settings.defaults
        settings.breakReminderEnabled = false
        settings.hydrationReminderEnabled = false
        scheduler.update(settings: settings)

        #expect(scheduler.breakDueAt == nil)
        #expect(scheduler.hydrationDueAt == nil)
    }

    @Test("a corrupt interval leaves the reminder unscheduled rather than looping")
    func corruptIntervalIsSafe() {
        var settings = Settings.defaults
        settings.breakIntervalMinutes = 0
        let (scheduler, clock, raised) = makeScheduler(settings: settings)

        #expect(scheduler.breakDueAt == nil)
        clock.advance(by: 60 * 60)
        scheduler.tick()
        #expect(!raised().contains(.breakReminder))
    }

    // MARK: Midnight

    @Test("crossing midnight raises the rollover exactly once")
    func midnightRollover() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // 1700004600 = 2023-11-14 23:30:00 UTC (86400-aligned day start
        // 1699920000 plus 84600 seconds).
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_700_004_600))
        let scheduler = ReminderScheduler(settings: .defaults, clock: clock, calendar: calendar)
        var midnights = 0
        scheduler.onMidnight = { midnights += 1 }
        scheduler.start()
        defer { scheduler.stop() }

        clock.advance(by: 20 * 60)     // 23:50
        scheduler.tick()
        #expect(midnights == 0)

        clock.advance(by: 20 * 60)     // 00:10 next day
        scheduler.tick()
        #expect(midnights == 1)

        scheduler.tick()
        #expect(midnights == 1, "the boundary must advance, not re-fire")
    }

    @Test("a multi-day sleep raises the rollover once per wake")
    func midnightAfterLongSleep() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let clock = TestClock()
        let scheduler = ReminderScheduler(settings: .defaults, clock: clock, calendar: calendar)
        var midnights = 0
        scheduler.onMidnight = { midnights += 1 }
        scheduler.start()
        defer { scheduler.stop() }

        clock.advance(by: 3 * 24 * 60 * 60)
        scheduler.handleWake()
        #expect(midnights == 1, "one rollover per wake, not one per elapsed day")
    }

    // MARK: Countdown

    @Test("time remaining counts down and floors at zero")
    func timeRemaining() throws {
        let (scheduler, clock, _) = makeScheduler()

        let initial = try #require(scheduler.timeRemaining(for: .breakReminder))
        #expect(initial == 45 * 60)

        clock.advance(by: 44 * 60)
        let later = try #require(scheduler.timeRemaining(for: .breakReminder))
        #expect(later == 60)

        clock.advance(by: 10 * 60)
        #expect(scheduler.timeRemaining(for: .breakReminder) == 0)
    }

    @Test("time remaining is nil when nothing is scheduled")
    func timeRemainingUnscheduled() {
        let (scheduler, _, _) = makeScheduler()
        scheduler.clearBreak()
        #expect(scheduler.timeRemaining(for: .breakReminder) == nil)
    }
}

@Suite("Display change watcher", .serialized)
@MainActor
struct DisplayChangeWatcherTests {

    @Test("a burst of changes is coalesced into one callback")
    func debouncesBurst() async throws {
        let watcher = DisplayChangeWatcher(debounceInterval: 0.05)
        var changes = 0
        watcher.onChange = { changes += 1 }

        for _ in 0..<5 {
            watcher.scheduleChange()
        }
        #expect(changes == 0, "nothing delivered until the window settles")

        try await Task.sleep(for: .milliseconds(150))
        #expect(changes == 1, "five changes should coalesce into one")
    }

    @Test("separate changes each deliver")
    func separateChangesDeliver() async throws {
        let watcher = DisplayChangeWatcher(debounceInterval: 0.05)
        var changes = 0
        watcher.onChange = { changes += 1 }

        watcher.scheduleChange()
        try await Task.sleep(for: .milliseconds(150))
        watcher.scheduleChange()
        try await Task.sleep(for: .milliseconds(150))

        #expect(changes == 2)
    }

    @Test("stopping cancels a pending change")
    func stopCancelsPending() async throws {
        let watcher = DisplayChangeWatcher(debounceInterval: 0.05)
        var changes = 0
        watcher.onChange = { changes += 1 }

        watcher.scheduleChange()
        #expect(watcher.hasPendingChange)
        watcher.stop()

        try await Task.sleep(for: .milliseconds(150))
        #expect(changes == 0)
    }

    @Test("the debounce interval matches the Electron build")
    func debounceIntervalMatchesSource() {
        #expect(Constants.displayChangeDebounce == 0.25)
    }
}
