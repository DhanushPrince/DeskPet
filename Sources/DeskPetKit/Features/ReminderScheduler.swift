import AppKit
import Foundation

/// Which reminder came due.
public enum ReminderKind: String, Equatable, Sendable {
    case breakReminder
    case hydration
}

/// What the app did with a reminder the scheduler raised.
///
/// The distinction matters because the Electron build treated the two refusal
/// cases differently: a muted break cleared its due date, while one blocked by
/// another prompt or by focus mode *kept* it, leaving the stale date as the
/// marker that `showOverdueReminder` later used to catch up.
public enum ReminderOutcome: Equatable, Sendable {
    /// Shown. The due date is cleared and rescheduling is up to the caller.
    case accepted
    /// Refused permanently for now (break reminders muted for the day).
    case suppressed
    /// Refused temporarily. The due date is retained so it reads as overdue.
    case deferred
}

/// Absolute due-times for the two recurring reminders.
///
/// Wall-clock `Date`s rather than interval countdowns: the Electron build used
/// `setTimeout`, which pauses while the machine sleeps, so a 45-minute reminder
/// set before a two-hour sleep fired 45 minutes after waking instead of
/// immediately.
public struct ReminderSchedule: Equatable, Sendable {
    public var breakDueAt: Date?
    public var hydrationDueAt: Date?

    public init(breakDueAt: Date? = nil, hydrationDueAt: Date? = nil) {
        self.breakDueAt = breakDueAt
        self.hydrationDueAt = hydrationDueAt
    }

    public func dueAt(_ kind: ReminderKind) -> Date? {
        switch kind {
        case .breakReminder: return breakDueAt
        case .hydration: return hydrationDueAt
        }
    }
}

/// Pure scheduling arithmetic.
public enum ReminderMath {

    /// Next due date, or nil when the reminder is disabled or the interval is
    /// unusable.
    ///
    /// The non-positive guard matters because `normalizeSettings` deliberately
    /// left the interval fields unclamped (the Electron settings UI constrained
    /// them instead), so a corrupt or hand-edited value could otherwise produce
    /// a timer that fires continuously.
    public static func nextDueDate(
        from now: Date,
        intervalMinutes: Int,
        enabled: Bool
    ) -> Date? {
        guard enabled, intervalMinutes > 0 else { return nil }
        return now.addingTimeInterval(TimeInterval(intervalMinutes) * 60)
    }

    public static func nextDueDate(from now: Date, after interval: TimeInterval) -> Date? {
        guard interval > 0 else { return nil }
        return now.addingTimeInterval(interval)
    }

    public static func isDue(_ date: Date?, at now: Date) -> Bool {
        guard let date else { return false }
        return date <= now
    }

    /// Ported from `showOverdueReminder`: break wins when both are overdue, and
    /// a muted break is skipped entirely.
    public static func overdueReminder(
        in schedule: ReminderSchedule,
        at now: Date,
        settings: Settings,
        breakMuted: Bool
    ) -> ReminderKind? {
        if settings.breakReminderEnabled, !breakMuted, isDue(schedule.breakDueAt, at: now) {
            return .breakReminder
        }
        if settings.hydrationReminderEnabled, isDue(schedule.hydrationDueAt, at: now) {
            return .hydration
        }
        return nil
    }

    /// Start of the next calendar day, used for the midnight rollover.
    public static func nextMidnight(after now: Date, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday)
            // A day that cannot be advanced (an impossible calendar) still needs
            // a future boundary rather than one in the past.
            ?? now.addingTimeInterval(24 * 60 * 60)
    }
}

/// Drives the break and hydration reminders and the midnight rollover.
///
/// A single timer targets the earliest upcoming deadline and is re-armed after
/// each fire, rather than one timer per reminder. Deadlines use
/// `DispatchWallTime`, which tracks the wall clock across sleep, and the
/// scheduler additionally re-evaluates on wake so a reminder that came due while
/// the machine was asleep fires straight away.
public final class ReminderScheduler {
    // MARK: Callbacks

    /// Raised when a reminder comes due. The return value decides whether the
    /// due date is cleared or kept as an overdue marker.
    public var onReminderDue: (ReminderKind) -> ReminderOutcome = { _ in .deferred }
    /// Raised once per calendar day boundary.
    public var onMidnight: () -> Void = {}

    // MARK: State

    public private(set) var schedule = ReminderSchedule()
    /// Exposed for the settings window's countdown display.
    public var breakDueAt: Date? { schedule.breakDueAt }
    public var hydrationDueAt: Date? { schedule.hydrationDueAt }

    private let clock: DeskPetClock
    private let calendar: Calendar
    private var settings: Settings
    private var breakMuted = false

    private var timer: DispatchSourceTimer?
    private var midnightBoundary: Date?
    private var wakeObserver: NSObjectProtocol?
    private var isRunning = false

    public init(
        settings: Settings,
        clock: DeskPetClock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.settings = settings
        self.clock = clock
        self.calendar = calendar
    }

    deinit {
        stop()
    }

