import AppKit
import Foundation
import Testing
@testable import DeskPetKit

/// Ported from `tests/statsStore.test.ts`.
@Suite("Stats store", .serialized)
struct StatsStoreTests {

    private func makeStore(clock: TestClock = TestClock()) -> (StatsStore, Persistence, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let store = StatsStore(persistence: persistence, clock: clock)

        return (store, persistence, {
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("identical stats compare equal, and nil never does")
    func isSameStats() {
        let stats = DayStats(date: "2026-08-28", breaksTaken: 1)
        #expect(StatsStore.isSame(stats, stats))
        #expect(!StatsStore.isSame(nil, stats))

        var other = stats
        other.watersLogged = 1
        #expect(!StatsStore.isSame(other, stats))
    }

    @Test("the first read creates today's entry")
    func firstReadCreatesToday() {
        let clock = TestClock()
        let (store, _, cleanup) = makeStore(clock: clock)
        defer { cleanup() }

        let today = StatsDate.key(for: clock.now)
        let current = store.current()
        #expect(current.date == today)
        #expect(current.breaksTaken == 0)
        #expect(store.history[today] == current, "the day is mirrored into history")
    }

    @Test("updates accumulate and persist")
    func updatesPersist() {
        let (store, persistence, cleanup) = makeStore()
        defer { cleanup() }

        store.update { $0.breaksTaken += 1 }
        store.update { $0.watersLogged += 2 }
        let current = store.update { $0.focusMinutes += 25 }

        #expect(current.breaksTaken == 1)
        #expect(current.watersLogged == 2)
        #expect(current.focusMinutes == 25)
        #expect(persistence.currentStats == current)
        #expect(store.history[current.date] == current)
    }

    @Test("crossing to a new day archives the old one and starts fresh")
    func dateRolloverArchives() {
        let clock = TestClock()
        let (store, _, cleanup) = makeStore(clock: clock)
        defer { cleanup() }

        store.update { $0.breaksTaken = 4 }
        let firstDay = store.current().date

        // Advance two days so the calendar day certainly changes.
        clock.advance(by: 2 * 24 * 60 * 60)
        let secondDay = store.current()

        #expect(secondDay.date != firstDay)
        #expect(secondDay.breaksTaken == 0, "the new day starts empty")
        #expect(store.history[firstDay]?.breaksTaken == 4, "the old day is preserved")
        #expect(store.history.count == 2)
    }

    @Test("reopening on a day already in history resumes its counters")
    func rolloverReusesExistingDay() {
        let clock = TestClock()
        let (store, _, cleanup) = makeStore(clock: clock)
        defer { cleanup() }

        store.update { $0.breaksTaken = 2 }
        let day = store.current().date

        // Move to the next day and back, as a stale in-memory value would.
        clock.advance(by: 24 * 60 * 60)
        store.current()
        clock.advance(by: -24 * 60 * 60)

        let resumed = store.current(on: day)
        #expect(resumed.breaksTaken == 2, "the earlier counters are recovered")
    }

    @Test("resetting today zeroes the counters but keeps other days")
    func resetTodayKeepsHistory() {
        let clock = TestClock()
        let (store, _, cleanup) = makeStore(clock: clock)
        defer { cleanup() }

        store.update { $0.breaksTaken = 3 }
        let firstDay = store.current().date
        clock.advance(by: 24 * 60 * 60)
        store.update { $0.watersLogged = 5 }

        let reset = store.resetToday()
        #expect(reset.watersLogged == 0)
        #expect(store.history[firstDay]?.breaksTaken == 3, "yesterday is untouched")
    }

    @Test("an unchanged entry is not rewritten")
    func unchangedEntryIsNotRewritten() {
        let (store, persistence, cleanup) = makeStore()
        defer { cleanup() }

        store.update { $0.breaksTaken = 1 }
        let before = try? Data(contentsOf: persistence.statsFileURL)

        // Reading repeatedly must not churn the file.
        store.current()
        store.current()
        let after = try? Data(contentsOf: persistence.statsFileURL)
        #expect(before == after)
    }
}

@Suite("Focus badge")
@MainActor
struct FocusBadgeTests {

    @Test("the countdown is zero-padded HH:MM:SS")
    func countdownFormat() {
        #expect(FocusBadgeView.countdownText(remainingSeconds: 0) == "00:00:00")
        #expect(FocusBadgeView.countdownText(remainingSeconds: 5) == "00:00:05")
        #expect(FocusBadgeView.countdownText(remainingSeconds: 65) == "00:01:05")
        #expect(FocusBadgeView.countdownText(remainingSeconds: 25 * 60) == "00:25:00")
        #expect(FocusBadgeView.countdownText(remainingSeconds: 3661) == "01:01:01")
    }

    @Test("negative time floors at zero")
    func countdownFloors() {
        #expect(FocusBadgeView.countdownText(remainingSeconds: -30) == "00:00:00")
    }

    @Test("the badge sits centred above the bottom edge")
    func badgePosition() {
        let container = CGRect(origin: .zero, size: Constants.petWindowSize)
        let badge = FocusBadgeView(frame: .zero)
        badge.update(remainingSeconds: 1500, in: container)

        #expect(badge.frame.minY == FocusBadgeStyle.bottomInset)
        #expect(abs(badge.frame.midX - container.midX) <= 0.5)
        #expect(badge.frame.width > 0 && badge.frame.height > 0)
    }

    @Test("the badge keeps a constant width as digits change")
    func badgeWidthIsStable() {
        // Tabular figures matter: the badge must not jiggle every second.
        let container = CGRect(origin: .zero, size: Constants.petWindowSize)
        let badge = FocusBadgeView(frame: .zero)

        badge.update(remainingSeconds: 1500, in: container)
        let first = badge.frame.width
        badge.update(remainingSeconds: 1111, in: container)
        #expect(badge.frame.width == first)
    }

    @Test("the badge shows the ported label alongside the countdown")
    func badgeLabel() {
        let container = CGRect(origin: .zero, size: Constants.petWindowSize)
        let badge = FocusBadgeView(frame: .zero)
        badge.update(remainingSeconds: 60, in: container)
        #expect(badge.countdownText == "00:01:00")

        // Regression: a single attributed string measured wider than it drew,
        // clipping the countdown entirely.
        let fields = badge.subviews.compactMap { $0 as? NSTextField }
        #expect(fields.allSatisfy { $0.frame.width > 0 })
    }

    @Test("both fields fit inside the badge with the label first")
    func fieldsAreLaidOutInOrder() {
        let container = CGRect(origin: .zero, size: Constants.petWindowSize)
        let badge = FocusBadgeView(frame: .zero)
        badge.update(remainingSeconds: 1500, in: container)

        let fields = badge.subviews.compactMap { $0 as? NSTextField }
        #expect(fields.count == 2)
        let label = fields.first { $0.stringValue == Strings.focusBadgeLabel }
        let countdown = fields.first { $0.stringValue.contains(":") }
        #expect(label != nil)
        #expect(countdown != nil)

        if let label, let countdown {
            #expect(label.frame.maxX <= countdown.frame.minX, "label precedes the countdown")
            #expect(countdown.frame.maxX <= badge.bounds.width,
                    "the countdown must not overflow the pill")
            #expect(label.frame.minX >= FocusBadgeStyle.horizontalPadding - 0.5)
        }
    }
}

@Suite("Hydration flow", .serialized)
@MainActor
struct HydrationFlowTests {

    private func makeState() -> (AppState, TestClock, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let clock = TestClock()
        let state = AppState(persistence: persistence, clock: clock, random: { 0.5 })

        return (state, clock, {
            state.stop()
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    private func tap(_ state: AppState, _ id: String) {
        state.petWindow.contentView.bubbleView.onAction(id)
    }

    @Test("a due hydration reminder shows the prompt with two actions")
    func hydrationPromptShowsActions() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()
        // Disable breaks so only hydration can fire.
        state.updateSettings { $0.breakReminderEnabled = false }

        clock.advance(by: 91 * 60)
        state.scheduler.tick()

        #expect(state.petState == .hydrationPrompt)
        #expect(state.blockingMode == .hydration)
        let actions = state.petWindow.currentBubble?.actions.map(\.id)
        #expect(actions == [BubbleActionID.hydrationDone, BubbleActionID.hydrationSnooze])
        #expect(state.petWindow.currentBubble?.actions.first?.kind == .primary)
    }

    @Test("drinking increments the counter and hides the prompt")
    func drinkingIncrementsCounter() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoHydration)
        tap(state, BubbleActionID.hydrationDone)

        #expect(state.stats.watersLogged == 1)
        #expect(state.persistence.currentStats.watersLogged == 1)
        #expect(state.petState == .drinking)
        #expect(state.blockingMode == nil, "the block is released while drinking")
        #expect(!state.petWindow.isBubbleVisible, "the prompt is dismissed")
    }

    @Test("the drinking sequence celebrates then reschedules and settles")
    func drinkingSequenceCompletes() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()
        state.updateSettings { $0.breakReminderEnabled = false }

        state.handle(.demoHydration)
        state.scheduler.clearHydration()
        tap(state, BubbleActionID.hydrationDone)

        // drinkingDuration is 2.4s; wait past it plus the 1.9s tail.
        try await Task.sleep(for: .milliseconds(2600))
        #expect(state.petState == .hydrationDone)
        #expect(state.petWindow.currentBubble?.id == BubbleID.hydrationComplete)

        try await Task.sleep(for: .milliseconds(2100))
        #expect(state.petState == .idle)
        #expect(state.scheduler.hydrationDueAt != nil, "the next reminder is scheduled")
    }

    @Test("snoozing hydration settles the pet and reschedules 15 minutes out")
    func snoozeHydration() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoHydration)
        tap(state, BubbleActionID.hydrationSnooze)

