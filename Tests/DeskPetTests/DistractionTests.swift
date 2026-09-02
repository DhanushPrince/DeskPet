import AppKit
import Foundation
import Testing
@testable import DeskPetKit

/// Ported from `tests/distraction.test.ts`.
@Suite("Distraction classifier")
struct DistractionClassifierTests {

    /// Mirrors the test helper in the original: defaults with both lists empty.
    private func settings(
        apps: [String] = [],
        keywords: [String] = []
    ) -> Settings {
        var settings = Settings.defaults
        settings.distractionBlockedApps = apps
        settings.distractionBlockedKeywords = keywords
        return settings
    }

    private func active(_ appName: String, _ windowTitle: String = "") -> ActiveWindowInfo {
        ActiveWindowInfo(appName: appName, windowTitle: windowTitle)
    }

    // MARK: Ported cases

    @Test("blocked apps match case-insensitively")
    func matchesBlockedAppsCaseInsensitively() {
        #expect(
            DistractionClassifier.classify(
                active("Discord"), settings: settings(apps: ["discord"])
            ) == "app:discord"
        )
    }

    @Test("blocked keywords match in the window title")
    func matchesKeywordInTitle() {
        #expect(
            DistractionClassifier.classify(
                active("Safari", "Watching YouTube"),
                settings: settings(keywords: ["youtube"])
            ) == "keyword:youtube"
        )
    }

    @Test("the pet's own app is never a distraction")
    func ignoresOwnApp() {
        #expect(
            DistractionClassifier.classify(
                active("DeskPet", "youtube"), settings: settings(keywords: ["youtube"])
            ) == nil
        )
    }

    // MARK: Matching details

    @Test("the ignore list is exact, not a substring")
    func ignoreListIsExact() {
        // An app whose name merely contains "DeskPet" is still checked.
        #expect(
            DistractionClassifier.classify(
                active("DeskPet Helper", "youtube"),
                settings: settings(keywords: ["youtube"])
            ) == "keyword:youtube"
        )
        // Electron is on the list for parity with development builds.
        #expect(
            DistractionClassifier.classify(
                active("Electron", "youtube"), settings: settings(keywords: ["youtube"])
            ) == nil
        )
    }

    @Test("app rules match as substrings of the app name")
    func appRuleIsSubstring() {
        #expect(
            DistractionClassifier.classify(
                active("Discord Canary"), settings: settings(apps: ["discord"])
            ) == "app:discord"
        )
    }

    @Test("keyword rules also match the app name")
    func keywordMatchesAppName() {
        // A native client has no useful title, so the app name is checked too.
        #expect(
            DistractionClassifier.classify(
                active("YouTube Music"), settings: settings(keywords: ["youtube"])
            ) == "keyword:youtube"
        )
    }

    @Test("app rules take precedence over keyword rules")
    func appRuleWins() {
        #expect(
            DistractionClassifier.classify(
                active("Discord", "youtube video"),
                settings: settings(apps: ["discord"], keywords: ["youtube"])
            ) == "app:discord"
        )
    }

    @Test("rules are trimmed and lowercased before matching")
    func rulesAreNormalized() {
        #expect(
            DistractionClassifier.classify(
                active("Discord"), settings: settings(apps: ["  DISCORD  "])
            ) == "app:discord",
            "the returned rule is the normalized form"
        )
    }

    @Test("blank rules are ignored")
    func blankRulesIgnored() {
        #expect(
            DistractionClassifier.classify(
                active("Safari", "anything"), settings: settings(apps: ["", "   "], keywords: [""])
            ) == nil
        )
    }

    @Test("nothing matches when no rule applies")
    func noMatch() {
        #expect(
            DistractionClassifier.classify(
                active("Xcode", "DeskPet.swift"),
                settings: settings(apps: ["discord"], keywords: ["youtube"])
            ) == nil
        )
    }

    @Test("the first matching rule in list order wins")
    func firstRuleWins() {
        #expect(
            DistractionClassifier.classify(
                active("Safari", "reddit and youtube"),
                settings: settings(keywords: ["reddit", "youtube"])
            ) == "keyword:reddit"
        )
    }

    // MARK: Display form

    @Test("prefixes are stripped for display")
    func displayStripsPrefix() {
        #expect(DistractionClassifier.displayRule("app:discord") == "discord")
        #expect(DistractionClassifier.displayRule("keyword:youtube") == "youtube")
        #expect(DistractionClassifier.displayRule("bare") == "bare")
    }

    // MARK: Warning gate

    @Test("no warning without a match")
    func noWarningWithoutMatch() {
        #expect(!DistractionClassifier.shouldWarn(
            matchedRule: nil, focusActive: true, blockingMode: nil,
            lastWarningAt: nil, now: Date()
        ))
    }

    @Test("no warning outside a focus session")
    func noWarningWithoutFocus() {
        #expect(!DistractionClassifier.shouldWarn(
            matchedRule: "app:discord", focusActive: false, blockingMode: nil,
            lastWarningAt: nil, now: Date()
        ))
    }

    @Test("no warning stacked on an existing focus warning")
    func noWarningDuringWarning() {
        #expect(!DistractionClassifier.shouldWarn(
            matchedRule: "app:discord", focusActive: true, blockingMode: .focusWarning,
            lastWarningAt: nil, now: Date()
        ))
    }

    @Test("other blocking modes do not suppress a warning")
    func otherBlockingModesAllowWarning() {
        // Only `focusWarning` was checked in the original; a break prompt does
        // not stop the nudge.
        for mode in [BlockingMode.breakPrompt, .breakRun, .hydration] {
            #expect(DistractionClassifier.shouldWarn(
                matchedRule: "app:discord", focusActive: true, blockingMode: mode,
                lastWarningAt: nil, now: Date()
            ), "mode \(mode.rawValue) should still warn")
        }
    }

    @Test("the cooldown suppresses repeat warnings for 60 seconds")
    func cooldownSuppresses() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(!DistractionClassifier.shouldWarn(
            matchedRule: "app:discord", focusActive: true, blockingMode: nil,
            lastWarningAt: now.addingTimeInterval(-30), now: now
        ), "30s after the last warning is still inside the cooldown")

        #expect(DistractionClassifier.shouldWarn(
            matchedRule: "app:discord", focusActive: true, blockingMode: nil,
            lastWarningAt: now.addingTimeInterval(-61), now: now
        ), "61s later the cooldown has expired")

        // Exactly the cooldown boundary is allowed, since the check is `<`.
        #expect(DistractionClassifier.shouldWarn(
            matchedRule: "app:discord", focusActive: true, blockingMode: nil,
            lastWarningAt: now.addingTimeInterval(-Constants.distractionWarningCooldown),
            now: now
        ))
    }

    @Test("the cooldown matches the ported constant")
    func cooldownConstant() {
        #expect(Constants.distractionWarningCooldown == 60)
        #expect(Constants.distractionCheckInterval == 3)
    }
}

