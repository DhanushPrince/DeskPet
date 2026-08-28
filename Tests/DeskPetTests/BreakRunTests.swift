import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import DeskPetKit

@Suite("Break run physics")
struct BreakRunPhysicsTests {
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let workArea = GlobalRect(x: 0, y: 0, width: 1440, height: 900)
    static let size = Constants.petWindowSize   // 220 × 340

    /// Returns a generator that yields the given values then repeats the last.
    private func scripted(_ values: [Double]) -> BreakRunPhysics.RandomSource {
        var index = 0
        return {
            let value = values[min(index, values.count - 1)]
            index += 1
            return value
        }
    }

    // MARK: Velocity

    @Test("speed stays within the ported bounds", arguments: [0.0, 0.25, 0.5, 0.99])
    func speedBounds(sample: Double) {
        let velocity = BreakRunPhysics.chooseVelocity(random: { sample })
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        // 3.5 + r * 2.9, so 3.5 ..< 6.4.
        #expect(speed >= Constants.BreakRun.speedBase - 0.0001)
        #expect(speed <= Constants.BreakRun.speedBase + Constants.BreakRun.speedRange + 0.0001)
    }

    @Test("a zero draw gives the base speed heading right")
    func zeroDrawIsBaseSpeed() {
        // speed = 3.5, angle = 0 → straight along +x.
        let velocity = BreakRunPhysics.chooseVelocity(random: scripted([0, 0]))
        #expect(abs(velocity.x - Constants.BreakRun.speedBase) < 0.0001)
        #expect(abs(velocity.y) < 0.0001)
    }

    @Test("random speeds are always non-zero so the pet keeps moving")
    func velocityIsNeverZero() {
        for _ in 0..<200 {
            let velocity = BreakRunPhysics.chooseVelocity(random: BreakRunPhysics.systemRandom)
            let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
            #expect(speed >= Constants.BreakRun.speedBase - 0.0001)
        }
    }

    // MARK: Limits

    @Test("travel limits inset the work area by 8pt on every side")
    func limitsUseEdgeInset() {
        let limits = BreakRunPhysics.limits(workArea: Self.workArea, size: Self.size)
        #expect(limits.minX == 8)
        #expect(limits.maxX == 1440 - 220 - 8)   // 1212
        #expect(limits.minY == 8)
        #expect(limits.maxY == 900 - 340 - 8)    // 552
    }

    @Test("limits follow a work area that does not start at the origin")
    func limitsRespectWorkAreaOrigin() {
        let offset = GlobalRect(x: -611, y: -1440, width: 2560, height: 1440)
        let limits = BreakRunPhysics.limits(workArea: offset, size: Self.size)
        #expect(limits.minX == -603)
        #expect(limits.minY == -1432)
    }

    // MARK: Bouncing

    @Test("the left edge reverses horizontal travel")
    func bouncesOffLeftEdge() {
        let state = BreakRunPhysics.State(
            position: CGPoint(x: 10, y: 300),
            velocity: CGPoint(x: -5, y: 0),
            nextTurnAt: Self.now.addingTimeInterval(100)   // no turn this tick
        )
        let next = BreakRunPhysics.step(
            state, workArea: Self.workArea, size: Self.size,
            now: Self.now, random: { 0.99 }
        )
        #expect(next.position.x == 8, "pinned to the inset edge")
        #expect(next.velocity.x > 0, "now heading right")
    }

    @Test("the right edge reverses horizontal travel")
    func bouncesOffRightEdge() {
        let state = BreakRunPhysics.State(
            position: CGPoint(x: 1210, y: 300),
            velocity: CGPoint(x: 5, y: 0),
            nextTurnAt: Self.now.addingTimeInterval(100)
        )
        let next = BreakRunPhysics.step(
            state, workArea: Self.workArea, size: Self.size,
            now: Self.now, random: { 0.99 }
        )
        #expect(next.position.x == 1212)
        #expect(next.velocity.x < 0)
    }

