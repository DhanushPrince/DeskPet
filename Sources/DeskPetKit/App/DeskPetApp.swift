import AppKit

/// Process entry point. Owns the `NSApplication` lifecycle.
public enum DeskPetApp {
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // .accessory: no Dock icon, no app switcher entry, but windows can
        // still be shown and focused. Paired with LSUIElement in Info.plist.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Retained for the process lifetime.
    private var appState: AppState?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("DeskPet \(AppInfo.version) launched (bundle: \(AppInfo.bundleIdentifier))")

        let persistence = Persistence(supportDirectory: Self.supportDirectory())
        // Imports the Electron build's store the first time only.
        LegacyMigration.run(into: persistence)

        let state = AppState(persistence: persistence)
        let statusBar = StatusBarController(
            stateProvider: { [weak state] in
                state?.menuState ?? MenuState(petVisible: false, focusActive: false)
            },
            onAction: { [weak state] action in
                state?.handle(action)
            }
        )
        state.statusBar = statusBar
        let settingsWindow = SettingsWindowController(state: state)
        state.onOpenSettings = { [weak settingsWindow] in
            settingsWindow?.show()
        }
        state.start()

        appState = state
        self.statusBar = statusBar
        self.settingsWindow = settingsWindow

        #if DEBUG
        DebugHarness.startIfRequested(state: state, settingsWindow: settingsWindow)
        #endif
    }

    /// Application Support directory, overridable in debug builds so migration
    /// can be exercised against a copy of a real store without touching the
    /// user's data.
    private static func supportDirectory() -> URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["DESKPET_SUPPORT_DIR"], !path.isEmpty {
            NSLog("DeskPet[debug]: using support directory \(path)")
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return PetAssetLoader.applicationSupportRoot
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// The pet and the menu bar item are the app; closing the settings window
    /// must not terminate the process.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Tear the pet and status item down first. `NSApp.terminate` otherwise
    /// waits on the borderless pet window and the status-item window, both of
    /// which ignore a normal `performClose:`.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        prepareToQuit()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        prepareToQuit()
    }

    private func prepareToQuit() {
        appState?.stop()
        appState?.petWindow.hide()
        settingsWindow?.close()
        statusBar = nil
        for window in NSApp.windows {
            window.close()
        }
    }
}

#if DEBUG
/// Debug-build affordances driven by environment variables, used to exercise
/// interactions that would otherwise need synthetic mouse events (posting those
/// requires Accessibility permission).
enum DebugHarness {
    static func startIfRequested(state: AppState, settingsWindow: SettingsWindowController) {
        let environment = ProcessInfo.processInfo.environment
        let controller = state.petWindow

        // DESKPET_DEBUG_DUMP_SETTINGS=1: report what was loaded or migrated.
        if environment["DESKPET_DEBUG_DUMP_SETTINGS"] != nil {
            dumpSettings(state)
        }

        // DESKPET_DEBUG_INTERVALS=<breakMinutes>,<hydrationMinutes>: shorten the
        // reminder intervals so the scheduler can be observed without waiting
        // 45 minutes. Not persisted beyond this launch's settings write.
        if let value = environment["DESKPET_DEBUG_INTERVALS"] {
            let parts = value.split(separator: ",").compactMap { Int($0) }
            if parts.count == 2 {
                state.updateSettings {
                    $0.breakIntervalMinutes = parts[0]
                    $0.hydrationIntervalMinutes = parts[1]
                }
                NSLog("DeskPet[debug]: intervals set to break=\(parts[0])m hydration=\(parts[1])m")
            }
        }

        // DESKPET_DEBUG_LOG_STATE=1: log every pet state change and the current
        // due dates.
        if environment["DESKPET_DEBUG_LOG_STATE"] != nil {
            logStateChanges(state)
        }

        // DESKPET_DEBUG_SIMULATE_WAKE=<seconds>: run the wake handler, which is
        // the path a real sleep/wake takes.
        if let value = environment["DESKPET_DEBUG_SIMULATE_WAKE"], let seconds = Double(value) {
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                NSLog("DeskPet[debug]: simulating wake")
                state.scheduler.handleWake()
            }
        }