@Suite("Distraction detector", .serialized)
@MainActor
struct DistractionDetectorTests {

    private func makeDetector(
        apps: [String] = ["Discord"],
        keywords: [String] = ["youtube"],
        enabled: Bool = true,
        grace: Int = 8,
        window: ActiveWindowInfo = ActiveWindowInfo(appName: "Discord"),
        titlePermissionDenied: Bool = false,
        focusActive: Bool = true
    ) -> (DistractionDetector, TestClock, () -> [String]) {
        var settings = Settings.defaults
        settings.distractionDetectionEnabled = enabled
        settings.distractionBlockedApps = apps
        settings.distractionBlockedKeywords = keywords
        settings.distractionGraceSeconds = grace

        let clock = TestClock()
        let detector = DistractionDetector(
            settings: settings,
            clock: clock,
            reader: {
                ActiveWindowReading(
                    info: window, titlePermissionDenied: titlePermissionDenied
                )
            }
        )
        detector.isFocusActive = { focusActive }
        var warnings: [String] = []
        detector.onWarning = { warnings.append($0) }
        return (detector, clock, { warnings })
    }

    @Test("a disabled detector reports idle and never checks")
    func disabledIsIdle() {
        let (detector, _, warnings) = makeDetector(enabled: false)
        detector.update(settings: {
            var s = Settings.defaults
            s.distractionDetectionEnabled = false
            return s
        }())

        #expect(detector.status.state == .idle)
        detector.checkNow()
        #expect(warnings().isEmpty)
        #expect(!detector.isPolling)
    }