    @Test("the top edge reverses vertical travel")
    func bouncesOffTopEdge() {
        let state = BreakRunPhysics.State(
            position: CGPoint(x: 500, y: 10),
            velocity: CGPoint(x: 0, y: -5),
            nextTurnAt: Self.now.addingTimeInterval(100)
        )
        let next = BreakRunPhysics.step(
            state, workArea: Self.workArea, size: Self.size,
            now: Self.now, random: { 0.99 }
        )
        #expect(next.position.y == 8)
        #expect(next.velocity.y > 0)
    }

    @Test("the bottom edge reverses vertical travel")
    func bouncesOffBottomEdge() {
        let state = BreakRunPhysics.State(
            position: CGPoint(x: 500, y: 550),
            velocity: CGPoint(x: 0, y: 5),
            nextTurnAt: Self.now.addingTimeInterval(100)
        )
        let next = BreakRunPhysics.step(
            state, workArea: Self.workArea, size: Self.size,
            now: Self.now, random: { 0.99 }
        )
        #expect(next.position.y == 552)
        #expect(next.velocity.y < 0)
    }

    @Test("the pet never leaves the inset work area over a long run")
    func staysInsideOverLongRun() {
        var state = BreakRunPhysics.State(
            position: CGPoint(x: 600, y: 300),
            velocity: BreakRunPhysics.chooseVelocity(random: BreakRunPhysics.systemRandom),
            nextTurnAt: Self.now
        )
        let limits = BreakRunPhysics.limits(workArea: Self.workArea, size: Self.size)
        var clock = Self.now

        // 60 seconds at 16ms.
        for _ in 0..<3750 {
            clock = clock.addingTimeInterval(Constants.breakRunTick)
            state = BreakRunPhysics.step(
                state, workArea: Self.workArea, size: Self.size,
                now: clock, random: BreakRunPhysics.systemRandom
            )
            #expect(state.position.x >= limits.minX)
            #expect(state.position.x <= limits.maxX)
            #expect(state.position.y >= limits.minY)
            #expect(state.position.y <= limits.maxY)
        }
    }

    @Test("a stationary pet still moves when a turn is rolled")
    func turnGivesMotionToAStoppedPet() {
        let state = BreakRunPhysics.State(
            position: CGPoint(x: 600, y: 300),
            velocity: .zero,
            nextTurnAt: Self.now
        )
        // First draw 0.1 < 0.45 triggers the turn, then speed and angle.
        let next = BreakRunPhysics.step(
            state, workArea: Self.workArea, size: Self.size,
            now: Self.now, random: scripted([0.1, 0.5, 0.25, 0.5])
        )
        #expect(next.velocity != .zero)
    }

    // MARK: Turn cadence

    @Test("no turn happens before the turn deadline")
    func noTurnBeforeDeadline() {
        let velocity = CGPoint(x: 4, y: 4)
        let state = BreakRunPhysics.State(
            position: CGPoint(x: 600, y: 300),
            velocity: velocity,
            nextTurnAt: Self.now.addingTimeInterval(1)
        )
        // Even a draw that would pass the probability check is not consulted.
        let next = BreakRunPhysics.step(
            state, workArea: Self.workArea, size: Self.size,
            now: Self.now, random: { 0 }
        )
        #expect(next.velocity == velocity)
        #expect(next.nextTurnAt == state.nextTurnAt, "deadline unchanged")
    }

    @Test("a failed probability roll keeps the heading but refreshes the deadline")
    func failedRollStillRefreshesDeadline() {
        let velocity = CGPoint(x: 4, y: 4)
        let state = BreakRunPhysics.State(
            position: CGPoint(x: 600, y: 300),
            velocity: velocity,
            nextTurnAt: Self.now
        )
        // 0.9 > 0.45 so no turn, then the delay draw.
        let next = BreakRunPhysics.step(
            state, workArea: Self.workArea, size: Self.size,
            now: Self.now, random: scripted([0.9, 0.0])
        )
        #expect(next.velocity == velocity)
        #expect(next.nextTurnAt > state.nextTurnAt, "deadline must advance")
    }

