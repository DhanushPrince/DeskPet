import Foundation
import Testing
@testable import DeskPetKit

@Suite("Pet state machine")
struct PetStateMachineTests {

    /// All blocking modes plus the unblocked case.
    static let allModes: [BlockingMode?] = [nil, .breakPrompt, .breakRun, .hydration, .focusWarning]

    /// Drives the machine into a given blocking mode using its own transitions,
    /// so no test depends on private state being writable.
    private func machine(
        in mode: BlockingMode?,
        focusActive: Bool = false,
        clock: TestClock = TestClock()
    ) -> PetStateMachine {
        let machine = PetStateMachine(clock: clock)
        if focusActive {
            machine.startFocus()
        }
        switch mode {
        case nil:
            break
        case .breakPrompt:
            // A scheduled reminder is refused while focused, so use the manual
            // path, which is only blocked by breakRun and focusWarning.
            machine.triggerBreakReminder(fromDemo: true)
        case .breakRun:
            machine.startBreakRun()
        case .hydration:
            machine.triggerHydrationReminder(fromDemo: true)
        case .focusWarning:
            machine.triggerFocusWarning()
        }
        return machine
    }

    // MARK: Initial state

    @Test("the machine starts idle and unblocked")
    func initialState() {
        let machine = PetStateMachine()
        #expect(machine.state == .idle)
        #expect(machine.blockingMode == nil)
        #expect(!machine.focusActive)
        #expect(!machine.breakMutedToday)
        #expect(machine.longTermState == .idle)
        #expect(machine.allowsOverdueReminder)
    }

    @Test("state changes are always reported, even when redundant")
    func redundantStateChangesNotify() {
        let machine = PetStateMachine()
        var reported: [PetState] = []
        machine.onStateChange = { reported.append($0) }

        machine.setState(.idle)
        machine.setState(.idle)
        #expect(reported == [.idle, .idle])
    }

    // MARK: Scheduled break reminder

    @Test("a scheduled break reminder is only accepted when unblocked and unfocused")
    func scheduledBreakGuards() {
        for mode in Self.allModes {
            let machine = machine(in: mode)
            let accepted = machine.triggerBreakReminder()
            #expect(accepted == (mode == nil), "mode \(String(describing: mode))")
        }
    }

    @Test("a scheduled break reminder is suppressed during focus")
    func scheduledBreakSuppressedByFocus() {
        let machine = PetStateMachine()
        machine.startFocus()
        #expect(!machine.triggerBreakReminder())
        #expect(machine.state == .focusGuard)
        #expect(machine.blockingMode == nil)
    }

    @Test("a muted break reminder is suppressed even when otherwise free")
    func mutedBreakSuppressed() {
        let machine = PetStateMachine()
        machine.muteBreaksForToday()
        #expect(machine.state == .sad)
        #expect(machine.breakMutedToday)
        #expect(!machine.triggerBreakReminder())

        machine.resetMuteForNewDay()
        #expect(machine.triggerBreakReminder())
        #expect(machine.state == .breakPrompt)
    }

    @Test("an accepted break reminder blocks and shows the prompt")
    func breakReminderAccepted() {
        let machine = PetStateMachine()
        var visibleRequests = 0
        machine.onRequestVisible = { visibleRequests += 1 }

        #expect(machine.triggerBreakReminder())
        #expect(machine.state == .breakPrompt)
        #expect(machine.blockingMode == .breakPrompt)
        #expect(visibleRequests == 1)
        #expect(!machine.allowsOverdueReminder)
    }

    // MARK: Manual break reminder

    @Test("a manual break reminder ignores mute and focus but not breakRun or focusWarning")
    func manualBreakGuards() {
        for mode in Self.allModes {
            let machine = machine(in: mode)
            let accepted = machine.triggerBreakReminder(fromDemo: true)
            let expected = !(mode == .breakRun || mode == .focusWarning)
            #expect(accepted == expected, "mode \(String(describing: mode))")
        }

        // Mute and focus do not stop a manual trigger.
        let muted = PetStateMachine()
        muted.muteBreaksForToday()
        #expect(muted.triggerBreakReminder(fromDemo: true))

        let focused = PetStateMachine()
        focused.startFocus()
        #expect(focused.triggerBreakReminder(fromDemo: true))
    }

    // MARK: Break run

    @Test("the break run takes over and finishing releases it")
    func breakRunLifecycle() {
        let machine = PetStateMachine()
        machine.triggerBreakReminder()
        machine.startBreakRun()

        #expect(machine.state == .breakRunning)
        #expect(machine.blockingMode == .breakRun)

        machine.finishBreakRun()
        #expect(machine.state == .breakDone)
        #expect(machine.blockingMode == nil)
        #expect(machine.allowsOverdueReminder)
    }