    @Test("a blocked app during focus raises a warning")
    func blockedAppWarns() {
        let (detector, _, warnings) = makeDetector()
        detector.checkNow()

        #expect(warnings() == ["discord"], "the display form drops the prefix")
        #expect(detector.status.state == .watching)
        #expect(detector.status.activeApp == "Discord")
        #expect(detector.status.matchedRule == "discord")
        #expect(detector.status.lastWarningAt != nil)
    }

    @Test("repeat checks inside the cooldown warn only once")
    func cooldownLimitsWarnings() {
        let (detector, clock, warnings) = makeDetector()

        detector.checkNow()
        clock.advance(by: 3)
        detector.checkNow()
        clock.advance(by: 30)
        detector.checkNow()
        #expect(warnings().count == 1, "still inside the 60s cooldown")

        clock.advance(by: 31)
        detector.checkNow()
        #expect(warnings().count == 2, "the cooldown has expired")
    }

    @Test("resetting the cooldown allows an immediate warning")
    func resetCooldown() {
        let (detector, clock, warnings) = makeDetector()

        detector.checkNow()
        #expect(warnings().count == 1)

        clock.advance(by: 5)
        detector.resetCooldown()
        detector.checkNow()
        #expect(warnings().count == 2)
    }

    @Test("no warning outside a focus session, but the status still updates")
    func noWarningWithoutFocus() {
        let (detector, _, warnings) = makeDetector(focusActive: false)
        detector.checkNow()

        #expect(warnings().isEmpty)
        #expect(detector.status.activeApp == "Discord")
        #expect(detector.status.matchedRule == "discord", "still reported for display")
    }

    @Test("an unmatched app updates the status without warning")
    func unmatchedAppNoWarning() {
        let (detector, _, warnings) = makeDetector(
            window: ActiveWindowInfo(appName: "Xcode", windowTitle: "AppState.swift")
        )
        detector.checkNow()

        #expect(warnings().isEmpty)
        #expect(detector.status.activeApp == "Xcode")
        #expect(detector.status.matchedRule == nil)
        #expect(detector.status.lastCheckedAt != nil)
    }

    @Test("a withheld window title reports permissionNeeded with guidance")
    func permissionFailure() {
        let (detector, _, _) = makeDetector(
            window: ActiveWindowInfo(appName: "Safari"),
            titlePermissionDenied: true
        )
        detector.checkNow()
        #expect(detector.status.state == .permissionNeeded)
        #expect(detector.status.error?.contains("Accessibility") == true)
    }

    @Test("blocked apps are still detected without Accessibility permission")
    func appRulesWorkWithoutPermission() {
        // NSWorkspace supplies the app name with no permission at all, so the
        // app half of detection must keep working; only title keywords are lost.
        let (detector, _, warnings) = makeDetector(
            window: ActiveWindowInfo(appName: "Discord"),
            titlePermissionDenied: true
        )
        detector.checkNow()

        #expect(warnings() == ["discord"])
        #expect(detector.status.state == .permissionNeeded, "the gap is still reported")
    }

    @Test("title keywords cannot match without permission")
    func keywordRulesNeedPermission() {
        let (detector, _, warnings) = makeDetector(
            window: ActiveWindowInfo(appName: "Safari"),
            titlePermissionDenied: true
        )
        detector.checkNow()
        #expect(warnings().isEmpty, "the title was withheld, so nothing to match")
    }

    @Test("other read failures report an error state")
    func otherFailure() {
        var settings = Settings.defaults
        settings.distractionDetectionEnabled = true
        let detector = DistractionDetector(
            settings: settings,
            clock: TestClock(),
            reader: { throw ActiveWindowError.accessibility(code: -25200) }
        )
        detector.isFocusActive = { true }

        detector.checkNow()
        #expect(detector.status.state == .error)
        #expect(detector.status.error?.contains("-25200") == true)
    }

    @Test("a focus warning already showing suppresses another")
    func existingWarningSuppresses() {
        let (detector, _, warnings) = makeDetector()
        detector.blockingMode = { .focusWarning }
        detector.checkNow()
        #expect(warnings().isEmpty)
    }