    @Test("the turn delay stays within 350...1200ms")
    func turnDelayBounds() {
        #expect(BreakRunPhysics.nextTurnDelay(random: { 0 }) == 0.350)
        #expect(BreakRunPhysics.nextTurnDelay(random: { 0.999 }) <= 1.200)
        for _ in 0..<100 {
            let delay = BreakRunPhysics.nextTurnDelay(random: BreakRunPhysics.systemRandom)
            #expect(delay >= 0.350 && delay <= 1.200)
        }
    }

    // MARK: Facing and countdown

    @Test("facing follows the heading, with zero counting as right")
    func facingFollowsHeading() {
        #expect(BreakRunPhysics.facing(for: CGPoint(x: 3, y: 0)) == .right)
        #expect(BreakRunPhysics.facing(for: CGPoint(x: -3, y: 0)) == .left)
        #expect(BreakRunPhysics.facing(for: CGPoint(x: 0, y: 5)) == .right)
    }

    @Test("the countdown rounds up and floors at zero")
    func countdownRounding() {
        let endsAt = Self.now.addingTimeInterval(10)
        #expect(BreakRunPhysics.remainingSeconds(until: endsAt, now: Self.now) == 10)
        #expect(BreakRunPhysics.remainingSeconds(
            until: endsAt, now: Self.now.addingTimeInterval(9.2)
        ) == 1)
        #expect(BreakRunPhysics.remainingSeconds(
            until: endsAt, now: Self.now.addingTimeInterval(20)
        ) == 0)
    }
}

@Suite("Break runner", .serialized)
@MainActor
struct BreakRunnerTests {

    private func makeRunner() -> (BreakRunner, TestClock) {
        let clock = TestClock()
        let runner = BreakRunner(clock: clock, random: { 0.5 })
        runner.currentPosition = { CGPoint(x: 600, y: 300) }
        runner.workArea = { _ in GlobalRect(x: 0, y: 0, width: 1440, height: 900) }
        return (runner, clock)
    }

    @Test("starting reports an initial countdown and a facing")
    func startReportsInitialState() {
        let (runner, _) = makeRunner()
        var countdowns: [Int] = []
        var facings: [PetFacing] = []
        runner.onCountdown = { countdowns.append($0) }
        runner.onFacingChange = { facings.append($0) }

        runner.start(duration: 60)
        defer { runner.cancel() }

        #expect(runner.isRunning)
        #expect(countdowns == [60])
        #expect(facings.count == 1)
    }

    @Test("ticking moves the pet")
    func tickMoves() {
        let (runner, clock) = makeRunner()
        var positions: [CGPoint] = []
        runner.onMove = { positions.append($0) }

        runner.start(duration: 60)
        defer { runner.cancel() }

        for _ in 0..<10 {
            clock.advance(by: Constants.breakRunTick)
            runner.tick()
        }
        #expect(positions.count == 10)
        #expect(positions.first != positions.last, "the pet should have travelled")
    }

    @Test("the countdown decreases as the clock advances")
    func countdownDecreases() {
        let (runner, clock) = makeRunner()
        runner.start(duration: 60)
        defer { runner.cancel() }

        #expect(runner.remainingSeconds == 60)
        clock.advance(by: 30)
        #expect(runner.remainingSeconds == 30)
        clock.advance(by: 40)
        #expect(runner.remainingSeconds == 0)
    }

    @Test("finishing reports completion once and stops the run")
    func finishReportsOnce() {
        let (runner, _) = makeRunner()
        var finishes = 0
        runner.onFinish = { finishes += 1 }

        runner.start(duration: 60)
        runner.finish()
        runner.finish()

        #expect(finishes == 1)
        #expect(!runner.isRunning)
    }

    @Test("cancelling stops the run without reporting completion")
    func cancelDoesNotReportFinish() {
        let (runner, _) = makeRunner()
        var finishes = 0
        runner.onFinish = { finishes += 1 }

        runner.start(duration: 60)
        runner.cancel()

        #expect(finishes == 0)
        #expect(!runner.isRunning)
    }