        // DESKPET_DEBUG_DRAG=<seconds>: hold a drag open so the pet follows the
        // real cursor, then release it.
        if let value = environment["DESKPET_DEBUG_DRAG"], let seconds = Double(value) {
            NSLog("DeskPet[debug]: starting drag for \(seconds)s")
            controller.startDrag(offset: CGPoint(x: 110, y: 170))
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                controller.stopDrag()
                NSLog("DeskPet[debug]: drag released")
            }
        }

        // DESKPET_DEBUG_LOG_POSITION=<interval>: log the pet's global bounds.
        if let value = environment["DESKPET_DEBUG_LOG_POSITION"], let interval = Double(value) {
            let timer = Timer(timeInterval: interval, repeats: true) { _ in
                let bounds = controller.globalBounds
                NSLog(String(
                    format: "DeskPet[debug]: pos %.0f,%.0f facing=%@",
                    bounds.x, bounds.y, controller.facing.rawValue
                ))
            }
            RunLoop.main.add(timer, forMode: .common)
        }

        // DESKPET_DEBUG_CYCLE_STATES=<seconds per state>: walk all 14 states so
        // every animation can be inspected.
        if let value = environment["DESKPET_DEBUG_CYCLE_STATES"], let interval = Double(value) {
            var index = 0
            let timer = Timer(timeInterval: interval, repeats: true) { _ in
                let petState = PetState.allCases[index % PetState.allCases.count]
                index += 1
                state.stateMachine.debugForceState(petState)
                let definition = PetAppearances.assetDefinition(
                    appearance: controller.appearance,
                    state: petState
                )
                NSLog(
                    "DeskPet[debug]: state=\(petState.rawValue) "
                        + "variants=\(definition.paths.count) "
                        + "placeholder=\(definition.isPlaceholder)"
                )
            }
            RunLoop.main.add(timer, forMode: .common)
        }

        // DESKPET_DEBUG_BUBBLE=<seconds>: show a three-button bubble so its
        // layout and hit area can be inspected.
        if let value = environment["DESKPET_DEBUG_BUBBLE"], let delay = Double(value) {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                let bubble = SpeechBubble(
                    id: BubbleID.breakPrompt,
                    message: Strings.pick(Strings.Bubble.breakReminder),
                    actions: [
                        BubbleAction(
                            id: BubbleActionID.breakDone,
                            label: Strings.Actions.breakDone,
                            kind: .primary
                        ),
                        BubbleAction(
                            id: BubbleActionID.breakSnooze,
                            label: Strings.Actions.breakSnooze
                        ),
                        BubbleAction(
                            id: BubbleActionID.breakMute,
                            label: Strings.Actions.breakMute,
                            kind: .danger
                        )
                    ]
                )
                state.stateMachine.debugForceState(.breakPrompt)
                state.showBubble(bubble)
                let frames = controller.contentView.additionalInteractiveRects
                NSLog(
                    "DeskPet[debug]: bubble shown, interactive rects=\(frames.count) "
                        + "frame=\(controller.contentView.bubbleView.frame)"
                )
            }
        }

        // DESKPET_DEBUG_DISTRACTION=<seconds>: enable detection, start focus, and
        // report what the accessibility API actually returns.
        if let value = environment["DESKPET_DEBUG_DISTRACTION"], let delay = Double(value) {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                NSLog("DeskPet[debug]: AXIsProcessTrusted=\(ActiveWindowReader.isTrusted)")
                NSLog(
                    "DeskPet[debug]: frontmost app via NSWorkspace = "
                        + "\(ActiveWindowReader.frontmostAppName() ?? "nil")"
                )
                do {
                    let reading = try ActiveWindowReader.read()
                    NSLog(
                        "DeskPet[debug]: active app=\(reading.info.appName) "
                            + "title=\(reading.info.windowTitle.isEmpty ? "(none)" : reading.info.windowTitle) "
                            + "titlePermissionDenied=\(reading.titlePermissionDenied)"
                    )
                } catch {
                    NSLog("DeskPet[debug]: read failed: \(error)")
                }

                state.updateSettings { $0.distractionDetectionEnabled = true }
                state.startFocus()
                state.distractionDetector.checkNow()
                let status = state.distractionStatus
                NSLog(
                    "DeskPet[debug]: status state=\(status.state.rawValue) "
                        + "app=\(status.activeApp) "
                        + "title=\(status.activeWindowTitle.isEmpty ? "(none)" : status.activeWindowTitle) "
                        + "matched=\(status.matchedRule ?? "none") "
                        + "error=\(status.error ?? "none")"
                )
            }
        }

        // DESKPET_DEBUG_SETTINGS=<seconds>: open the settings window.
        // DESKPET_DEBUG_SETTINGS_FRAME="x,y,w,h" additionally places it in global
        // top-left coordinates, so the whole scrollable form can be captured on
        // a display tall enough to show it.
        if let value = environment["DESKPET_DEBUG_SETTINGS"], let delay = Double(value) {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                NSLog("DeskPet[debug]: opening settings")
                state.onOpenSettings?()

                guard let frameSpec = environment["DESKPET_DEBUG_SETTINGS_FRAME"] else { return }
                let parts = frameSpec.split(separator: ",").compactMap { Double($0) }
                guard parts.count == 4, let window = settingsWindow.currentWindow else { return }
                let rect = GlobalRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
                window.maxSize = CGSize(width: parts[2], height: .greatestFiniteMagnitude)
                window.minSize = CGSize(width: parts[2], height: 200)
                window.setFrame(ScreenBridge.cocoaRect(from: rect), display: true)
                NSLog("DeskPet[debug]: settings frame set to \(frameSpec)")
            }
        }

        // DESKPET_DEBUG_FOCUS=<seconds>: start a focus session after a delay so
        // the countdown badge can be inspected.
        if let value = environment["DESKPET_DEBUG_FOCUS"], let delay = Double(value) {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                NSLog("DeskPet[debug]: starting focus session")
                state.startFocus()
                NSLog(
                    "DeskPet[debug]: focusActive=\(state.focusActive) "
                        + "badge visible=\(state.petWindow.isFocusBadgeVisible) "
                        + "frame=\(controller.contentView.focusBadge.frame)"
                )
            }
        }

        // DESKPET_DEBUG_HYDRATION=<seconds>: show the hydration prompt.
        if let value = environment["DESKPET_DEBUG_HYDRATION"], let delay = Double(value) {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                NSLog("DeskPet[debug]: triggering hydration prompt")
                state.handle(.demoHydration)
            }
        }

        // DESKPET_DEBUG_BREAK_RUN=<seconds>: start a break run after a delay so
        // the physics can be watched.
        if let value = environment["DESKPET_DEBUG_BREAK_RUN"], let delay = Double(value) {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                NSLog("DeskPet[debug]: starting break run")
                state.startBreakRun()
            }
        }

        // DESKPET_DEBUG_DUMP_MENU=1: print the tray menu structure.
        if environment["DESKPET_DEBUG_DUMP_MENU"] != nil {
            let items = MenuBuilder.trayMenu(state.menuState)
            NSLog("DeskPet[debug]: tray menu has \(items.count) rows")
            for item in items {
                switch item {
                case .separator: NSLog("DeskPet[debug]:   ---")
                case .disabledLabel(let title): NSLog("DeskPet[debug]:   [\(title)]")
                case .command(let action, let title):
                    NSLog("DeskPet[debug]:   \(title) -> \(action.rawValue)")
                case .submenu(let title, let items):
                    NSLog("DeskPet[debug]:   \(title) (\(items.count) items)")
                }
            }
        }

        // DESKPET_DEBUG_QUIT=<seconds>: terminate after exercising other probes.
        if let value = environment["DESKPET_DEBUG_QUIT"], let delay = Double(value) {
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
                NSLog("DeskPet[debug]: quitting")
                NSApp.terminate(nil)
            }
        }
    }

    /// Logs every pet state change plus the reminder due dates, by chaining onto
    /// the existing state-change callback rather than replacing it.
    private static func logStateChanges(_ state: AppState) {
        let existing = state.stateMachine.onStateChange
        state.stateMachine.onStateChange = { petState in
            existing?(petState)
            let breakIn = state.scheduler.timeRemaining(for: .breakReminder)
            let hydrationIn = state.scheduler.timeRemaining(for: .hydration)
            NSLog(
                "DeskPet[debug]: state=\(petState.rawValue) "
                    + "blocking=\(state.stateMachine.blockingMode?.rawValue ?? "none") "
                    + "breakIn=\(breakIn.map { String(format: "%.0fs", $0) } ?? "-") "
                    + "hydrationIn=\(hydrationIn.map { String(format: "%.0fs", $0) } ?? "-")"
            )
        }
    }

    private static func dumpSettings(_ state: AppState) {
        let settings = state.settings
        NSLog(
            "DeskPet[debug]: settings appearance=\(settings.petAppearanceID.rawValue) "
                + "break=\(settings.breakIntervalMinutes)m/\(settings.breakReminderEnabled) "
                + "run=\(settings.breakRunDurationSeconds)s "
                + "hydration=\(settings.hydrationIntervalMinutes)m/\(settings.hydrationReminderEnabled) "
                + "focus=\(settings.focusDurationMinutes)m "
                + "distraction=\(settings.distractionDetectionEnabled)/\(settings.distractionGraceSeconds)s "
                + "apps=\(settings.distractionBlockedApps.count) "
                + "keywords=\(settings.distractionBlockedKeywords.count)"
        )
        let stats = state.stats
        NSLog(
            "DeskPet[debug]: stats date=\(stats.date) breaks=\(stats.breaksTaken) "
                + "waters=\(stats.watersLogged) focusMinutes=\(stats.focusMinutes) "
                + "warnings=\(stats.focusWarnings) "
                + "historyDays=\(state.persistence.statsHistory.count)"
        )
        if let position = state.persistence.petPosition {
            NSLog(String(
                format: "DeskPet[debug]: restored position x=%.0f y=%.0f display=%d",
                position.x, position.y, position.displayId ?? -1
            ))
        } else {
            NSLog("DeskPet[debug]: no saved position")
        }
        NSLog("DeskPet[debug]: hiddenByUser=\(state.persistence.petHiddenByUser)")
    }
}
#endif

/// Bundle metadata, read once. Falls back to literals when running under
/// `swift test`, where there is no app bundle.
public enum AppInfo {
    public static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    public static let bundleIdentifier: String =
        Bundle.main.bundleIdentifier ?? "com.dhanushprince.deskpet"

    public static let name = "DeskPet"
}
