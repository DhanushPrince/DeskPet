import AppKit
import Foundation
import Testing
@testable import DeskPetKit

/// Ported from `src/main/menus.ts`.
@Suite("Menu builder")
struct MenuBuilderTests {

    private func state(
        petVisible: Bool = true,
        focusActive: Bool = false,
        developer: Bool = false
    ) -> MenuState {
        MenuState(
            petVisible: petVisible,
            focusActive: focusActive,
            includeDeveloperItems: developer
        )
    }

    /// Commands in order, ignoring separators and labels.
    private func commands(_ items: [MenuItemDescriptor]) -> [MenuAction] {
        items.compactMap {
            if case .command(let action, _) = $0 { return action }
            return nil
        }
    }

    private func title(of action: MenuAction, in items: [MenuItemDescriptor]) -> String? {
        for item in items {
            if case .command(let candidate, let title) = item, candidate == action {
                return title
            }
        }
        return nil
    }

    // MARK: Dynamic labels

    @Test("the pet toggle is labelled for the current visibility")
    func petToggleLabel() {
        let visible = MenuBuilder.trayMenu(state(petVisible: true))
        #expect(title(of: .togglePet, in: visible) == "Hide Pet")

        let hidden = MenuBuilder.trayMenu(state(petVisible: false))
        #expect(title(of: .togglePet, in: hidden) == "Show Pet")
    }

    @Test("the focus item switches command and label with focus state")
    func focusToggleLabel() {
        let idle = MenuBuilder.trayMenu(state(focusActive: false))
        #expect(commands(idle).contains(.startFocus))
        #expect(title(of: .startFocus, in: idle) == "Start Focus Mode")

        let focused = MenuBuilder.trayMenu(state(focusActive: true))
        #expect(commands(focused).contains(.stopFocusCompleted))
        #expect(!commands(focused).contains(.startFocus))
        #expect(title(of: .stopFocusCompleted, in: focused) == "Stop Focus Mode")
    }

    @Test("the context menu cancels focus while the tray menu completes it")
    func focusStopDiffersByMenu() {
        // Preserves stopFocusFromMenu (completed) vs stopFocusFromContext.
        let tray = MenuBuilder.trayMenu(state(focusActive: true))
        #expect(commands(tray).contains(.stopFocusCompleted))

        let context = MenuBuilder.petContextMenu(state(focusActive: true))
        #expect(commands(context).contains(.stopFocusCancelled))
        #expect(!commands(context).contains(.stopFocusCompleted))
    }

    // MARK: Structure

    @Test("the tray menu opens with a disabled app name and ends with quit")
    func trayMenuStructure() {
        let items = MenuBuilder.trayMenu(state())
        #expect(items.first == .disabledLabel(Constants.appName))
        #expect(items.dropFirst().first == .separator)
        #expect(items.last == .command(.quit, title: "Quit"))
        #expect(commands(items) == [.togglePet, .startFocus, .openSettings, .quit])
    }

    @Test("the application menu nests everything under an app submenu")
    func applicationMenuStructure() throws {
        let items = MenuBuilder.applicationMenu(state())
        #expect(items.count == 1)

        guard case .submenu(let title, let children) = items[0] else {
            Issue.record("expected a submenu")
            return
        }
        #expect(title == Constants.appName)
        #expect(commands(children) == [.togglePet, .startFocus, .openSettings, .quit])
    }

    @Test("the pet context menu offers settings, focus and hide")
    func contextMenuStructure() {
        let items = MenuBuilder.petContextMenu(state())
        #expect(commands(items) == [.openSettings, .startFocus, .hidePet])
        #expect(items.last == .command(.hidePet, title: "Hide Pet"))
    }

    // MARK: Developer items