    // MARK: Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        midnightBoundary = ReminderMath.nextMidnight(after: clock.now, calendar: calendar)
        observeWake()
        rescheduleAll()
    }

    public func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }
    }

    /// Re-evaluates everything after the machine wakes. Anything that came due
    /// during sleep is already in the past, so `tick` fires it immediately.
    public func handleWake() {
        NSLog("DeskPet: woke, re-evaluating reminders")
        tick()
    }

    // MARK: Scheduling

    /// Ported from `scheduleReminderTimers`: clears both and schedules afresh
    /// from the current settings.
    public func rescheduleAll() {
        schedule.breakDueAt = nextBreakDueDate()
        schedule.hydrationDueAt = nextHydrationDueDate()
        armTimer()
    }

    /// Applies changed settings, rescheduling both reminders.
    public func update(settings newSettings: Settings) {
        settings = newSettings
        rescheduleAll()
    }

    public func setBreakMuted(_ muted: Bool) {
        breakMuted = muted
        if muted {
            schedule.breakDueAt = nil
        } else if schedule.breakDueAt == nil {
            schedule.breakDueAt = nextBreakDueDate()
        }
        armTimer()
    }

    /// Ported from `scheduleBreakReminderTimer`. A muted or disabled reminder
    /// clears its due date instead.
    public func scheduleBreak(after interval: TimeInterval? = nil) {
        guard settings.breakReminderEnabled, !breakMuted else {
            schedule.breakDueAt = nil
            armTimer()
            return
        }
        schedule.breakDueAt = interval.flatMap {
            ReminderMath.nextDueDate(from: clock.now, after: $0)
        } ?? nextBreakDueDate()
        armTimer()
    }

    /// Ported from `scheduleHydrationReminderTimer`.
    public func scheduleHydration(after interval: TimeInterval? = nil) {
        guard settings.hydrationReminderEnabled else {
            schedule.hydrationDueAt = nil
            armTimer()
            return
        }
        schedule.hydrationDueAt = interval.flatMap {
            ReminderMath.nextDueDate(from: clock.now, after: $0)
        } ?? nextHydrationDueDate()
        armTimer()
    }

    public func snoozeBreak() {
        scheduleBreak(after: Constants.breakSnooze)
    }

    public func snoozeHydration() {
        scheduleHydration(after: Constants.hydrationSnooze)
    }

    public func clearBreak() {
        schedule.breakDueAt = nil
        armTimer()
    }

    public func clearHydration() {
        schedule.hydrationDueAt = nil
        armTimer()
    }

    private func nextBreakDueDate() -> Date? {
        guard !breakMuted else { return nil }
        return ReminderMath.nextDueDate(
            from: clock.now,
            intervalMinutes: settings.breakIntervalMinutes,
            enabled: settings.breakReminderEnabled
        )
    }

    private func nextHydrationDueDate() -> Date? {
        ReminderMath.nextDueDate(
            from: clock.now,
            intervalMinutes: settings.hydrationIntervalMinutes,
            enabled: settings.hydrationReminderEnabled
        )
    }

    // MARK: Catch-up

    /// Ported from `showOverdueReminder`, minus the blocking-mode and focus
    /// checks the state machine owns (`allowsOverdueReminder`).
    ///
    /// - Returns: true when a reminder was raised.
    @discardableResult
    public func showOverdueReminder() -> Bool {
        guard let kind = ReminderMath.overdueReminder(
            in: schedule,
            at: clock.now,
            settings: settings,
            breakMuted: breakMuted
        ) else {
            return false
        }
        return raise(kind) == .accepted
    }

    // MARK: Ticking

    /// Evaluates due dates against the clock. Called by the timer, on wake, and
    /// directly by tests.
    public func tick() {
        let now = clock.now

        if let boundary = midnightBoundary, now >= boundary {
            midnightBoundary = ReminderMath.nextMidnight(after: now, calendar: calendar)
            onMidnight()
        }

        // Break takes precedence when both are due, matching the ordering in
        // `showOverdueReminder`. Only one prompt can be shown at a time.
        if ReminderMath.isDue(schedule.breakDueAt, at: now), !breakMuted,
           settings.breakReminderEnabled {
            raise(.breakReminder)
        } else if ReminderMath.isDue(schedule.hydrationDueAt, at: now),
                  settings.hydrationReminderEnabled {
            raise(.hydration)
        }

        armTimer()
    }

    @discardableResult
    private func raise(_ kind: ReminderKind) -> ReminderOutcome {
        let outcome = onReminderDue(kind)
        switch outcome {
        case .accepted, .suppressed:
            // Clear the due date; the caller reschedules when appropriate.
            switch kind {
            case .breakReminder: schedule.breakDueAt = nil
            case .hydration: schedule.hydrationDueAt = nil
            }
        case .deferred:
            // Left in the past on purpose, so it reads as overdue later.
            break
        }
        return outcome
    }

    /// Arms one timer for the earliest of the two due dates and the next
    /// midnight.
    private func armTimer() {
        timer?.cancel()
        timer = nil
        guard isRunning else { return }

        let deadlines = [schedule.breakDueAt, schedule.hydrationDueAt, midnightBoundary]
            .compactMap { $0 }
        guard let earliest = deadlines.min() else { return }

        let now = clock.now
        // A deadline already in the past still needs a tick, so floor at zero
        // rather than skipping.
        let delay = max(0, earliest.timeIntervalSince(now))

        let source = DispatchSource.makeTimerSource(queue: .main)
        // Wall time rather than the default monotonic clock: this deadline must
        // survive system sleep.
        source.schedule(wallDeadline: .now() + delay, leeway: .milliseconds(200))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = source
        source.activate()
    }

    /// Seconds until a due date, for countdown displays.
    public func timeRemaining(for kind: ReminderKind) -> TimeInterval? {
        guard let due = schedule.dueAt(kind) else { return nil }
        return max(0, due.timeIntervalSince(clock.now))
    }
}