        #expect(state.petState == .idle)
        #expect(state.blockingMode == nil)
        #expect(!state.petWindow.isBubbleVisible)
        let due = try #require(state.scheduler.hydrationDueAt)
        #expect(due.timeIntervalSince(clock.now) == Constants.hydrationSnooze)
    }

    @Test("demo hydration replaces an active break prompt")
    func demoHydrationOverridesBreakPrompt() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        #expect(state.petState == .breakPrompt)
        #expect(state.petWindow.currentBubble?.id == BubbleID.breakPrompt)

        state.handle(.demoHydration)
        #expect(state.petState == .hydrationPrompt)
        #expect(state.blockingMode == .hydration)
        #expect(state.petWindow.currentBubble?.id == BubbleID.hydrationPrompt)
        let actions = state.petWindow.currentBubble?.actions.map(\.id)
        #expect(actions == [BubbleActionID.hydrationDone, BubbleActionID.hydrationSnooze])
    }
}

@Suite("Focus flow", .serialized)
@MainActor
struct FocusFlowTests {

    private func makeState() -> (AppState, TestClock, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let clock = TestClock()
        let state = AppState(persistence: persistence, clock: clock, random: { 0.5 })

        return (state, clock, {
            state.stop()
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    private func tap(_ state: AppState, _ id: String) {
        state.petWindow.contentView.bubbleView.onAction(id)
    }

    @Test("starting focus guards, announces, and shows the badge")
    func startFocusShowsBadge() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.startFocus()

        #expect(state.focusActive)
        #expect(state.petState == .focusGuard)
        #expect(state.petWindow.currentBubble?.id == BubbleID.focusStart)
        #expect(state.petWindow.currentBubble?.message.contains("25") == true,
                "the message names the duration")
        #expect(state.petWindow.isFocusBadgeVisible)

        let endsAt = try #require(state.focusEndsAt)
        #expect(endsAt.timeIntervalSince(clock.now) == 25 * 60)
    }

    @Test("the badge counts down with the clock")
    func badgeCountsDown() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.startFocus()
        clock.advance(by: 60)
        state.refreshFocusBadge()
        #expect(state.petWindow.isFocusBadgeVisible)

        // 25 minutes less one leaves 24:00.
        let remaining = try #require(state.focusEndsAt).timeIntervalSince(clock.now)
        #expect(FocusBadgeView.countdownText(remainingSeconds: Int(remaining)) == "00:24:00")
    }