    // MARK: Hydration

    @Test("a scheduled hydration reminder is only accepted when unblocked and unfocused")
    func scheduledHydrationGuards() {
        for mode in Self.allModes {
            let machine = machine(in: mode)
            let accepted = machine.triggerHydrationReminder()
            #expect(accepted == (mode == nil), "mode \(String(describing: mode))")
        }

        let focused = PetStateMachine()
        focused.startFocus()
        #expect(!focused.triggerHydrationReminder())
    }

    @Test("a manual hydration reminder may replace a break prompt")
    func manualHydrationGuards() {
        for mode in Self.allModes {
            let machine = machine(in: mode)
            let accepted = machine.triggerHydrationReminder(fromDemo: true)
            let expected = mode != .focusWarning && mode != .breakRun
            #expect(accepted == expected, "mode \(String(describing: mode))")
            if accepted {
                #expect(machine.blockingMode == .hydration)
                #expect(machine.state == .hydrationPrompt)
            }
        }
    }

    @Test("the drinking sequence releases the block then completes")
    func drinkingSequence() {
        let machine = PetStateMachine()
        machine.triggerHydrationReminder()
        #expect(machine.blockingMode == .hydration)

        machine.beginDrinking()
        #expect(machine.state == .drinking)
        #expect(machine.blockingMode == nil)

        #expect(machine.finishDrinking())
        #expect(machine.state == .hydrationDone)
    }

    @Test("the drinking sequence aborts if something else takes over")
    func drinkingInterrupted() {
        let machine = PetStateMachine()
        machine.triggerHydrationReminder()
        machine.beginDrinking()

        // A focus warning arrives during the drinking animation.
        machine.triggerFocusWarning()
        #expect(!machine.finishDrinking())
        #expect(machine.state == .focusAlert)
    }

    // MARK: Focus mode

    @Test("focus starts only when unblocked and not already focused")
    func focusStartGuards() {
        for mode in Self.allModes {
            let machine = machine(in: mode)
            let accepted = machine.startFocus()
            #expect(accepted == (mode == nil), "mode \(String(describing: mode))")
        }

        let machine = PetStateMachine()
        #expect(machine.startFocus())
        #expect(!machine.startFocus(), "already focused")
    }

    @Test("starting focus enters focusGuard and changes the long-term state")
    func focusStartState() {
        let machine = PetStateMachine()
        #expect(machine.startFocus())
        #expect(machine.state == .focusGuard)
        #expect(machine.focusActive)
        #expect(machine.longTermState == .focusGuard)
        #expect(machine.focusStartedAt != nil)
    }

    @Test("stopping focus credits elapsed minutes, rounded, with a one-minute floor")
    func focusStopCreditsMinutes() {
        let clock = TestClock()
        let machine = PetStateMachine(clock: clock)
        machine.startFocus()

        clock.advance(by: 25 * 60)
        #expect(machine.stopFocus() == 25)
        #expect(machine.state == .focusDone)
        #expect(!machine.focusActive)
        #expect(machine.focusStartedAt == nil)
        #expect(machine.longTermState == .idle)
    }

    @Test("a very short focus session still credits one minute")
    func focusStopFloor() {
        let clock = TestClock()
        let machine = PetStateMachine(clock: clock)
        machine.startFocus()
        clock.advance(by: 3)
        #expect(machine.stopFocus() == 1)
    }

    @Test("focus minutes round to nearest")
    func focusStopRounding() {
        let clock = TestClock()
        let machine = PetStateMachine(clock: clock)

        machine.startFocus()
        clock.advance(by: 90)          // 1.5 min → 2
        #expect(machine.stopFocus() == 2)

        machine.startFocus()
        clock.advance(by: 80)          // 1.33 min → 1
        #expect(machine.stopFocus() == 1)
    }

    @Test("stopping focus when none is running reports nothing")
    func focusStopWithoutSession() {
        let machine = PetStateMachine()
        #expect(machine.stopFocus() == nil)
        #expect(machine.state == .idle)
    }

    // MARK: Focus warning

    @Test("a focus warning is blocked only by the break run")
    func focusWarningGuards() {
        for mode in Self.allModes {
            let machine = machine(in: mode)
            let accepted = machine.triggerFocusWarning()
            #expect(accepted == (mode != .breakRun), "mode \(String(describing: mode))")
        }
    }

    @Test("a focus warning overrides a hydration prompt")
    func focusWarningOverridesHydration() {
        let machine = PetStateMachine()
        machine.triggerHydrationReminder()
        #expect(machine.triggerFocusWarning())
        #expect(machine.blockingMode == .focusWarning)
        #expect(machine.state == .focusAlert)
    }