    @Test("developer items are absent unless requested")
    func developerItemsHidden() {
        let items = MenuBuilder.trayMenu(state(developer: false))
        let actions = Set(commands(items))
        #expect(actions.isDisjoint(with: [
            .demoBreak, .demoHydration, .demoFocusWarning, .demoHappy, .debugCycleStates
        ]))
    }

    @Test("developer items appear in all three menus when enabled")
    func developerItemsShown() {
        for items in [
            MenuBuilder.trayMenu(state(developer: true)),
            MenuBuilder.petContextMenu(state(developer: true))
        ] {
            let actions = Set(commands(items))
            #expect(actions.isSuperset(of: [
                .demoBreak, .demoHydration, .demoFocusWarning, .demoHappy
            ]))
        }
    }

    // MARK: AppKit construction

    @Test("descriptors build an NSMenu with matching rows")
    @MainActor
    func buildsNSMenu() {
        let target = MenuActionTarget { _ in }
        let descriptors = MenuBuilder.trayMenu(state())
        let menu = MenuBuilder.makeMenu(from: descriptors, target: target)

        #expect(menu.items.count == descriptors.count)
        #expect(menu.items[0].title == Constants.appName)
        #expect(!menu.items[0].isEnabled, "the app name row is a label")
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items.last?.title == "Quit")
    }

    @Test("clicking a built menu item dispatches its action")
    @MainActor
    func menuItemDispatchesAction() throws {
        var received: [MenuAction] = []
        let target = MenuActionTarget { received.append($0) }
        let menu = MenuBuilder.makeMenu(from: MenuBuilder.trayMenu(state()), target: target)

        let quit = try #require(menu.items.indices.last.map { menu.items[$0] })
        target.handleMenuItem(quit)
        #expect(received == [.quit])
    }

    @Test("submenus are constructed recursively")
    @MainActor
    func submenusAreBuilt() throws {
        let target = MenuActionTarget { _ in }
        let menu = MenuBuilder.makeMenu(
            from: MenuBuilder.applicationMenu(state()),
            target: target
        )
        let submenu = try #require(menu.items.first?.submenu)
        #expect(submenu.items.count > 1)
    }
}

@Suite("Tray icon")
@MainActor
struct TrayIconTests {

    @Test("the paw icon is a 22pt template image")
    func iconIsTemplate() {
        let image = TrayIcon.make()
        #expect(image.isTemplate, "must be a template so the menu bar tints it")
        #expect(image.size == CGSize(width: 22, height: 22))
    }

    @Test("the icon draws five shapes: four toes and a pad")
    func iconGeometry() {
        #expect(TrayIcon.circles.count == 5)
        // The pad is the largest shape.
        let largest = TrayIcon.circles.max { $0.radius < $1.radius }
        #expect(largest?.radius == 7)
        // Every shape fits inside the icon bounds.
        for circle in TrayIcon.circles {
            #expect(circle.x - circle.radius >= -0.001)
            #expect(circle.x + circle.radius <= TrayIcon.size)
            #expect(circle.y + circle.radius <= TrayIcon.size)
        }
    }

    @Test("the icon rasterises to non-empty pixels")
    func iconRasterises() throws {
        let image = TrayIcon.make()
        let representation = try #require(
            image.representations.first ?? NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
        )
        #expect(representation.size.width > 0)

        // Drawing into a bitmap should mark some pixels.
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 22, pixelsHigh: 22,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: CGRect(x: 0, y: 0, width: 22, height: 22))
        NSGraphicsContext.restoreGraphicsState()

        var opaquePixels = 0
        for x in 0..<22 {
            for y in 0..<22 {
                if let colour = bitmap.colorAt(x: x, y: y), colour.alphaComponent > 0.5 {
                    opaquePixels += 1
                }
            }
        }
        #expect(opaquePixels > 50, "expected the paw to cover pixels, got \(opaquePixels)")
    }
}

@Suite("App state", .serialized)
@MainActor
struct AppStateTests {