    @Test("stopping focus credits minutes and hides the badge")
    func stopFocusCreditsMinutes() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.startFocus()
        clock.advance(by: 20 * 60)
        state.stopFocus(completed: true)

        #expect(!state.focusActive)
        #expect(state.petState == .focusDone)
        #expect(state.stats.focusMinutes == 20)
        #expect(state.persistence.currentStats.focusMinutes == 20)
        #expect(!state.petWindow.isFocusBadgeVisible)
        #expect(state.focusEndsAt == nil)
    }

    @Test("a completed session and a cancelled one show different messages")
    func completedAndCancelledDiffer() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.startFocus()
        clock.advance(by: 60)
        state.stopFocus(completed: true)
        let completedMessage = try #require(state.petWindow.currentBubble?.message)
        #expect(Strings.Bubble.focusComplete.contains(completedMessage))

        state.startFocus()
        clock.advance(by: 60)
        state.stopFocus(completed: false)
        let cancelledMessage = try #require(state.petWindow.currentBubble?.message)
        #expect(Strings.Bubble.focusCancelled.contains(cancelledMessage))
    }

    @Test("the menu bar completes a session while the context menu cancels it")
    func menuActionsDifferInCompletion() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.startFocus)
        clock.advance(by: 60)
        state.handle(.stopFocusCompleted)
        #expect(Strings.Bubble.focusComplete.contains(
            state.petWindow.currentBubble?.message ?? ""
        ))

        state.handle(.startFocus)
        clock.advance(by: 60)
        state.handle(.stopFocusCancelled)
        #expect(Strings.Bubble.focusCancelled.contains(
            state.petWindow.currentBubble?.message ?? ""
        ))
    }

    @Test("reminders are suppressed during focus and fire once it ends")
    func remindersSuppressedDuringFocus() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()
        state.updateSettings { $0.hydrationReminderEnabled = false }

        state.startFocus()
        clock.advance(by: 46 * 60)
        state.scheduler.tick()

        #expect(state.petState == .focusGuard, "a break must not interrupt focus")
        // The due date is retained as an overdue marker.
        #expect(state.scheduler.breakDueAt != nil)

        state.stopFocus(completed: true)
        #expect(state.showOverdueReminder(), "the deferred break fires after focus")
        #expect(state.petState == .breakPrompt)
    }

    @Test("a focus warning counts a warning and offers back or end")
    func focusWarningOffersActions() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.startFocus()
        state.triggerFocusWarning(rule: "youtube")

        #expect(state.petState == .focusAlert)
        #expect(state.blockingMode == .focusWarning)
        #expect(state.stats.focusWarnings == 1)
        #expect(state.petWindow.currentBubble?.message.contains("youtube") == true)
        let actions = state.petWindow.currentBubble?.actions.map(\.id)
        #expect(actions == [BubbleActionID.focusBack, BubbleActionID.focusEnd])
    }

    @Test("back to work clears the warning and resumes guarding")
    func backToWorkResumesFocus() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.startFocus()
        state.triggerFocusWarning(rule: "reddit")
        tap(state, BubbleActionID.focusBack)

        #expect(state.petState == .focusGuard)
        #expect(state.blockingMode == nil)
        #expect(state.focusActive)
        #expect(state.petWindow.currentBubble?.id == BubbleID.focusBack)
    }

    @Test("ending focus from the warning stops the session")
    func endFromWarningStopsFocus() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.startFocus()
        clock.advance(by: 120)
        state.triggerFocusWarning(rule: "twitter")
        tap(state, BubbleActionID.focusEnd)

        #expect(!state.focusActive)
        #expect(state.petState == .focusDone)
        #expect(state.stats.focusMinutes == 2)
        #expect(Strings.Bubble.focusCancelled.contains(
            state.petWindow.currentBubble?.message ?? ""
        ))
    }

    @Test("the session's end timer is armed for the configured duration")
    func focusEndTimerIsArmed() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()
        state.updateSettings { $0.focusDurationMinutes = 50 }

        state.startFocus()

        // The end timer fires `stopFocus(completed: true)`; waiting 50 minutes is
        // impractical, so assert the deadline it was armed for. The stop path
        // itself is covered by `stopFocusCreditsMinutes`.
        let endsAt = try #require(state.focusEndsAt)
        #expect(endsAt.timeIntervalSince(clock.now) == 50 * 60)
    }

    @Test("a zero focus duration is treated as one minute rather than ending instantly")
    func zeroDurationIsClamped() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()
        // normalizeSettings leaves this field unclamped, so the guard is here.
        state.updateSettings { $0.focusDurationMinutes = 0 }

        state.startFocus()
        let endsAt = try #require(state.focusEndsAt)
        #expect(endsAt.timeIntervalSince(clock.now) == 60)
    }

    @Test("the badge disappears when focus is not running")
    func badgeHiddenWithoutFocus() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        #expect(!state.petWindow.isFocusBadgeVisible)
        state.refreshFocusBadge()
        #expect(!state.petWindow.isFocusBadgeVisible)
    }

    @Test("focus minutes accumulate across sessions")
    func focusMinutesAccumulate() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.startFocus()
        clock.advance(by: 10 * 60)
        state.stopFocus(completed: true)

        state.startFocus()
        clock.advance(by: 5 * 60)
        state.stopFocus(completed: true)

        #expect(state.stats.focusMinutes == 15)
    }
}