    @Test("enabling starts polling after the grace period")
    func gracePeriodDelaysFirstCheck() async throws {
        var settings = Settings.defaults
        settings.distractionDetectionEnabled = true
        settings.distractionBlockedApps = ["Discord"]
        // A short grace so the test does not wait 8 seconds.
        settings.distractionGraceSeconds = 0

        let detector = DistractionDetector(
            settings: settings,
            clock: SystemClock(),
            reader: { ActiveWindowReading(info: ActiveWindowInfo(appName: "Discord")) }
        )
        detector.isFocusActive = { true }
        var warnings: [String] = []
        detector.onWarning = { warnings.append($0) }

        detector.update(settings: settings)
        #expect(detector.status.state == .watching)

        try await Task.sleep(for: .milliseconds(200))
        #expect(warnings.count == 1, "the first check runs once the grace elapses")
        #expect(detector.isPolling, "polling continues afterwards")
        detector.stop()
    }

    @Test("stopping halts polling and returns to idle")
    func stopReturnsToIdle() {
        let (detector, _, _) = makeDetector()
        detector.update(settings: {
            var s = Settings.defaults
            s.distractionDetectionEnabled = true
            return s
        }())
        detector.stop()
        #expect(detector.status.state == .idle)
        #expect(!detector.isPolling)
    }
}

@Suite("Distraction integration", .serialized)
@MainActor
struct DistractionIntegrationTests {

    private func makeState(
        window: ActiveWindowInfo
    ) -> (AppState, TestClock, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let clock = TestClock()
        let state = AppState(
            persistence: persistence,
            clock: clock,
            random: { 0.5 },
            activeWindowReader: { ActiveWindowReading(info: window) }
        )

        return (state, clock, {
            state.stop()
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("a detected distraction during focus nudges the pet")
    func detectionRaisesFocusWarning() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState(window: ActiveWindowInfo(appName: "Discord"))
        defer { cleanup() }
        state.start()
        state.updateSettings { $0.distractionDetectionEnabled = true }

        state.startFocus()
        state.distractionDetector.checkNow()

        #expect(state.petState == .focusAlert)
        #expect(state.blockingMode == .focusWarning)
        #expect(state.stats.focusWarnings == 1)
        #expect(state.petWindow.currentBubble?.message.contains("discord") == true)
    }

    @Test("detection is silent outside a focus session")
    func silentWithoutFocus() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState(window: ActiveWindowInfo(appName: "Discord"))
        defer { cleanup() }
        state.start()
        state.updateSettings { $0.distractionDetectionEnabled = true }

        state.distractionDetector.checkNow()
        #expect(state.petState == .idle)
        #expect(state.stats.focusWarnings == 0)
    }

    @Test("the status is mirrored onto AppState for the settings window")
    func statusMirrored() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState(
            window: ActiveWindowInfo(appName: "Safari", windowTitle: "YouTube")
        )
        defer { cleanup() }
        state.start()
        state.updateSettings { $0.distractionDetectionEnabled = true }

        state.distractionDetector.checkNow()
        #expect(state.distractionStatus.activeApp == "Safari")
        #expect(state.distractionStatus.activeWindowTitle == "YouTube")
        #expect(state.distractionStatus.matchedRule == "youtube")
    }

    @Test("disabling detection returns the status to idle")
    func disablingReturnsToIdle() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState(window: ActiveWindowInfo(appName: "Discord"))
        defer { cleanup() }
        state.start()

        state.updateSettings { $0.distractionDetectionEnabled = true }
        #expect(state.distractionStatus.state == .watching)

        state.updateSettings { $0.distractionDetectionEnabled = false }
        #expect(state.distractionStatus.state == .idle)
    }

    @Test("a new focus session can warn again after the previous one")
    func newSessionResetsCooldown() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState(window: ActiveWindowInfo(appName: "Discord"))
        defer { cleanup() }
        state.start()
        state.updateSettings { $0.distractionDetectionEnabled = true }

        state.startFocus()
        state.distractionDetector.checkNow()
        #expect(state.stats.focusWarnings == 1)

        clock.advance(by: 60)
        state.stopFocus(completed: false)
        state.startFocus()
        state.distractionDetector.checkNow()

        #expect(state.stats.focusWarnings == 2, "the cooldown resets between sessions")
    }
}

