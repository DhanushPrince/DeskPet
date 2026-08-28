import AppKit
import Foundation
import Testing
@testable import DeskPetKit

@Suite("Version comparison")
struct VersionComparisonTests {
    @Test("a newer patch is greater")
    func newerPatch() {
        #expect(Versions.compare("0.1.4", "0.1.3") == 1)
    }

    @Test("v-prefixed tags compare equal to the bare version")
    func vPrefix() {
        #expect(Versions.compare("v1.2.0", "1.2.0") == 0)
    }

    @Test("a prerelease is lower than the matching stable")
    func prereleaseLower() {
        #expect(Versions.compare("1.0.0-beta.1", "1.0.0") == -1)
        #expect(Versions.compare("1.0.0", "1.0.0-beta.1") == 1)
    }
}

@Suite("GitHub release payload")
struct UpdateCheckerParseTests {
    @Test("a newer tag is available")
    func newerTagAvailable() throws {
        let data = Data("""
        {"tag_name":"v9.9.9","html_url":"https://github.com/DhanushPrince/DeskPet/releases/tag/v9.9.9"}
        """.utf8)
        let result = GitHubUpdateChecker.parse(data, currentVersion: "1.0.0")
        #expect(result.status == .available)
        #expect(result.latestVersion == "v9.9.9")
        #expect(result.releaseURL.absoluteString.hasSuffix("/v9.9.9"))
    }

    @Test("the same version is up to date")
    func sameVersionUpToDate() {
        let data = Data(#"{"tag_name":"1.0.0"}"#.utf8)
        let result = GitHubUpdateChecker.parse(data, currentVersion: "1.0.0")
        #expect(result.status == .upToDate)
    }

    @Test("a missing tag is an error")
    func missingTag() {
        let data = Data(#"{}"#.utf8)
        let result = GitHubUpdateChecker.parse(data, currentVersion: "1.0.0")
        #expect(result.status == .error)
    }
}

final class FakeUpdateChecker: UpdateChecking, @unchecked Sendable {
    var result: UpdateCheckResult

    init(result: UpdateCheckResult) {
        self.result = result
    }

    func check(current: UpdateCheckResult) async -> UpdateCheckResult {
        result
    }
}

@Suite("Update check wiring", .serialized)
@MainActor
struct UpdateCheckWiringTests {
    private func makeState(
        checker: FakeUpdateChecker
    ) -> (AppState, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let state = AppState(
            persistence: persistence,
            clock: TestClock(),
            random: { 0.5 },
            updateChecker: checker
        )
        return (state, {
            state.stop()
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("an available result updates the settings message and shows a bubble")
    func availableShowsBubble() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let checker = FakeUpdateChecker(result: UpdateCheckResult(
            status: .available,
            currentVersion: "1.0.0",
            latestVersion: "9.9.9",
            releaseURL: Constants.releasesURL
        ))
        let (state, cleanup) = makeState(checker: checker)
        defer { cleanup() }
        state.start()

        await state.performUpdateCheck(notifyAvailable: true)

        #expect(state.lastUpdateCheck.status == .available)
        #expect(state.updateStatusMessage == Strings.SettingsLabels.updateAvailable("9.9.9"))
        #expect(state.petWindow.currentBubble?.id == BubbleID.updateAvailable)
        #expect(state.petState == .happy)
    }

    @Test("an up-to-date result does not show a bubble")
    func upToDateSilent() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let checker = FakeUpdateChecker(result: UpdateCheckResult(
            status: .upToDate,
            currentVersion: "1.0.0",
            latestVersion: "1.0.0"
        ))
        let (state, cleanup) = makeState(checker: checker)
        defer { cleanup() }

        await state.performUpdateCheck(notifyAvailable: true)

        #expect(state.updateStatusMessage == Strings.SettingsLabels.updateCurrent("1.0.0"))
        #expect(state.petWindow.currentBubble == nil)
    }
}