    @Test("a focus warning outside a session starts one")
    func focusWarningStartsFocus() {
        let machine = PetStateMachine()
        #expect(machine.triggerFocusWarning())
        #expect(machine.focusActive)
        #expect(machine.blockingMode == .focusWarning)
        #expect(machine.state == .focusAlert)
    }

    @Test("a focus warning during another prompt does not start a session")
    func focusWarningDuringPromptDoesNotStartFocus() {
        // Reproduces the Electron ordering: startFocusMode() is attempted while
        // the break prompt still owns blockingMode, so it returns early.
        let machine = PetStateMachine()
        machine.triggerBreakReminder()
        #expect(machine.blockingMode == .breakPrompt)

        #expect(machine.triggerFocusWarning())
        #expect(!machine.focusActive, "focus must not activate from a blocked warning")
        #expect(machine.blockingMode == .focusWarning)
        #expect(machine.state == .focusAlert)
    }

    @Test("returning to focus clears the warning")
    func returnToFocus() {
        let machine = PetStateMachine()
        machine.triggerFocusWarning()
        machine.returnToFocus()
        #expect(machine.blockingMode == nil)
        #expect(machine.state == .focusGuard)
    }

    // MARK: Resume and happy feedback

    @Test("resuming settles to idle, or focusGuard while focused")
    func resumeRespectsFocus() {
        let idle = PetStateMachine()
        idle.triggerBreakReminder()
        #expect(idle.resumeLongTermState() == .idle)
        #expect(idle.blockingMode == nil)

        let focused = PetStateMachine()
        focused.startFocus()
        focused.triggerFocusWarning()
        #expect(focused.resumeLongTermState() == .focusGuard)
    }

    @Test("resuming clears any blocking mode", arguments: PetStateMachineTests.allModes)
    func resumeClearsAnyMode(mode: BlockingMode?) {
        let machine = machine(in: mode)
        machine.resumeLongTermState()
        #expect(machine.blockingMode == nil)
    }

    @Test("happy feedback is refused while blocked")
    func happyFeedbackGuards() {
        for mode in Self.allModes {
            let machine = machine(in: mode)
            let accepted = machine.beginHappyFeedback()
            #expect(accepted == (mode == nil), "mode \(String(describing: mode))")
        }
    }

    @Test("happy feedback returns to the long-term state")
    func happyFeedbackReturnState() {
        let idle = PetStateMachine()
        #expect(idle.beginHappyFeedback())
        #expect(idle.state == .happy)
        #expect(idle.settleAfterTransientState())
        #expect(idle.state == .idle)

        let focused = PetStateMachine()
        focused.startFocus()
        #expect(focused.beginHappyFeedback())
        #expect(focused.settleAfterTransientState())
        #expect(focused.state == .focusGuard)
    }

    @Test("settling is skipped if something took over during the animation")
    func settleInterrupted() {
        let machine = PetStateMachine()
        machine.beginHappyFeedback()
        machine.triggerFocusWarning()
        #expect(!machine.settleAfterTransientState())
        #expect(machine.state == .focusAlert)
    }

    // MARK: Overdue gating

    @Test("overdue reminders are gated by blocking mode and focus")
    func overdueGating() {
        for mode in Self.allModes {
            let machine = machine(in: mode)
            #expect(machine.allowsOverdueReminder == (mode == nil), "mode \(String(describing: mode))")
        }

        let focused = PetStateMachine()
        focused.startFocus()
        #expect(!focused.allowsOverdueReminder)
    }

    // MARK: Full break flow

    @Test("the break flow returns the pet to idle")
    func fullBreakFlow() {
        let machine = PetStateMachine()
        var states: [PetState] = []
        machine.onStateChange = { states.append($0) }

        #expect(machine.triggerBreakReminder())
        machine.startBreakRun()
        machine.finishBreakRun()
        #expect(machine.settleAfterTransientState())

        #expect(states == [.breakPrompt, .breakRunning, .breakDone, .idle])
        #expect(machine.blockingMode == nil)
    }

    @Test("the hydration flow returns to focusGuard when focused")
    func fullHydrationFlowDuringFocus() {
        let machine = PetStateMachine()
        machine.startFocus()
        // Scheduled reminders are suppressed during focus, but `startFocus`
        // leaves the blocking mode clear, so a manual trigger is accepted.
        #expect(machine.triggerHydrationReminder(fromDemo: true))
        machine.beginDrinking()
        #expect(machine.finishDrinking())
        #expect(machine.settleAfterTransientState())
        #expect(machine.state == .focusGuard)
    }
}