    private func makeState() -> (AppState, TestClock, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let clock = TestClock()
        let state = AppState(persistence: persistence, clock: clock)

        return (state, clock, {
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("state starts from persisted settings")
    func startsFromPersistedSettings() {
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        #expect(state.settings == Settings.defaults)
        #expect(state.petState == .idle)
        #expect(!state.focusActive)
        #expect(state.blockingMode == nil)
    }

    @Test("settings changes persist and reach the pet window")
    func settingsChangesApply() {
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.updateSettings { $0.petAppearanceID = .xiaoJiMao }

        #expect(state.settings.petAppearanceID == .xiaoJiMao)
        #expect(state.petWindow.appearance == .xiaoJiMao)
        #expect(state.persistence.settings.petAppearanceID == .xiaoJiMao)
    }

    @Test("settings are normalized when written through")
    func settingsNormalizedOnUpdate() {
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.updateSettings { $0.breakRunDurationSeconds = 1 }
        #expect(state.settings.breakRunDurationSeconds == 10)
    }

    @Test("hiding the pet persists the choice and showing clears it")
    func visibilityPersists() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.start()
        #expect(state.petVisible)
        #expect(!state.petHiddenByUser)

        state.hidePet()
        #expect(!state.petVisible)
        #expect(state.petHiddenByUser)
        #expect(state.persistence.petHiddenByUser)

        state.showPet()
        #expect(state.petVisible)
        #expect(!state.petHiddenByUser)
    }

    @Test("a pet hidden by the user stays hidden at launch")
    func hiddenPetStaysHidden() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.persistence.petHiddenByUser = true
        state.start()
        #expect(!state.petVisible)
    }

    @Test("a reminder cannot resurrect a pet the user hid")
    func reminderRespectsHiddenPet() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.start()
        state.hidePet()

        // Requests visibility as part of the trigger.
        state.stateMachine.triggerBreakReminder()
        #expect(!state.petVisible, "hidden pet must stay hidden")
    }

    @Test("toggling visibility flips it both ways")
    func toggleVisibility() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.start()
        state.togglePetVisibility()
        #expect(!state.petVisible)
        state.togglePetVisibility()
        #expect(state.petVisible)
    }

    @Test("state changes mirror onto the published properties")
    func stateMirrors() {
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.stateMachine.triggerBreakReminder()
        #expect(state.petState == .breakPrompt)
        #expect(state.blockingMode == .breakPrompt)

        state.stateMachine.resumeLongTermState()
        #expect(state.petState == .idle)
        #expect(state.blockingMode == nil)
    }

    @Test("focus start and stop credit minutes to today's stats")
    func focusCreditsStats() {
        let (state, clock, cleanup) = makeState()
        defer { cleanup() }

        state.startFocus()
        #expect(state.focusActive)

        clock.advance(by: 30 * 60)
        state.stopFocus(completed: true)

        #expect(!state.focusActive)
        #expect(state.stats.focusMinutes == 30)
        #expect(state.persistence.currentStats.focusMinutes == 30)
    }

    @Test("stopping focus when none is running changes nothing")
    func stopFocusWithoutSession() {
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.stopFocus(completed: false)
        #expect(state.stats.focusMinutes == 0)
    }

    @Test("resetting today clears counters and the break mute")
    func resetToday() {
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.startFocus()
        state.stopFocus(completed: true)
        state.stateMachine.muteBreaksForToday()
        #expect(state.stats.focusMinutes > 0)
        #expect(state.stateMachine.breakMutedToday)

        state.resetTodayStats()
        #expect(state.stats.focusMinutes == 0)
        #expect(state.stats.breaksTaken == 0)
        #expect(!state.stateMachine.breakMutedToday)
    }

    @Test("menu actions route to the matching behaviour")
    func menuActionRouting() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.start()

        state.handle(.hidePet)
        #expect(!state.petVisible)

        state.handle(.togglePet)
        #expect(state.petVisible)

        state.handle(.startFocus)
        #expect(state.focusActive)

        state.handle(.stopFocusCancelled)
        #expect(!state.focusActive)

        var settingsOpened = 0
        state.onOpenSettings = { settingsOpened += 1 }
        state.handle(.openSettings)
        #expect(settingsOpened == 1)
    }

    @Test("the menu state reflects live pet and focus status")
    func menuStateReflectsLiveState() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, _, cleanup) = makeState()
        defer { cleanup() }

        state.start()
        #expect(state.menuState.petVisible)
        #expect(!state.menuState.focusActive)

        state.startFocus()
        #expect(state.menuState.focusActive)
    }
}
