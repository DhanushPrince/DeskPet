import Foundation

/// Pure hydration pacing and progress arithmetic.
///
/// Split out from `ReminderScheduler` (which owns timers and wake handling) so
/// every branch — before/after the active window, goal reached, a large drink
/// just logged, a mid-day target change — is deterministic and unit-testable
/// without AppKit or a clock. The scheduler passes today's consumed volume in;
/// this type never reads stats or settings storage itself.
public enum HydrationMath {

    // MARK: Volume formatting

    /// Millilitres rendered as a compact litre string: 2000 -> "2 L",
    /// 1250 -> "1.25 L", 500 -> "0.5 L". Trailing zeros are trimmed.
    public static func litersString(_ milliliters: Int) -> String {
        let liters = Double(max(0, milliliters)) / 1000.0
        // Up to two decimals, trimming trailing zeros so 2.00 -> "2".
        var text = String(format: "%.2f", liters)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text) L"
    }

    // MARK: Servings

    /// Servings still needed to reach the target, rounded up so a partial glass
    /// still counts. Never returns 0 while any volume remains (a 100 ml gap with
    /// a 250 ml serving is "one glass left", not "0").
    public static func remainingServings(
        targetMilliliters: Int,
        consumedMilliliters: Int,
        servingMilliliters: Int
    ) -> Int {
        guard targetMilliliters > 0, servingMilliliters > 0 else { return 0 }
        let remaining = targetMilliliters - consumedMilliliters
        guard remaining > 0 else { return 0 }
        return Int((Double(remaining) / Double(servingMilliliters)).rounded(.up))
    }

    // MARK: Pacing

    /// The next hydration reminder time under the current strategy, or nil when
    /// no reminder should be scheduled (disabled, goal reached with stop-at-goal,
    /// or past the active window).
    ///
    /// Smart pacing spreads the remaining servings across the time left in the
    /// active window, clamped to `[minGap, maxGap]`. Fixed interval reproduces
    /// the original blind timer. A target of 0 (no goal) falls back to the fixed
    /// interval regardless of strategy, since pacing needs a target to divide.
    public static func nextHydrationDate(
        now: Date,
        settings: Settings,
        consumedMilliliters: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard settings.hydrationReminderEnabled else { return nil }

        let target = settings.hydrationTargetMilliliters
        let usePacing = settings.hydrationReminderStrategy == .smartPacing && target > 0
        guard usePacing else {
            return fixedIntervalDate(now: now, settings: settings)
        }

        // Goal reached: stay silent for the rest of the day when configured to.
        if settings.hydrationStopAtGoal, consumedMilliliters >= target {
            return nil
        }

        let (activeStart, activeEnd) = activeWindow(on: now, settings: settings, calendar: calendar)

        // Before the window opens: wait until it starts.
        if let activeStart, now < activeStart {
            return activeStart
        }
        // After the window closes: no more reminders today.
        if let activeEnd, now >= activeEnd {
            return nil
        }

        let servings = max(
            1,
            remainingServings(
                targetMilliliters: target,
                consumedMilliliters: consumedMilliliters,
                servingMilliliters: settings.hydrationServingMilliliters
            )
        )

        // Minutes left before the window closes (whole day if the window is
        // invalid / treated as always-active).
        let remainingMinutes: Double
        if let activeEnd {
            remainingMinutes = max(0, activeEnd.timeIntervalSince(now)) / 60.0
        } else {
            remainingMinutes = Double(Constants.hydrationMaxGapMinutes)
        }

        let rawGap = remainingMinutes / Double(servings)
        let gap = min(
            Double(Constants.hydrationMaxGapMinutes),
            max(Double(Constants.hydrationMinGapMinutes), rawGap)
        )
        return now.addingTimeInterval(gap * 60.0)
    }

    private static func fixedIntervalDate(now: Date, settings: Settings) -> Date? {
        ReminderMath.nextDueDate(
            from: now,
            intervalMinutes: settings.hydrationIntervalMinutes,
            enabled: settings.hydrationReminderEnabled
        )
    }

    /// The active window mapped onto `now`'s calendar day. Returns nil bounds
    /// when the window is invalid (start >= end), which callers treat as
    /// "always active".
    static func activeWindow(
        on now: Date,
        settings: Settings,
        calendar: Calendar = .current
    ) -> (start: Date?, end: Date?) {
        let start = settings.hydrationActiveStartMinutes
        let end = settings.hydrationActiveEndMinutes
        guard start < end else { return (nil, nil) }
        let midnight = calendar.startOfDay(for: now)
        let startDate = midnight.addingTimeInterval(TimeInterval(start) * 60)
        let endDate = midnight.addingTimeInterval(TimeInterval(end) * 60)
        return (startDate, endDate)
    }
}

/// Progress toward the daily target, plus milestone-crossing detection.
public struct HydrationProgress: Equatable, Sendable {
    public let consumedMilliliters: Int
    public let targetMilliliters: Int

    public init(consumedMilliliters: Int, targetMilliliters: Int) {
        self.consumedMilliliters = consumedMilliliters
        self.targetMilliliters = targetMilliliters
    }

    /// Whether a target is set (0 = no target).
    public var hasTarget: Bool { targetMilliliters > 0 }

    /// Progress fraction clamped to 0...1. No target -> 0.
    public var fraction: Double {
        guard targetMilliliters > 0 else { return 0 }
        return min(1, max(0, Double(consumedMilliliters) / Double(targetMilliliters)))
    }

    public var isGoalReached: Bool {
        hasTarget && consumedMilliliters >= targetMilliliters
    }

    /// "1.25 L / 2 L".
    public var summaryString: String {
        "\(HydrationMath.litersString(consumedMilliliters)) / \(HydrationMath.litersString(targetMilliliters))"
    }

    /// The milestone percentages tracked for gentle acknowledgements.
    public static let milestonePercents = [25, 50, 75, 100]

    /// The highest milestone (25/50/75/100) first crossed by moving from
    /// `previousMilliliters` to `newMilliliters`, or nil if none. Returns a
    /// value only on the crossing increment, so drinking further past a
    /// milestone never re-fires it.
    public static func milestoneJustCrossed(
        previousMilliliters: Int,
        newMilliliters: Int,
        targetMilliliters: Int
    ) -> Int? {
        guard targetMilliliters > 0, newMilliliters > previousMilliliters else { return nil }
        var crossed: Int?
        for percent in milestonePercents {
            let threshold = targetMilliliters * percent / 100
            if previousMilliliters < threshold, newMilliliters >= threshold {
                crossed = percent
            }
        }
        return crossed
    }
}
