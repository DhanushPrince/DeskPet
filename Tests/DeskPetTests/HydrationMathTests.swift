import Foundation
import Testing
@testable import DeskPetKit

/// Pure pacing and progress math for smart-paced hydration. No AppKit, no clock.
@Suite("Hydration math")
struct HydrationMathTests {

    private let calendar = Calendar(identifier: .gregorian)

    /// A date at `hour:minute` on a fixed reference day, in the test calendar.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 10
        comps.hour = hour; comps.minute = minute
        return calendar.date(from: comps)!
    }

    private func settings(
        target: Int = 2000,
        serving: Int = 250,
        start: Int = 8 * 60,
        end: Int = 22 * 60,
        strategy: HydrationReminderStrategy = .smartPacing,
        stopAtGoal: Bool = true,
        enabled: Bool = true,
        interval: Int = 90
    ) -> Settings {
        var s = Settings.defaults
        s.hydrationTargetMilliliters = target
        s.hydrationServingMilliliters = serving
        s.hydrationActiveStartMinutes = start
        s.hydrationActiveEndMinutes = end
        s.hydrationReminderStrategy = strategy
        s.hydrationStopAtGoal = stopAtGoal
        s.hydrationReminderEnabled = enabled
        s.hydrationIntervalMinutes = interval
        return s
    }

    // MARK: litersString

    @Test("litersString trims trailing zeros")
    func litersFormatting() {
        #expect(HydrationMath.litersString(2000) == "2 L")
        #expect(HydrationMath.litersString(1250) == "1.25 L")
        #expect(HydrationMath.litersString(500) == "0.5 L")
        #expect(HydrationMath.litersString(0) == "0 L")
        #expect(HydrationMath.litersString(1500) == "1.5 L")
    }

    // MARK: remainingServings

    @Test("remaining servings rounds up and never shows zero while volume remains")
    func remainingServings() {
        #expect(HydrationMath.remainingServings(targetMilliliters: 2000, consumedMilliliters: 0, servingMilliliters: 250) == 8)
        #expect(HydrationMath.remainingServings(targetMilliliters: 2000, consumedMilliliters: 1000, servingMilliliters: 250) == 4)
        // 100 ml remaining with a 250 ml glass is still one glass.
        #expect(HydrationMath.remainingServings(targetMilliliters: 2000, consumedMilliliters: 1900, servingMilliliters: 250) == 1)
        // Goal met.
        #expect(HydrationMath.remainingServings(targetMilliliters: 2000, consumedMilliliters: 2000, servingMilliliters: 250) == 0)
        // No target.
        #expect(HydrationMath.remainingServings(targetMilliliters: 0, consumedMilliliters: 0, servingMilliliters: 250) == 0)
    }

    // MARK: nextHydrationDate — pacing

    @Test("initial pacing at active-window start spreads 8 servings across 14 hours (~105 min, clamped to 180)")
    func pacingInitial() throws {
        let now = at(8) // start of window, 0 consumed, 8 servings, 14h left
        let next = try #require(HydrationMath.nextHydrationDate(
            now: now, settings: settings(), consumedMilliliters: 0, calendar: calendar
        ))
        // 14h/8 = 105 min, within [45,180].
        let minutes = next.timeIntervalSince(now) / 60
        #expect(minutes == 105)
    }

    @Test("a big drink reduces remaining servings and widens the next gap (clamped to max 180)")
    func pacingBigDrink() throws {
        let now = at(10)
        // Consumed 1000 -> 4 servings left, 12h left -> 180 min raw, clamps to 180.
        let next = try #require(HydrationMath.nextHydrationDate(
            now: now, settings: settings(), consumedMilliliters: 1000, calendar: calendar
        ))
        #expect(next.timeIntervalSince(now) / 60 == 180)
    }

    @Test("very behind late in the day clamps to the minimum gap")
    func pacingBehindLate() throws {
        let now = at(21, 30) // 30 min left, 8 servings still needed
        let next = try #require(HydrationMath.nextHydrationDate(
            now: now, settings: settings(), consumedMilliliters: 0, calendar: calendar
        ))
        // raw 30/8 ~ 3.75 -> clamps up to minimum 45.
        #expect(next.timeIntervalSince(now) / 60 == 45)
    }

    @Test("serving larger than remaining still schedules one final reminder")
    func pacingServingLargerThanRemaining() throws {
        let now = at(12)
        // 100 ml remaining, 250 serving -> 1 serving; 10h left -> raw 600 clamps to 180.
        let next = try #require(HydrationMath.nextHydrationDate(
            now: now, settings: settings(), consumedMilliliters: 1900, calendar: calendar
        ))
        #expect(next.timeIntervalSince(now) / 60 == 180)
    }

    @Test("before the active window schedules at the window start")
    func pacingBeforeWindow() throws {
        let now = at(6)
        let next = try #require(HydrationMath.nextHydrationDate(
            now: now, settings: settings(), consumedMilliliters: 0, calendar: calendar
        ))
        #expect(next == at(8))
    }

    @Test("after the active window schedules nothing")
    func pacingAfterWindow() {
        let now = at(23)
        #expect(HydrationMath.nextHydrationDate(
            now: now, settings: settings(), consumedMilliliters: 0, calendar: calendar
        ) == nil)
    }

    @Test("goal reached with stop-at-goal schedules nothing")
    func pacingGoalReached() {
        let now = at(15)
        #expect(HydrationMath.nextHydrationDate(
            now: now, settings: settings(), consumedMilliliters: 2000, calendar: calendar
        ) == nil)
    }

    @Test("goal reached without stop-at-goal keeps pacing")
    func pacingGoalReachedNoStop() throws {
        let now = at(15)
        let next = HydrationMath.nextHydrationDate(
            now: now, settings: settings(stopAtGoal: false), consumedMilliliters: 2000, calendar: calendar
        )
        // Consumed >= target -> 0 remaining servings -> max(1) -> a gap is still produced.
        #expect(next != nil)
    }

    @Test("a mid-day target increase produces a tighter schedule than a smaller target")
    func pacingTargetChange() throws {
        let now = at(12)
        let small = try #require(HydrationMath.nextHydrationDate(
            now: now, settings: settings(target: 2000), consumedMilliliters: 1000, calendar: calendar
        ))
        let large = try #require(HydrationMath.nextHydrationDate(
            now: now, settings: settings(target: 4000), consumedMilliliters: 1000, calendar: calendar
        ))
        // More required servings for the larger target -> gap no wider.
        #expect(large.timeIntervalSince(now) <= small.timeIntervalSince(now))
    }

    @Test("an invalid active window (start >= end) is treated as always active")
    func pacingInvalidWindow() throws {
        let now = at(23)
        let next = HydrationMath.nextHydrationDate(
            now: now, settings: settings(start: 22 * 60, end: 8 * 60), consumedMilliliters: 0, calendar: calendar
        )
        #expect(next != nil) // not silenced by being "after" a window
    }

    // MARK: nextHydrationDate — strategy / disabled

    @Test("fixed-interval strategy ignores pacing and uses the interval")
    func fixedIntervalStrategy() throws {
        let now = at(10)
        let next = try #require(HydrationMath.nextHydrationDate(
            now: now, settings: settings(strategy: .fixedInterval, interval: 90), consumedMilliliters: 0, calendar: calendar
        ))
        #expect(next.timeIntervalSince(now) / 60 == 90)
    }

    @Test("zero target falls back to the fixed interval even under smart pacing")
    func zeroTargetFallsBackToInterval() throws {
        let now = at(10)
        let next = try #require(HydrationMath.nextHydrationDate(
            now: now, settings: settings(target: 0, interval: 60), consumedMilliliters: 0, calendar: calendar
        ))
        #expect(next.timeIntervalSince(now) / 60 == 60)
    }

    @Test("disabled hydration schedules nothing")
    func disabledSchedulesNothing() {
        let now = at(10)
        #expect(HydrationMath.nextHydrationDate(
            now: now, settings: settings(enabled: false), consumedMilliliters: 0, calendar: calendar
        ) == nil)
    }

    // MARK: HydrationProgress

    @Test("progress fraction is clamped and formatted")
    func progressFractionAndString() {
        let p = HydrationProgress(consumedMilliliters: 1250, targetMilliliters: 2000)
        #expect(p.fraction == 0.625)
        #expect(p.summaryString == "1.25 L / 2 L")
        #expect(!p.isGoalReached)

        let over = HydrationProgress(consumedMilliliters: 2500, targetMilliliters: 2000)
        #expect(over.fraction == 1)
        #expect(over.isGoalReached)

        let none = HydrationProgress(consumedMilliliters: 500, targetMilliliters: 0)
        #expect(none.fraction == 0)
        #expect(!none.hasTarget)
    }

    // MARK: milestones

    @Test("milestone fires only on the crossing increment")
    func milestoneCrossing() {
        // 750 -> 1000 crosses 50% (1000 of 2000).
        #expect(HydrationProgress.milestoneJustCrossed(previousMilliliters: 750, newMilliliters: 1000, targetMilliliters: 2000) == 50)
        // Already past 50%, moving to 1250 -> no milestone.
        #expect(HydrationProgress.milestoneJustCrossed(previousMilliliters: 1000, newMilliliters: 1250, targetMilliliters: 2000) == nil)
        // Crossing the goal.
        #expect(HydrationProgress.milestoneJustCrossed(previousMilliliters: 1900, newMilliliters: 2000, targetMilliliters: 2000) == 100)
        // A single big drink crossing multiple returns the highest.
        #expect(HydrationProgress.milestoneJustCrossed(previousMilliliters: 0, newMilliliters: 1600, targetMilliliters: 2000) == 75)
        // No target.
        #expect(HydrationProgress.milestoneJustCrossed(previousMilliliters: 0, newMilliliters: 500, targetMilliliters: 0) == nil)
    }
}