    @Test("ticking after the run ends does nothing")
    func tickAfterFinishIsInert() {
        let (runner, _) = makeRunner()
        var positions: [CGPoint] = []
        runner.onMove = { positions.append($0) }

        runner.start(duration: 60)
        runner.finish()
        runner.tick()
        #expect(positions.isEmpty)
    }

    @Test("the real timers finish a short run on their own")
    func realTimersFinishRun() async throws {
        // A live clock so the finish timer is genuine.
        let runner = BreakRunner(clock: SystemClock(), random: { 0.5 })
        runner.currentPosition = { CGPoint(x: 600, y: 300) }
        runner.workArea = { _ in GlobalRect(x: 0, y: 0, width: 1440, height: 900) }

        var finished = false
        var moves = 0
        runner.onFinish = { finished = true }
        runner.onMove = { _ in moves += 1 }

        runner.start(duration: 0.3)
        try await Task.sleep(for: .milliseconds(600))

        #expect(finished, "the finish timer should have fired")
        // The exact tick count depends on run-loop scheduling under test load, so
        // assert only that the 16ms movement timer ran — not how often.
        #expect(moves > 0, "the movement timer should have ticked, got \(moves)")
    }
}

@Suite("Break flow", .serialized)
@MainActor
struct BreakFlowTests {

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

    private func actionIDs(_ bubble: SpeechBubble?) -> [String] {
        bubble?.actions.map(\.id) ?? []
    }

    @Test("a due break shows the prompt with three actions")
    func breakPromptShowsActions() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        clock.advance(by: 46 * 60)
        state.scheduler.tick()

