import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DeskPetKit

@Suite("Settings limits")
struct SettingsLimitsTests {

    @Test("the ranges match the Electron number inputs")
    func rangesMatchSource() {
        // min/max attributes from SettingsView.tsx.
        #expect(SettingsLimits.breakIntervalMinutes == 1...900)
        #expect(SettingsLimits.breakRunDurationSeconds == 10...900)
        #expect(SettingsLimits.hydrationIntervalMinutes == 1...900)
        #expect(SettingsLimits.focusDurationMinutes == 1...900)
        #expect(SettingsLimits.distractionGraceSeconds == 0...900)
    }

    @Test("clamping pins values to the range")
    func clamping() {
        #expect(SettingsLimits.clamp(0, to: 1...900) == 1)
        #expect(SettingsLimits.clamp(5000, to: 1...900) == 900)
        #expect(SettingsLimits.clamp(45, to: 1...900) == 45)
        #expect(SettingsLimits.clamp(-10, to: 0...900) == 0)
    }

    @Test("the break-run floor agrees with the store's own normalization")
    func breakRunFloorAgrees() {
        // The UI range and normalizeSettings must not disagree, or a value
        // accepted by one would be rewritten by the other.
        #expect(
            SettingsLimits.breakRunDurationSeconds.lowerBound
                == Settings.minimumBreakRunDurationSeconds
        )
    }
}

@Suite("Settings window", .serialized)
@MainActor
struct SettingsWindowTests {

    private func makeState() -> (AppState, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let state = AppState(persistence: persistence, clock: TestClock(), random: { 0.5 })

        return (state, {
            state.stop()
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("the window uses the ported geometry")
    func windowGeometry() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let controller = SettingsWindowController(state: state)
        controller.show()
        defer { controller.close() }

        let window = try #require(controller.currentWindow)
        #expect(window.frame.width == Constants.settingsWindowSize.width)
        // Width is fixed; height resizes down to the minimum.
        #expect(window.minSize.width == Constants.settingsWindowSize.width)
        #expect(window.maxSize.width == Constants.settingsWindowSize.width)
        #expect(window.minSize.height == Constants.settingsWindowMinHeight)
        // `titleBarStyle: hiddenInset` in the original.
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.closable))

        let hosting = try #require(window.contentView as? NSHostingView<SettingsView>)
        #expect(
            !hosting.sizingOptions.contains(.intrinsicContentSize),
            "intrinsic sizing clips Reminders/Focus below the window"
        )
        #expect(hosting.sizingOptions.contains(.minSize))
    }

    @Test("the window is pinned to light appearance")
    func windowForcesLightAppearance() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let controller = SettingsWindowController(state: state)
        controller.show()
        defer { controller.close() }

        // Regression: in Dark Mode SwiftUI gave buttons white labels, which were
        // invisible against the hardcoded cream cards.
        let window = try #require(controller.currentWindow)
        #expect(window.appearance?.name == .aqua)
    }

    @Test("showing twice reuses the same window")
    func showIsIdempotent() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let controller = SettingsWindowController(state: state)
        controller.show()
        let first = try #require(controller.currentWindow)
        controller.show()
        #expect(controller.currentWindow === first, "a second window must not open")
        controller.close()
    }

    @Test("the window hosts the SwiftUI view")
    func windowHostsSwiftUI() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let controller = SettingsWindowController(state: state)
        controller.show()
        defer { controller.close() }

        let window = try #require(controller.currentWindow)
        #expect(window.contentView != nil)
        #expect(String(describing: type(of: window.contentView!)).contains("NSHostingView"))
    }

    @Test("the menu's settings action opens the window")
    func menuOpensWindow() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let controller = SettingsWindowController(state: state)
        state.onOpenSettings = { controller.show() }
        defer { controller.close() }

        state.handle(.openSettings)
        #expect(controller.isVisible)
    }
}

