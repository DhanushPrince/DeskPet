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
        #expect(result.dmgURL == Constants.dmgDownloadURL)
    }

    @Test("a DeskPet.dmg asset supplies URL and size")
    func dmgAssetParsed() {
        let data = Data("""
        {
          "tag_name":"v9.9.9",
          "html_url":"https://github.com/DhanushPrince/DeskPet/releases/tag/v9.9.9",
          "assets":[{
            "name":"DeskPet.dmg",
            "size":12345,
            "browser_download_url":"https://github.com/DhanushPrince/DeskPet/releases/download/v9.9.9/DeskPet.dmg"
          }]
        }
        """.utf8)
        let result = GitHubUpdateChecker.parse(data, currentVersion: "1.0.0")
        #expect(result.status == .available)
        #expect(result.dmgByteCount == 12345)
        #expect(result.dmgURL?.lastPathComponent == "DeskPet.dmg")
        #expect(result.dmgURL?.absoluteString.contains("v9.9.9") == true)
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

@Suite("Update installer cache")
struct UpdateInstallerCacheTests {
    private func makeInstaller() -> (FileUpdateInstaller, URL, () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-updates-\(UUID().uuidString)")
        let installer = FileUpdateInstaller(supportDirectory: directory)
        return (installer, directory, {
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("a matching file size is a cache hit")
    func cacheHitMatchingSize() throws {
        let (installer, _, cleanup) = makeInstaller()
        defer { cleanup() }
        try FileManager.default.createDirectory(
            at: installer.updatesDirectory, withIntermediateDirectories: true
        )
        let payload = Data(repeating: 7, count: 32)
        try payload.write(to: installer.dmgCacheURL(version: "v1.2.0"))
        let cached = installer.cachedDMG(version: "1.2.0", expectedByteCount: 32)
        #expect(cached != nil)
    }

    @Test("a different file size is a cache miss")
    func cacheMissWrongSize() throws {
        let (installer, _, cleanup) = makeInstaller()
        defer { cleanup() }
        try FileManager.default.createDirectory(
            at: installer.updatesDirectory, withIntermediateDirectories: true
        )
        try Data(repeating: 1, count: 8).write(to: installer.dmgCacheURL(version: "1.2.0"))
        #expect(installer.cachedDMG(version: "1.2.0", expectedByteCount: 32) == nil)
    }

    @Test("staging a newer fixture app succeeds")
    func stageCopiedNewerApp() throws {
        let (installer, directory, cleanup) = makeInstaller()
        defer { cleanup() }
        let fixture = try makeAppFixture(in: directory, version: "9.9.9")
        let staged = try installer.stageCopiedApp(from: fixture, currentVersion: "1.0.0")
        #expect(FileManager.default.fileExists(atPath: staged.path))
    }

    @Test("staging an equal or older app is refused")
    func stageCopiedOlderApp() throws {
        let (installer, directory, cleanup) = makeInstaller()
        defer { cleanup() }
        let fixture = try makeAppFixture(in: directory, version: "1.0.0")
        #expect(throws: UpdateInstallerError.notNewer) {
            try installer.stageCopiedApp(from: fixture, currentVersion: "1.0.0")
        }
    }

    private func makeAppFixture(in directory: URL, version: String) throws -> URL {
        let app = directory.appendingPathComponent("fixture/DeskPet.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleShortVersionString</key><string>\(version)</string>
        </dict></plist>
        """
        try plist.write(
            to: contents.appendingPathComponent("Info.plist"),
            atomically: true,
            encoding: .utf8
        )
        return app
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

final class FakeUpdateInstaller: UpdateInstalling, @unchecked Sendable {
    var downloadCount = 0
    var stageCount = 0
    var installCount = 0
    var lastDownloadURL: URL?
    var cachedURL: URL?
    var stagedURL = URL(fileURLWithPath: "/tmp/DeskPet-staged.app")

    func cachedDMG(version: String, expectedByteCount: Int?) -> URL? {
        cachedURL
    }

    func download(from url: URL, version: String, expectedByteCount: Int?) async throws -> URL {
        downloadCount += 1
        lastDownloadURL = url
        return URL(fileURLWithPath: "/tmp/DeskPet.dmg")
    }

    func stageApp(fromDMG dmgURL: URL, currentVersion: String) throws -> URL {
        stageCount += 1
        return stagedURL
    }

    func stageCopiedApp(from sourceApp: URL, currentVersion: String) throws -> URL {
        stageCount += 1
        return stagedURL
    }

    func installAndRelaunch(destination: URL, stagedApp: URL) throws {
        installCount += 1
    }
}

@Suite("Update check wiring", .serialized)
@MainActor
struct UpdateCheckWiringTests {
    private func makeState(
        checker: FakeUpdateChecker,
        installer: FakeUpdateInstaller = FakeUpdateInstaller()
    ) -> (AppState, FakeUpdateInstaller, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let state = AppState(
            persistence: persistence,
            clock: TestClock(),
            random: { 0.5 },
            updateChecker: checker,
            updateInstaller: installer
        )
        return (state, installer, {
            state.stop()
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("an available result downloads, stages, and shows a bubble")
    func availableShowsBubble() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let checker = FakeUpdateChecker(result: UpdateCheckResult(
            status: .available,
            currentVersion: "1.0.0",
            latestVersion: "9.9.9",
            releaseURL: Constants.releasesURL,
            dmgURL: Constants.dmgDownloadURL,
            dmgByteCount: 100
        ))
        let (state, installer, cleanup) = makeState(checker: checker)
        defer { cleanup() }
        state.start()

        await state.performUpdateCheck(notifyAvailable: true)

        #expect(state.lastUpdateCheck.status == .available)
        #expect(installer.downloadCount == 1)
        #expect(installer.stageCount == 1)
        #expect(state.canInstallUpdate)
        #expect(state.updateStatusMessage == Strings.SettingsLabels.updateReady("9.9.9"))
        #expect(state.petWindow.currentBubble?.id == BubbleID.updateAvailable)
        #expect(state.petWindow.currentBubble?.actions.contains { $0.id == BubbleActionID.installUpdate } == true)
        #expect(state.petState == .happy)
    }

    @Test("a cached DMG is not downloaded again")
    func cacheSkipsDownload() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let installer = FakeUpdateInstaller()
        installer.cachedURL = URL(fileURLWithPath: "/tmp/cached.dmg")
        let checker = FakeUpdateChecker(result: UpdateCheckResult(
            status: .available,
            currentVersion: "1.0.0",
            latestVersion: "9.9.9",
            dmgURL: Constants.dmgDownloadURL,
            dmgByteCount: 100
        ))
        let (state, wired, cleanup) = makeState(checker: checker, installer: installer)
        defer { cleanup() }

        await state.performUpdateCheck(notifyAvailable: false)

        #expect(wired.downloadCount == 0)
        #expect(wired.stageCount == 1)
        #expect(state.canInstallUpdate)
    }

    @Test("Update installs once")
    func installCalledOnce() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let checker = FakeUpdateChecker(result: UpdateCheckResult(
            status: .available,
            currentVersion: "1.0.0",
            latestVersion: "9.9.9",
            dmgURL: Constants.dmgDownloadURL
        ))
        let (state, installer, cleanup) = makeState(checker: checker)
        defer { cleanup() }

        await state.performUpdateCheck(notifyAvailable: false)
        state.installReadyUpdate()

        #expect(installer.installCount == 1)
        #expect(state.updateInstallPhase == .installing)
    }

    @Test("an up-to-date result does not show a bubble")
    func upToDateSilent() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let checker = FakeUpdateChecker(result: UpdateCheckResult(
            status: .upToDate,
            currentVersion: "1.0.0",
            latestVersion: "1.0.0"
        ))
        let (state, installer, cleanup) = makeState(checker: checker)
        defer { cleanup() }

        await state.performUpdateCheck(notifyAvailable: true)

        #expect(state.updateStatusMessage == Strings.SettingsLabels.updateCurrent("1.0.0"))
        #expect(state.petWindow.currentBubble == nil)
        #expect(installer.downloadCount == 0)
        #expect(!state.canInstallUpdate)
    }
}
