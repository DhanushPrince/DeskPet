import Foundation

/// Owns the pet's state, the active blocking mode, and focus session status.
///
/// Ported from the module-level state and trigger functions in `main.ts`. The
/// machine deliberately performs no side effects: it decides transitions and
/// reports whether each was accepted, leaving bubbles, statistics, and timers to
/// the caller. That keeps every guard condition testable without a run loop.
public final class PetStateMachine {
    // MARK: Observable state

    public private(set) var state: PetState = .idle
    public private(set) var blockingMode: BlockingMode?
    public private(set) var focusActive = false
    /// Silences break reminders until the next day. Held in memory by the
    /// Electron build; Task 11 resets it at midnight.
    public private(set) var breakMutedToday = false
    public private(set) var focusStartedAt: Date?

    /// Called on every state change, including redundant assignments — the
    /// Electron build re-sent `pet:set-state` unconditionally, which is what
    /// made the renderer re-roll its animation variant.
    public var onStateChange: ((PetState) -> Void)?
    /// Triggers call this before showing a prompt, mirroring
    /// `ensurePetWindowVisible()`.
    public var onRequestVisible: (() -> Void)?

    private let clock: DeskPetClock

    public init(clock: DeskPetClock = SystemClock()) {
        self.clock = clock
    }

    // MARK: - State assignment

    /// Mirrors `setPetState`: always notifies, even when the value is unchanged.
    public func setState(_ next: PetState) {
        state = next
        onStateChange?(next)
    }

    /// The state the pet settles into between events.
    public var longTermState: PetState {
        focusActive ? .focusGuard : .idle
    }

    /// Whether a due reminder may be surfaced right now. Combined with the
    /// scheduler's due dates to reproduce `showOverdueReminder`.
    public var allowsOverdueReminder: Bool {
        blockingMode == nil && !focusActive
    }

    // MARK: - Break reminder

    /// Ported from `triggerBreakReminder`.
    ///
    /// A scheduled reminder is suppressed by the mute flag, by any blocking
    /// mode, and by an active focus session. A manually triggered one bypasses
    /// all of those except the break run and a focus warning.
    @discardableResult
    public func triggerBreakReminder(fromDemo: Bool = false) -> Bool {
        if fromDemo {
            if blockingMode == .focusWarning || blockingMode == .breakRun { return false }
        } else {
            if breakMutedToday { return false }
            if blockingMode != nil || focusActive { return false }
        }

        onRequestVisible?()
        blockingMode = .breakPrompt
        setState(.breakPrompt)
        return true
    }

    /// Ported from the `break:mute` action: the pet looks sad and break
    /// reminders stop for the day.
    public func muteBreaksForToday() {
        breakMutedToday = true
        blockingMode = nil
        setState(.sad)
    }

    /// Ported from the midnight rollover requirement; the Electron build only
    /// cleared this on relaunch or an explicit stats reset.
    public func resetMuteForNewDay() {
        breakMutedToday = false
    }

    /// Ported from `startBreakRun`. Always accepted: it is only reachable from
    /// the break prompt's own action.
    public func startBreakRun() {
        onRequestVisible?()
        blockingMode = .breakRun
        setState(.breakRunning)
    }

    /// Ported from `finishBreakRun`, up to the point where the caller schedules
    /// the next reminder and the return-to-idle delay.
    public func finishBreakRun() {
        blockingMode = nil
        setState(.breakDone)
    }

    // MARK: - Hydration reminder

    /// Ported from `triggerHydrationReminder`. Unlike the break reminder there
    /// is no mute. A scheduled trigger is blocked by any mode or focus; a demo
    /// trigger matches the break demo and may replace a break/hydration prompt
    /// (only a focus warning or an active break run refuses it).
    @discardableResult
    public func triggerHydrationReminder(fromDemo: Bool = false) -> Bool {
        if fromDemo {
            if blockingMode == .focusWarning || blockingMode == .breakRun { return false }
        } else {
            if blockingMode != nil || focusActive { return false }
        }

        onRequestVisible?()
        blockingMode = .hydration
        setState(.hydrationPrompt)
        return true
    }

    /// Ported from the `hydration:done` action: the blocking mode is released
    /// before the drinking animation plays.
    public func beginDrinking() {
        blockingMode = nil
        setState(.drinking)
    }

    /// Second stage of the hydration sequence, skipped if something else has
    /// taken over in the meantime.
    @discardableResult
    public func finishDrinking() -> Bool {
        guard blockingMode == nil else { return false }
        setState(.hydrationDone)
        return true
    }

    // MARK: - Focus mode

    /// Ported from `startFocusMode`. Refused while another blocking mode owns
    /// the pet, which is why a focus warning arriving during a break prompt does
    /// not start a session.
    @discardableResult
    public func startFocus() -> Bool {
        guard !focusActive, blockingMode == nil else { return false }

        onRequestVisible?()
        focusActive = true
        focusStartedAt = clock.now
        blockingMode = nil
        setState(.focusGuard)
        return true
    }

    /// Ported from `stopFocusMode`. Returns the minutes to credit, or nil when
    /// no session was running.
    @discardableResult
    public func stopFocus() -> Int? {
        guard focusActive else { return nil }

        let startedAt = focusStartedAt ?? clock.now
        let elapsed = clock.now.timeIntervalSince(startedAt)
        // `Math.max(1, Math.round(elapsed / 60000))`: any session counts for at
        // least a minute.
        let minutes = max(1, Int(DisplayGeometry.jsRound(elapsed / 60)))

        focusActive = false
        focusStartedAt = nil
        blockingMode = nil
        setState(.focusDone)
        return minutes
    }

    /// Ported from `triggerFocusWarning`.
    ///
    /// Only the break run blocks it; it overrides a break or hydration prompt.
    /// Note the ordering faithfully reproduced here: `startFocus` is attempted
    /// *before* the blocking mode is set, so a warning raised during another
    /// prompt sets `focusWarning` without activating focus.
    @discardableResult
    public func triggerFocusWarning() -> Bool {
        guard blockingMode != .breakRun else { return false }

        onRequestVisible?()
        if !focusActive {
            startFocus()
        }
        blockingMode = .focusWarning
        setState(.focusAlert)
        return true
    }

    /// Ported from the `focus:back` action.
    public func returnToFocus() {
        blockingMode = nil
        setState(.focusGuard)
    }

    // MARK: - Returning to rest

    /// Ported from `resumeLongTermState`, minus the overdue-reminder check the
    /// caller performs first. Returns the state settled into.
    @discardableResult
    public func resumeLongTermState() -> PetState {
        blockingMode = nil
        let next = longTermState
        setState(next)
        return next
    }

    /// Ported from `happyFeedback`. Refused while any blocking mode is active,
    /// so clicking the pet mid-prompt does nothing.
    @discardableResult
    public func beginHappyFeedback() -> Bool {
        guard blockingMode == nil else { return false }
        setState(.happy)
        return true
    }

    /// Completion half of `happyFeedback` and of the other timed sequences:
    /// settle back unless something took over while the animation played.
    @discardableResult
    public func settleAfterTransientState() -> Bool {
        guard blockingMode == nil else { return false }
        setState(longTermState)
        return true
    }

    // MARK: - Test and debug support

    /// Forces state without touching blocking mode, for the debug state cycler.
    public func debugForceState(_ next: PetState) {
        setState(next)
    }
}