@Suite("Browser tab reader")
struct BrowserTabReaderTests {

    private struct StubRunner: AppleScriptRunning {
        let result: String?

        func run(source: String) -> String? { result }
    }

    @Test("supported bundle IDs map to AppleScript application names")
    func bundleIDMap() {
        #expect(BrowserTabReader.supportedBundleIDs["com.brave.Browser"] == "Brave Browser")
        #expect(BrowserTabReader.supportedBundleIDs["com.google.Chrome"] == "Google Chrome")
        #expect(BrowserTabReader.supportedBundleIDs["com.apple.Safari"] == "Safari")
    }

    @Test("Chromium scripts query only the active tab of the front window")
    func chromiumScriptUsesActiveTabOnly() {
        let script = BrowserTabReader.script(forBundleID: "com.brave.Browser")!
        #expect(script.contains("tell application \"Brave Browser\""))
        #expect(script.contains("active tab of front window"))
        #expect(!script.contains("repeat"))
        #expect(!script.contains("tabs of"))
    }

    @Test("Safari script queries only the current tab of the front window")
    func safariScriptUsesCurrentTabOnly() {
        let script = BrowserTabReader.script(forBundleID: "com.apple.Safari")!
        #expect(script.contains("tell application \"Safari\""))
        #expect(script.contains("current tab of front window"))
        #expect(!script.contains("repeat"))
    }

    @Test("parses title and URL from the two-line script result")
    func parseScriptResult() {
        let tab = BrowserTabReader.parseScriptResult(
            "YouTube\nhttps://www.youtube.com/"
        )
        #expect(tab?.title == "YouTube")
        #expect(tab?.url == "https://www.youtube.com/")
        #expect(tab?.keywordContext == "YouTube https://www.youtube.com/")
    }

    @Test("YouTube URL matches blocked keywords when injected into the classifier")
    func youtubeURLMatchesKeyword() {
        let tab = BrowserTabReader.parseScriptResult(
            "YouTube\nhttps://www.youtube.com/"
        )!
        var settings = Settings.defaults
        settings.distractionBlockedKeywords = ["youtube"]
        #expect(
            DistractionClassifier.classify(
                ActiveWindowInfo(appName: "Brave Browser", windowTitle: tab.keywordContext),
                settings: settings
            ) == "keyword:youtube"
        )
    }

    @Test("script failure does not match YouTube from the app name alone")
    func failureDoesNotMatchAppName() {
        let runner = StubRunner(result: nil)
        let tab = BrowserTabReader.readActiveTab(
            bundleID: "com.brave.Browser",
            runner: runner
        )
        #expect(tab == nil)

        var settings = Settings.defaults
        settings.distractionBlockedKeywords = ["youtube"]
        #expect(
            DistractionClassifier.classify(
                ActiveWindowInfo(appName: "Brave Browser", windowTitle: ""),
                settings: settings
            ) == nil
        )
    }

    @Test("empty URL keeps AX title via enrichedWindowTitle")
    func emptyURLFallsBackToAX() {
        let runner = StubRunner(result: "YouTube\n")
        let tabReader: (String?) -> BrowserTabReader.ActiveTab? = { bundleID in
            BrowserTabReader.readActiveTab(bundleID: bundleID, runner: runner)
        }
        #expect(
            ActiveWindowReader.enrichedWindowTitle(
                axTitle: "Brave",
                bundleID: "com.brave.Browser",
                tabReader: tabReader
            ) == "Brave"
        )
    }

    @Test("non-empty URL replaces AX title for keyword context")
    func urlReplacesAXTitle() {
        let runner = StubRunner(result: "YouTube\nhttps://www.youtube.com/")
        let tabReader: (String?) -> BrowserTabReader.ActiveTab? = { bundleID in
            BrowserTabReader.readActiveTab(bundleID: bundleID, runner: runner)
        }
        #expect(
            ActiveWindowReader.enrichedWindowTitle(
                axTitle: "Brave",
                bundleID: "com.brave.Browser",
                tabReader: tabReader
            ) == "YouTube https://www.youtube.com/"
        )
    }
}