@Suite("Settings editing", .serialized)
@MainActor
struct SettingsEditingTests {

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

    @Test("changing the break interval reschedules immediately")
    func intervalChangeReschedules() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.updateSettings { $0.breakIntervalMinutes = 5 }

        let due = try #require(state.scheduler.breakDueAt)
        #expect(due.timeIntervalSince(clock.now) == 5 * 60, "no restart should be needed")
    }

    @Test("disabling a reminder clears its schedule")
    func disablingClearsSchedule() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.updateSettings { $0.breakReminderEnabled = false }
        #expect(state.scheduler.breakDueAt == nil)

        state.updateSettings { $0.breakReminderEnabled = true }
        #expect(state.scheduler.breakDueAt != nil)
    }

    @Test("changing the appearance updates the live pet")
    func appearanceChangeIsLive() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        for appearance in BuiltInPetAppearanceID.allCases {
            let id = PetAppearanceID(rawValue: appearance.rawValue)!
            state.updateSettings { $0.petAppearanceID = id }
            #expect(state.petWindow.appearance == id)
            #expect(state.petWindow.contentView.petLayer.contents != nil)
        }
    }

    @Test("edits survive a reload from persistence")
    func editsPersist() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.updateSettings {
            $0.breakIntervalMinutes = 33
            $0.hydrationIntervalMinutes = 77
            $0.focusDurationMinutes = 45
            $0.distractionDetectionEnabled = true
            $0.distractionBlockedApps = ["Slack", "Steam"]
        }

        // A fresh read models the next launch.
        let reloaded = state.persistence.settings
        #expect(reloaded.breakIntervalMinutes == 33)
        #expect(reloaded.hydrationIntervalMinutes == 77)
        #expect(reloaded.focusDurationMinutes == 45)
        #expect(reloaded.distractionDetectionEnabled)
        #expect(reloaded.distractionBlockedApps == ["Slack", "Steam"])
    }

    @Test("an out-of-range value written directly is corrected on load")
    func outOfRangeBreakRunIsCorrected() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.updateSettings { $0.breakRunDurationSeconds = 1 }
        #expect(state.settings.breakRunDurationSeconds == 10, "the floor applies")
    }

    @Test("blocked list edits reach the settings store")
    func blockedListEdits() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.updateSettings { $0.distractionBlockedKeywords = ["youtube"] }
        #expect(state.settings.distractionBlockedKeywords == ["youtube"])

        state.updateSettings { $0.distractionBlockedKeywords.append("reddit") }
        #expect(state.settings.distractionBlockedKeywords == ["youtube", "reddit"])

        state.updateSettings { $0.distractionBlockedKeywords.removeAll { $0 == "youtube" } }
        #expect(state.settings.distractionBlockedKeywords == ["reddit"])
    }

    @Test("resetting today's stats clears the counters shown in settings")
    func resetTodayClearsCounters() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.startFocus()
        clock.advance(by: 5 * 60)
        state.stopFocus(completed: true)
        #expect(state.stats.focusMinutes == 5)

        state.resetTodayStats()
        #expect(state.stats.focusMinutes == 0)
    }

    @Test("appearance previews decode for every built-in pet")
    func previewsDecode() {
        for appearance in BuiltInPetAppearanceID.allCases {
            let id = PetAppearanceID(rawValue: appearance.rawValue)!
            let image = PetAssetLoader.previewImage(for: id)
            #expect(image != nil, "no preview for \(appearance.rawValue)")
            #expect((image?.size.width ?? 0) > 0)
        }
    }

    @Test("enabling distraction detection keeps the settings window hosting SwiftUI")
    func distractionStatusRowWindow() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.updateSettings { $0.distractionDetectionEnabled = true }
        let controller = SettingsWindowController(state: state)
        controller.show()
        defer { controller.close() }

        let window = try #require(controller.currentWindow)
        #expect(window.contentView != nil)
        #expect(state.settings.distractionDetectionEnabled)
    }
}