        #expect(state.petState == .breakPrompt)
        #expect(state.blockingMode == .breakPrompt)
        #expect(state.petWindow.isBubbleVisible)
        #expect(actionIDs(state.petWindow.currentBubble) == [
            BubbleActionID.breakDone,
            BubbleActionID.breakSnooze,
            BubbleActionID.breakMute
        ])
        // The prompt's primary action is the one that starts the run.
        #expect(state.petWindow.currentBubble?.actions.first?.kind == .primary)
        #expect(state.petWindow.currentBubble?.actions.last?.kind == .danger)
    }

    @Test("taking the break increments the counter and starts the run")
    func takingBreakStartsRun() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        #expect(state.petState == .breakPrompt)

        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakDone)

        #expect(state.stats.breaksTaken == 1)
        #expect(state.persistence.currentStats.breaksTaken == 1)
        #expect(state.petState == .breakRunning)
        #expect(state.blockingMode == .breakRun)
        #expect(state.breakRunner.isRunning)
        // The countdown bubble replaces the prompt.
        #expect(state.petWindow.currentBubble?.id == BubbleID.breakRun)
        #expect(actionIDs(state.petWindow.currentBubble) == [BubbleActionID.breakRunDone])
    }

    @Test("the countdown bubble keeps one phrasing for the whole run")
    func countdownPhrasingIsStable() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakDone)

        // The message differs only in its number, never in its wording.
        let first = try #require(state.petWindow.currentBubble?.message)
        clock.advance(by: 5)
        state.breakRunner.tick()
        // Force a countdown refresh the way the 1s timer would.
        state.breakRunner.onCountdown(state.breakRunner.remainingSeconds ?? 0)
        let second = try #require(state.petWindow.currentBubble?.message)

        let strip: (String) -> String = { $0.filter { !$0.isNumber } }
        #expect(strip(first) == strip(second), "phrasing changed mid-run")
        #expect(first != second, "the number should have counted down")
    }

    @Test("the run cannot be dragged")
    func runBlocksDragging() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakDone)

        state.petWindow.startDrag(offset: .zero)
        #expect(!state.petWindow.isDragging, "the break run owns the pet's position")
    }

    @Test("finishing the run celebrates and schedules the next break")
    func finishingRunSchedulesNextBreak() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakDone)
        #expect(state.scheduler.breakDueAt == nil, "the run clears the pending break")

        state.finishBreakRun()

        #expect(state.petState == .breakDone)
        #expect(state.blockingMode == nil)
        #expect(!state.breakRunner.isRunning)
        #expect(state.petWindow.currentBubble?.id == BubbleID.breakRunComplete)
        #expect(state.petWindow.currentBubble?.autoDismissAfter
            == Constants.breakRunCompleteBubbleDuration)
        #expect(state.scheduler.breakDueAt != nil, "the next break is scheduled from here")
    }

    @Test("the run's done button finishes it early")
    func runDoneButtonFinishes() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakDone)
        #expect(state.breakRunner.isRunning)

        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakRunDone)
        #expect(!state.breakRunner.isRunning)
        #expect(state.petState == .breakDone)
    }

    @Test("snoozing settles the pet and reschedules 10 minutes out")
    func snoozeReschedules() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakSnooze)

        #expect(state.petState == .idle)
        #expect(state.blockingMode == nil)
        #expect(!state.petWindow.isBubbleVisible)
        let due = try #require(state.scheduler.breakDueAt)
        #expect(due.timeIntervalSince(clock.now) == Constants.breakSnooze)
    }

    @Test("muting silences breaks for the day and the pet sulks")
    func muteSilencesBreaks() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()
        // Isolate the break reminder: muting breaks must not affect hydration,
        // which would otherwise come due during the long advance below.
        state.updateSettings { $0.hydrationReminderEnabled = false }

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakMute)

        #expect(state.petState == .sad)
        #expect(state.stateMachine.breakMutedToday)
        #expect(state.scheduler.breakDueAt == nil)
        #expect(state.petWindow.currentBubble?.id == BubbleID.breakMuted)
        #expect(state.petWindow.currentBubble?.autoDismissAfter
            == Constants.breakMutedBubbleDuration)

        // No further break fires, however much time passes.
        clock.advance(by: 5 * 60 * 60)
        state.scheduler.tick()
        #expect(state.petState == .sad, "a muted break must not re-prompt")
    }

    @Test("muting breaks leaves hydration reminders working")
    func muteDoesNotSilenceHydration() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakMute)
        #expect(state.stateMachine.breakMutedToday)

        // Past the 90-minute hydration interval.
        clock.advance(by: 91 * 60)
        state.scheduler.tick()
        #expect(state.petState == .hydrationPrompt, "hydration is independent of the break mute")
    }

    @Test("midnight clears the mute and reschedules")
    func midnightClearsMute() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakMute)
        #expect(state.stateMachine.breakMutedToday)

        state.scheduler.onMidnight()
        #expect(!state.stateMachine.breakMutedToday)
        #expect(state.scheduler.breakDueAt != nil)
    }

    @Test("resetting today clears the mute too")
    func resetClearsMute() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakDone)
        #expect(state.stats.breaksTaken == 1)

        state.resetTodayStats()
        #expect(state.stats.breaksTaken == 0)
        #expect(!state.stateMachine.breakMutedToday)
    }

    @Test("the run uses the configured duration")
    func runUsesConfiguredDuration() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()
        state.updateSettings { $0.breakRunDurationSeconds = 25 }

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakDone)

        #expect(state.breakRunner.remainingSeconds == 25)
    }

    @Test("the pet stays on screen throughout a run")
    func runKeepsPetOnScreen() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.petWindow.contentView.bubbleView.onAction(BubbleActionID.breakDone)

        for _ in 0..<300 {
            clock.advance(by: Constants.breakRunTick)
            state.breakRunner.tick()

            let bounds = state.petWindow.globalBounds
            let clamped = DisplayGeometry.visibleBounds(
                displays: ScreenBridge.displays,
                primaryDisplay: ScreenBridge.primaryDisplay,
                bounds: bounds
            )
            #expect(clamped == bounds, "pet left the work area: \(bounds)")
        }
    }
}
