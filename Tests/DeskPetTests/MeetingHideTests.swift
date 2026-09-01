import AppKit
import Foundation
import Testing
@testable import DeskPetKit

@Suite("Teams call detector")
struct TeamsCallDetectorTests {
    @Test("the Teams call assertion name matches")
    func assertionNameMatches() {
        #expect(
            TeamsCallDetector.isInCall(assertionNames: [
                "Microsoft Teams Call in progress"
            ])
        )
        #expect(
            TeamsCallDetector.isInCall(assertionNames: [
                "pid 40742(MSTeams): NoDisplaySleepAssertion named: \"Microsoft Teams Call in progress\""
            ])
        )
    }

    @Test("unrelated assertions are ignored")
    func unrelatedIgnored() {
        #expect(
            !TeamsCallDetector.isInCall(assertionNames: [
                "Electron",
                "com.apple.metadata.mds.power",
                "Prevent sleep while display is on"
            ])
        )
        #expect(!TeamsCallDetector.isInCall(assertionNames: []))
    }
}

@Suite("Meeting hide", .serialized)
@MainActor
struct MeetingHideIntegrationTests {
    private final class CallBox: @unchecked Sendable {
        var inCall = false
    }

    private func makeState(
        box: CallBox = CallBox()
    ) -> (AppState, CallBox, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let state = AppState(
            persistence: persistence,
            clock: TestClock(),
            random: { 0.5 },
            teamsCallActive: { box.inCall }
        )
        return (state, box, {
            state.stop()
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("a Teams call assertion hides the pet without the sticky hide flag")
    func callHidesWithoutStickyFlag() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, box, cleanup) = makeState()
        defer { cleanup() }

        state.start()
        #expect(state.petVisible)
        #expect(state.settings.hidePetDuringMeetings)

        box.inCall = true
        state.meetingHideWatcher.checkNow()

        #expect(!state.petVisible)
        #expect(state.hiddenForMeeting)
        #expect(!state.petHiddenByUser)
        #expect(!state.persistence.petHiddenByUser)
    }

    @Test("ending the call shows the pet again")
    func callEndShowsPet() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, box, cleanup) = makeState()
        defer { cleanup() }

        state.start()
        box.inCall = true
        state.meetingHideWatcher.checkNow()
        #expect(!state.petVisible)

        box.inCall = false
        state.meetingHideWatcher.checkNow()
        #expect(state.petVisible)
        #expect(!state.hiddenForMeeting)
    }

    @Test("a user-hidden pet stays hidden after the call ends")
    func userHiddenStaysHidden() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, box, cleanup) = makeState()
        defer { cleanup() }

        state.start()
        state.hidePet()

        box.inCall = true
        state.meetingHideWatcher.checkNow()
        box.inCall = false
        state.meetingHideWatcher.checkNow()

        #expect(!state.petVisible)
        #expect(state.petHiddenByUser)
        #expect(!state.hiddenForMeeting)
    }

    @Test("a reminder cannot unhide the pet during a call")
    func reminderRespectsMeetingHide() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, box, cleanup) = makeState()
        defer { cleanup() }

        state.start()
        box.inCall = true
        state.meetingHideWatcher.checkNow()

        state.stateMachine.triggerBreakReminder()
        #expect(!state.petVisible)
        #expect(!state.petHiddenByUser)
    }

    @Test("turning the setting off restores the pet")
    func disablingSettingShowsPet() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, box, cleanup) = makeState()
        defer { cleanup() }

        state.start()
        box.inCall = true
        state.meetingHideWatcher.checkNow()
        #expect(!state.petVisible)

        state.updateSettings { $0.hidePetDuringMeetings = false }
        #expect(state.petVisible)
        #expect(!state.hiddenForMeeting)
        #expect(!state.meetingHideWatcher.isPolling)
    }
}
