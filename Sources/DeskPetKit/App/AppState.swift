import AppKit
import Observation
import UniformTypeIdentifiers

/// Composition root and single source of truth.
///
/// `@Observable` (ADR-5) so the SwiftUI settings window in Task 15 can read and
/// write the same state the AppKit pet window renders, without a second
/// notification mechanism.
@Observable
public final class AppState {
    // MARK: Dependencies

    @ObservationIgnored public let persistence: Persistence
    @ObservationIgnored public let stateMachine: PetStateMachine
    @ObservationIgnored public let petWindow: PetWindowController
    @ObservationIgnored public let scheduler: ReminderScheduler
    @ObservationIgnored public let breakRunner: BreakRunner
    @ObservationIgnored public let statsStore: StatsStore
    @ObservationIgnored public let distractionDetector: DistractionDetector
    @ObservationIgnored public let meetingHideWatcher: MeetingHideWatcher
    @ObservationIgnored public let updateChecker: UpdateChecking
    /// Watchers that poll only after `start()`, so constructing AppState in
    /// tests does not spin timers.
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored public let updateInstaller: UpdateInstalling
    @ObservationIgnored private let displayWatcher = DisplayChangeWatcher()
    @ObservationIgnored private let clock: DeskPetClock

    /// Set by the app delegate once the menu bar exists, so state changes can
    /// refresh the menu labels.
    @ObservationIgnored public var statusBar: StatusBarController?
    /// Task 15 replaces this with the real settings window.
    @ObservationIgnored public var onOpenSettings: (() -> Void)?
    /// Pending steps of timed sequences (happy reaction, break done, drinking).
    @ObservationIgnored private var sequenceTimers: [Timer] = []
    /// Debug menu: walks every `PetState` animation.
    @ObservationIgnored private var stateCycleTimer: Timer?
    /// Countdown phrasing, fixed for the duration of one break run.
    @ObservationIgnored private var breakRunPhrasing: ((Int) -> String)?
    /// Ends the focus session; separate from the badge refresh timer.
    @ObservationIgnored private var focusEndTimer: Timer?
    @ObservationIgnored private var focusBadgeTimer: Timer?
    @ObservationIgnored private var updateCheckTask: Task<Void, Never>?
    @ObservationIgnored private var stagedAppURL: URL?

    // MARK: Observable state

    /// Mirrors the pet's rendered state so observers can react.
    public private(set) var petState: PetState = .idle
    public private(set) var petVisible = false
    public private(set) var focusActive = false
    public private(set) var blockingMode: BlockingMode?
    /// Mirrors the detector so the settings window can show what it sees.
    public private(set) var distractionStatus = DistractionStatus()
    /// Temporary hide while Teams is in a call. Not persisted.
    public private(set) var hiddenForMeeting = false

    /// Written through to `UserDefaults` and applied to the running pet.
    public var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            persistence.settings = settings
            applySettings()
        }
    }

    public private(set) var stats: DayStats

    /// Human-readable result of the last update check.
    public private(set) var updateStatusMessage = Strings.SettingsLabels.updateIdle
    public private(set) var lastUpdateCheck = UpdateCheckResult(
        status: .idle,
        currentVersion: AppInfo.version
    )
    public private(set) var updateInstallPhase: UpdateInstallPhase = .idle
    public var canInstallUpdate: Bool { updateInstallPhase == .readyToInstall }

    /// Checks GitHub Releases. Manual checks from settings also show a bubble
    /// when a newer version exists, matching the Electron IPC handler.
    public func checkForUpdates(notifyAvailable: Bool = true) {
        updateCheckTask?.cancel()
        updateStatusMessage = Strings.SettingsLabels.updateChecking
        lastUpdateCheck.status = .checking
        updateCheckTask = Task { [weak self] in
            await self?.performUpdateCheck(notifyAvailable: notifyAvailable)
        }
    }

    public func performUpdateCheck(notifyAvailable: Bool) async {
        let current = UpdateCheckResult(
            status: .checking,
            currentVersion: AppInfo.version,
            releaseURL: lastUpdateCheck.releaseURL
        )
        let result = await updateChecker.check(current: current)
        guard !Task.isCancelled else { return }
        await MainActor.run { [weak self] in
            self?.applyUpdateCheck(result)
        }
        if result.status == .available {
            await prepareDownloadedUpdate(result)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.updateInstallPhase == .readyToInstall else { return }
                if notifyAvailable, let version = result.latestVersion {
                    self.showUpdateAvailableNotice(version: version)
                }
            }
        }
    }

    public init(
        persistence: Persistence,
        clock: DeskPetClock = SystemClock(),
        random: @escaping BreakRunPhysics.RandomSource = BreakRunPhysics.systemRandom,
        activeWindowReader: @escaping () throws -> ActiveWindowReading = ActiveWindowReader.read,
        teamsCallActive: @escaping () -> Bool = TeamsCallDetector.isInCall,
        updateChecker: UpdateChecking = GitHubUpdateChecker(),
        updateInstaller: UpdateInstalling? = nil
    ) {
        self.persistence = persistence
        self.clock = clock
        self.updateChecker = updateChecker
        self.updateInstaller = updateInstaller
            ?? FileUpdateInstaller(supportDirectory: persistence.supportDirectory)
        PetAssetLoader.supportDirectory = persistence.supportDirectory
        let loaded = persistence.settings
        self.settings = loaded
        let store = StatsStore(persistence: persistence, clock: clock)
        self.statsStore = store
        self.stats = store.current()
        self.stateMachine = PetStateMachine(clock: clock)
        self.petWindow = PetWindowController(savedPosition: persistence.petPosition)
        self.scheduler = ReminderScheduler(settings: loaded, clock: clock)
        self.breakRunner = BreakRunner(clock: clock, random: random)
        self.distractionDetector = DistractionDetector(
            settings: loaded,
            clock: clock,
            reader: activeWindowReader
        )
        self.meetingHideWatcher = MeetingHideWatcher(isInCall: teamsCallActive)

        wire()
    }

    private func wire() {
        stateMachine.onStateChange = { [weak self] state in
            guard let self else { return }
            self.petState = state
            self.petWindow.setState(state)
            self.syncDerivedState()
        }
        stateMachine.onRequestVisible = { [weak self] in
            self?.ensurePetVisible()
        }

        petWindow.isDragBlocked = { [weak self] in
            self?.stateMachine.blockingMode == .breakRun
        }
        petWindow.onPetClicked = { [weak self] in
            self?.handlePetClicked()
        }
        petWindow.onPositionChanged = { [weak self] position in
            self?.persistence.petPosition = position
        }
        petWindow.onContextMenu = { [weak self] event in
            guard let self else { return }
            self.statusBar?.showPetContextMenu(for: event, in: self.petWindow.contentView)
        }
        petWindow.onBubbleAction = { [weak self] id in
            self?.handleBubbleAction(id)
        }

        scheduler.onReminderDue = { [weak self] kind in
            self?.handleReminderDue(kind) ?? .deferred
        }
        scheduler.onMidnight = { [weak self] in
            self?.handleMidnight()
        }
        displayWatcher.onChange = { [weak self] in
            ScreenBridge.invalidateDisplayCache()
            self?.petWindow.clampIntoVisibleArea()
        }

        breakRunner.currentPosition = { [weak self] in
            guard let self else { return .zero }
            let bounds = self.petWindow.globalBounds
            return CGPoint(x: bounds.x, y: bounds.y)
        }
        breakRunner.workArea = { position in
            // Resolve per tick so the pet bounces within whichever display it is
            // currently over.
            let probe = GlobalRect(origin: position, size: Constants.petWindowSize)
            return DisplayGeometry.displayForBounds(
                displays: ScreenBridge.displays,
                bounds: probe,
                fallback: ScreenBridge.primaryDisplay
            ).workArea
        }
        breakRunner.onMove = { [weak self] position in
            guard let self else { return }
            self.petWindow.setGlobalBounds(
                GlobalRect(origin: position, size: Constants.petWindowSize)
            )
        }
        breakRunner.onFacingChange = { [weak self] facing in
            self?.petWindow.facing = facing
        }
        breakRunner.onCountdown = { [weak self] seconds in
            self?.showBreakRunCountdown(seconds: seconds)
        }
        breakRunner.onFinish = { [weak self] in
            self?.finishBreakRun()
        }

        distractionDetector.isFocusActive = { [weak self] in
            self?.stateMachine.focusActive ?? false
        }
        distractionDetector.blockingMode = { [weak self] in
            self?.stateMachine.blockingMode
        }
        distractionDetector.onWarning = { [weak self] rule in
            self?.triggerFocusWarning(rule: rule)
        }
        distractionDetector.onStatusChange = { [weak self] status in
            self?.distractionStatus = status
        }

        meetingHideWatcher.onMeetingChange = { [weak self] inMeeting in
            self?.applyMeetingHide(inMeeting)
        }

        applySettings()
    }

    /// Shows the pet unless the user hid it, then starts the timers.
    public func start() {
        isRunning = true
        if persistence.petHiddenByUser {
            NSLog("DeskPet: pet stays hidden (hidden by user)")
        } else {
            petWindow.show()
        }
        rollStatsDateIfNeeded()
        scheduler.start()
        displayWatcher.start()
        meetingHideWatcher.update(enabled: settings.hidePetDuringMeetings)
        syncDerivedState()
        syncLaunchAtLoginFromSystem()
        if settings.checkUpdatesOnLaunchEnabled {
            after(Constants.launchUpdateCheckDelay) { [weak self] in
                self?.checkForUpdates(notifyAvailable: true)
            }
        }
    }

    public func stop() {
        isRunning = false
        updateCheckTask?.cancel()
        updateCheckTask = nil
        stagedAppURL = nil
        updateInstallPhase = .idle
        scheduler.stop()
        displayWatcher.stop()
        breakRunner.cancel()
        distractionDetector.stop()
        meetingHideWatcher.stop()
        stopFocusTimers()
        cancelPendingSequences()
        stateCycleTimer?.invalidate()
        stateCycleTimer = nil
    }

    // MARK: - Reminders

    /// Task 14 adds the hydration bubble; the outcome reported here is what
    /// decides whether the due date is cleared or left as an overdue marker.
    private func handleReminderDue(_ kind: ReminderKind) -> ReminderOutcome {
        switch kind {
        case .breakReminder:
            if stateMachine.breakMutedToday { return .suppressed }
            guard stateMachine.triggerBreakReminder() else { return .deferred }
            presentBreakPrompt()
            return .accepted
        case .hydration:
            guard stateMachine.triggerHydrationReminder() else { return .deferred }
            presentHydrationPrompt()
            return .accepted
        }
    }

    // MARK: - Hydration flow

    /// Ported from the bubble in `triggerHydrationReminder`.
    private func presentHydrationPrompt() {
        showBubble(SpeechBubble(
            id: BubbleID.hydrationPrompt,
            message: Strings.pick(Strings.Bubble.hydrationReminder),
            actions: [
                BubbleAction(
                    id: BubbleActionID.hydrationDone,
                    label: Strings.Actions.hydrationDone,
                    kind: .primary
                ),
                BubbleAction(
                    id: BubbleActionID.hydrationSnooze,
                    label: Strings.Actions.hydrationSnooze
                )
            ]
        ))
    }

    /// Ported from the `hydration:done` action: drink, celebrate, then settle.
    private func completeHydrationPrompt() {
        statsStore.update { $0.watersLogged += 1 }
        stats = statsStore.current()

        stateMachine.beginDrinking()
        hideBubble()
        syncDerivedState()

        after(Constants.drinkingDuration) { [weak self] in
            guard let self, self.stateMachine.finishDrinking() else { return }
            self.showBubble(SpeechBubble(
                id: BubbleID.hydrationComplete,
                message: Strings.pick(Strings.Bubble.hydrationDone),
                autoDismissAfter: Constants.hydrationDoneBubbleDuration
            ))

            self.after(Constants.hydrationDoneReturnDelay) { [weak self] in
                guard let self else { return }
                // The next reminder is measured from the end of this one.
                self.scheduler.scheduleHydration()
                if self.showOverdueReminder() { return }
                self.hideBubble()
                self.stateMachine.settleAfterTransientState()
            }
        }
    }

    /// Ported from the `hydration:snooze` action.
    private func snoozeHydration() {
        hideBubble()
        stateMachine.resumeLongTermState()
        scheduler.snoozeHydration()
        syncDerivedState()
    }

    // MARK: - Break flow

    /// Ported from the bubble in `triggerBreakReminder`.
    private func presentBreakPrompt() {
        showBubble(SpeechBubble(
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
        ))
    }

    /// Ported from `startBreakRun`.
    public func startBreakRun() {
        ensurePetVisible()
        cancelPendingSequences()
        stateMachine.startBreakRun()
        // The run owns the pet's position, so the pending break is cleared.
        scheduler.clearBreak()

        // The phrasing is chosen once and reused for every countdown tick, so
        // the wording does not change each second.
        breakRunPhrasing = Strings.Bubble.breakRun.randomElement()
        breakRunner.start(duration: TimeInterval(settings.breakRunDurationSeconds))
        syncDerivedState()
    }

    private func showBreakRunCountdown(seconds: Int) {
        let phrasing = breakRunPhrasing ?? Strings.Bubble.breakRun[0]
        showBubble(SpeechBubble(
            id: BubbleID.breakRun,
            message: phrasing(seconds),
            actions: [
                BubbleAction(
                    id: BubbleActionID.breakRunDone,
                    label: Strings.Actions.breakRunDone,
                    kind: .primary
                )
            ]
        ))
    }

    /// Ported from `finishBreakRun`.
    public func finishBreakRun() {
        breakRunner.cancel()
        breakRunPhrasing = nil
        stateMachine.finishBreakRun()

        hideBubble()
        showBubble(SpeechBubble(
            id: BubbleID.breakRunComplete,
            message: Strings.pick(Strings.Bubble.breakRunComplete),
            autoDismissAfter: Constants.breakRunCompleteBubbleDuration
        ))
        // The next break is scheduled from the end of this one.
        scheduler.scheduleBreak()
        syncDerivedState()

        after(Constants.breakDoneReturnDelay) { [weak self] in
            self?.settleAfterSequence()
        }
    }

    /// Shared tail of the timed sequences: surface anything that came due while
    /// the pet was busy, otherwise return to rest.
    private func settleAfterSequence() {
        guard stateMachine.blockingMode == nil, !stateMachine.focusActive else { return }
        if showOverdueReminder() { return }
        hideBubble()
        stateMachine.settleAfterTransientState()
    }

    /// Ported from the `break:snooze` action.
    private func snoozeBreak() {
        hideBubble()
        stateMachine.resumeLongTermState()
        scheduler.snoozeBreak()
        syncDerivedState()
    }

    /// Ported from the `break:mute` action: the pet sulks, then settles, and
    /// break reminders stop until midnight.
    private func muteBreaksForToday() {
        stateMachine.muteBreaksForToday()
        scheduler.setBreakMuted(true)
        showBubble(SpeechBubble(
            id: BubbleID.breakMuted,
            message: Strings.pick(Strings.Bubble.breakIgnore),
            autoDismissAfter: Constants.breakMutedBubbleDuration
        ))
        syncDerivedState()

        after(Constants.breakMutedBubbleDuration + 0.1) { [weak self] in
            guard let self else { return }
            self.hideBubble()
            if self.showOverdueReminder() { return }
            self.stateMachine.resumeLongTermState()
        }
    }

    /// Ported from the `break:done` action.
    private func completeBreakPrompt() {
        statsStore.update { $0.breaksTaken += 1 }
        stats = statsStore.current()
        startBreakRun()
    }

    /// Ported from the `showOverdueReminder` call sites: after any blocking mode
    /// ends, a reminder that came due meanwhile fires instead of the pet simply
    /// returning to idle.
    @discardableResult
    public func showOverdueReminder() -> Bool {
        guard stateMachine.allowsOverdueReminder else { return false }
        return scheduler.showOverdueReminder()
    }

    /// Midnight rollover: clears the break mute and starts a fresh stats day.
    /// The Electron build only cleared the mute on relaunch.
    private func handleMidnight() {
        NSLog("DeskPet: midnight rollover")
        stateMachine.resetMuteForNewDay()
        scheduler.setBreakMuted(false)
        rollStatsDateIfNeeded()
    }

    private func rollStatsDateIfNeeded() {
        // The store archives the outgoing day and adopts today, reusing an
        // existing entry if the app already ran earlier today.
        stats = statsStore.current()
    }

    // MARK: - Settings

    private func applySettings() {
        petWindow.appearance = settings.petAppearanceID
        petWindow.customAppearance = settings.customPetAppearance
        // Interval or enablement changes take effect without a restart.
        scheduler.update(settings: settings)
        distractionDetector.update(settings: settings)
        if isRunning {
            meetingHideWatcher.update(enabled: settings.hidePetDuringMeetings)
        }
        LoginItemService.apply(enabled: settings.launchAtLoginEnabled)
    }

    private func syncLaunchAtLoginFromSystem() {
        let resolved = LoginItemService.resolvedPreference(settings.launchAtLoginEnabled)
        guard resolved != settings.launchAtLoginEnabled else { return }
        updateSettings { $0.launchAtLoginEnabled = resolved }
    }

    /// Mutates settings in place, persisting once.
    public func updateSettings(_ mutate: (inout Settings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next.normalized()
    }

    // MARK: - Custom assets

    /// Opens an `NSOpenPanel` filtered to GIFs and imports the selection.
    public func chooseCustomAsset(for state: PetState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importCustomAsset(from: url, for: state)
    }

    @discardableResult
    public func importCustomAsset(from source: URL, for state: PetState) -> CustomPetAsset? {
        PetAssetLoader.supportDirectory = persistence.supportDirectory
        guard let asset = CustomAssetImporter.importGIF(
            state: state,
            from: source,
            into: persistence.supportDirectory,
            now: clock.now
        ) else { return nil }

        updateSettings { settings in
            var custom = settings.customPetAppearance
                ?? CustomPetAppearance(name: Strings.SettingsLabels.customPet, assets: [:])
            custom.assets[state] = asset
            settings.customPetAppearance = custom
            if PetAppearances.hasRequiredAssets(custom) {
                settings.petAppearanceID = .custom
            }
        }
        return asset
    }

    public func removeCustomAsset(for state: PetState) {
        updateSettings { settings in
            guard var custom = settings.customPetAppearance else { return }
            custom.assets.removeValue(forKey: state)
            settings.customPetAppearance = custom.assets.isEmpty ? nil : custom
            if settings.petAppearanceID == .custom,
               !PetAppearances.hasRequiredAssets(settings.customPetAppearance) {
                settings.petAppearanceID = Settings.defaults.petAppearanceID
            }
        }
    }

    // MARK: - Pet visibility

    public var petHiddenByUser: Bool {
        persistence.petHiddenByUser
    }

    public func togglePetVisibility() {
        if petWindow.isVisible {
            hidePet()
        } else {
            showPet()
        }
    }

    /// Ported from `showPetWindowFromMenu`: clears the sticky hidden flag.
    public func showPet() {
        persistence.petHiddenByUser = false
        petWindow.show()
        syncDerivedState()
    }

    /// Ported from `hidePetWindowFromMenu`: the choice persists across launches.
    public func hidePet() {
        persistence.petHiddenByUser = true
        petWindow.hide()
        syncDerivedState()
    }

    /// Ported from `ensurePetWindowVisible`: a reminder must not resurrect a pet
    /// the user deliberately hid, and a Teams call must keep it off-screen.
    private func ensurePetVisible() {
        guard !persistence.petHiddenByUser else { return }
        guard !hiddenForMeeting else { return }
        guard !petWindow.isVisible else { return }
        petWindow.show()
        syncDerivedState()
    }

    private func applyMeetingHide(_ inMeeting: Bool) {
        hiddenForMeeting = inMeeting
        if inMeeting {
            petWindow.hide()
            syncDerivedState()
        } else {
            ensurePetVisible()
        }
    }

    // MARK: - Interactions

    private func handlePetClicked() {
        // Ported from the `pet:clicked` handler, which passed a nil message so
        // the pet reacts without saying anything.
        happyFeedback(message: nil)
    }

    /// Ported from `happyFeedback`: a brief happy animation, optionally with a
    /// bubble, then back to the long-term state.
    public func happyFeedback(message: String?) {
        guard stateMachine.beginHappyFeedback() else { return }
        if let message {
            showBubble(SpeechBubble(
                id: BubbleID.happy,
                message: message,
                autoDismissAfter: Constants.happyBubbleDuration
            ))
        }
        after(Constants.happyReturnDelay) { [weak self] in
            guard let self else { return }
            self.hideBubble()
            self.stateMachine.settleAfterTransientState()
        }
    }

    private func applyUpdateCheck(_ result: UpdateCheckResult) {
        lastUpdateCheck = result
        if result.status != .available {
            updateInstallPhase = .idle
            stagedAppURL = nil
        }
        switch result.status {
        case .available:
            if let version = result.latestVersion {
                updateStatusMessage = Strings.SettingsLabels.updateAvailable(version)
            }
        case .upToDate:
            updateStatusMessage = Strings.SettingsLabels.updateCurrent(result.currentVersion)
        case .error:
            updateStatusMessage = Strings.SettingsLabels.updateError(result.error ?? "")
        case .checking:
            updateStatusMessage = Strings.SettingsLabels.updateChecking
        case .idle:
            updateStatusMessage = Strings.SettingsLabels.updateIdle
        }
    }

    private func prepareDownloadedUpdate(_ result: UpdateCheckResult) async {
        let version = result.latestVersion ?? ""
        let url = result.dmgURL ?? Constants.dmgDownloadURL
        await MainActor.run { [weak self] in
            self?.updateInstallPhase = .downloading
            self?.updateStatusMessage = Strings.SettingsLabels.updateDownloading(version)
        }
        do {
            let dmg: URL
            if let cached = updateInstaller.cachedDMG(
                version: version,
                expectedByteCount: result.dmgByteCount
            ) {
                dmg = cached
            } else {
                dmg = try await updateInstaller.download(
                    from: url,
                    version: version,
                    expectedByteCount: result.dmgByteCount
                )
            }
            guard !Task.isCancelled else { return }
            let staged = try updateInstaller.stageApp(fromDMG: dmg, currentVersion: AppInfo.version)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.stagedAppURL = staged
                self.updateInstallPhase = .readyToInstall
                self.updateStatusMessage = Strings.SettingsLabels.updateReady(version)
            }
        } catch {
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updateInstallPhase = .idle
                self.stagedAppURL = nil
                self.updateStatusMessage = Strings.SettingsLabels.updateError(
                    Self.installErrorMessage(error)
                )
            }
        }
    }

    /// Replaces the running bundle with the staged app, then quits so the helper can relaunch.
    public func installReadyUpdate() {
        guard updateInstallPhase == .readyToInstall, let stagedAppURL else { return }
        updateInstallPhase = .installing
        hideBubble()
        stateMachine.settleAfterTransientState()
        do {
            try updateInstaller.installAndRelaunch(
                destination: Bundle.main.bundleURL,
                stagedApp: stagedAppURL
            )
            if Bundle.main.bundleIdentifier == "com.dhanushprince.deskpet" {
                NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
            }
        } catch {
            updateInstallPhase = .readyToInstall
            updateStatusMessage = Strings.SettingsLabels.updateError(Self.installErrorMessage(error))
        }
    }

    private static func installErrorMessage(_ error: Error) -> String {
        guard let error = error as? UpdateInstallerError else {
            return error.localizedDescription
        }
        switch error {
        case .downloadFailed: return "Couldn’t download the installer"
        case .sizeMismatch: return "Downloaded file was incomplete"
        case .mountFailed: return "Couldn’t open the installer disk image"
        case .missingApp: return "The disk image has no DeskPet app"
        case .notNewer: return "The downloaded app is not newer"
        case .installFailed: return "Couldn’t start the installer"
        }
    }

    /// Shown once the DMG is cached and the new app is staged.
    private func showUpdateAvailableNotice(version: String) {
        guard stateMachine.blockingMode == nil else { return }
        ensurePetVisible()
        guard stateMachine.beginHappyFeedback() else { return }
        showBubble(SpeechBubble(
            id: BubbleID.updateAvailable,
            message: Strings.Bubble.pick(Strings.Bubble.updateAvailable, version),
            actions: [
                BubbleAction(
                    id: BubbleActionID.installUpdate,
                    label: Strings.Actions.installUpdate,
                    kind: .primary
                ),
                BubbleAction(
                    id: BubbleActionID.dismissUpdate,
                    label: Strings.Actions.updateLater
                ),
                BubbleAction(
                    id: BubbleActionID.openReleaseNotes,
                    label: Strings.Actions.openReleaseNotes
                )
            ],
            autoDismissAfter: Constants.updateAvailableBubbleDuration
        ))
        after(Constants.updateAvailableBubbleDuration + 0.1) { [weak self] in
            guard let self else { return }
            guard self.stateMachine.blockingMode == nil, self.petState == .happy else { return }
            self.stateMachine.settleAfterTransientState()
        }
    }

    // MARK: - Bubbles

    public func showBubble(_ bubble: SpeechBubble) {
        petWindow.showBubble(bubble)
    }

    public func hideBubble() {
        petWindow.hideBubble()
    }

    /// Routed from bubble button taps. Task 14 fills in hydration and focus.
    private func handleBubbleAction(_ id: String) {
        switch id {
        case BubbleActionID.breakDone:
            completeBreakPrompt()
        case BubbleActionID.breakSnooze:
            snoozeBreak()
        case BubbleActionID.breakMute:
            muteBreaksForToday()
        case BubbleActionID.breakRunDone:
            finishBreakRun()
        case BubbleActionID.hydrationDone:
            completeHydrationPrompt()
        case BubbleActionID.hydrationSnooze:
            snoozeHydration()
        case BubbleActionID.focusBack:
            returnToFocus()
        case BubbleActionID.focusEnd:
            stopFocus(completed: false)
        case BubbleActionID.openReleaseNotes:
            hideBubble()
            stateMachine.settleAfterTransientState()
            NSWorkspace.shared.open(lastUpdateCheck.releaseURL)
        case BubbleActionID.installUpdate:
            installReadyUpdate()
        case BubbleActionID.dismissUpdate:
            hideBubble()
            stateMachine.settleAfterTransientState()
        default:
            NSLog("DeskPet: unhandled bubble action \(id)")
        }
    }

    /// Schedules follow-up work for a timed sequence. Uses the run loop rather
    /// than the injected clock because these are short UI delays, not
    /// wall-clock deadlines.
    func after(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in work() }
        RunLoop.main.add(timer, forMode: .common)
        sequenceTimers.append(timer)
        sequenceTimers.removeAll { !$0.isValid }
    }

    /// Cancels any pending sequence step, so a new prompt does not get clobbered
    /// by an older sequence's tail.
    func cancelPendingSequences() {
        sequenceTimers.forEach { $0.invalidate() }
        sequenceTimers.removeAll()
    }

    // MARK: - Focus

    /// Absolute end of the current focus session, for the countdown badge.
    public private(set) var focusEndsAt: Date?

    /// Ported from `startFocusMode`.
    public func startFocus() {
        guard stateMachine.startFocus() else { return }

        let minutes = settings.focusDurationMinutes
        let duration = TimeInterval(max(1, minutes)) * 60
        focusEndsAt = clock.now.addingTimeInterval(duration)

        showBubble(SpeechBubble(
            id: BubbleID.focusStart,
            message: Strings.Bubble.pick(Strings.Bubble.focusStart, minutes),
            autoDismissAfter: Constants.focusStartBubbleDuration
        ))
        startFocusTimers(duration: duration)
        // Re-arm detection so the grace period applies from the session's start,
        // matching `scheduleDistractionDetection` being called from
        // `startFocusMode`.
        distractionDetector.update(settings: settings)
        syncDerivedState()
    }

    /// Ported from `stopFocusMode`.
    ///
    /// - Parameter completed: true when the session ran its course, false when
    ///   the user ended it early. Selects between the two closing messages.
    public func stopFocus(completed: Bool) {
        guard let minutes = stateMachine.stopFocus() else { return }

        stopFocusTimers()
        focusEndsAt = nil
        petWindow.hideFocusBadge()
        // A new session should be able to warn immediately after its grace
        // period rather than inheriting this session's cooldown.
        distractionDetector.resetCooldown()
        distractionDetector.update(settings: settings)

        statsStore.update { $0.focusMinutes += minutes }
        stats = statsStore.current()

        showBubble(SpeechBubble(
            id: BubbleID.focusComplete,
            message: Strings.pick(
                completed ? Strings.Bubble.focusComplete : Strings.Bubble.focusCancelled
            ),
            autoDismissAfter: Constants.focusCompleteBubbleDuration
        ))
        syncDerivedState()

        after(Constants.focusCompleteReturnDelay) { [weak self] in
            self?.settleAfterSequence()
        }
    }

    /// Ported from the `focus:back` action.
    private func returnToFocus() {
        stateMachine.returnToFocus()
        showBubble(SpeechBubble(
            id: BubbleID.focusBack,
            message: Strings.pick(Strings.Bubble.focusBack),
            autoDismissAfter: Constants.focusBackBubbleDuration
        ))
        syncDerivedState()

        after(Constants.focusBackReturnDelay) { [weak self] in
            guard let self, self.stateMachine.focusActive,
                  self.stateMachine.blockingMode == nil else { return }
            self.hideBubble()
        }
    }

    /// Raises a distraction nudge. Task 16 supplies the matched rule.
    public func triggerFocusWarning(rule: String) {
        guard stateMachine.triggerFocusWarning() else { return }
        statsStore.update { $0.focusWarnings += 1 }
        stats = statsStore.current()

        showBubble(SpeechBubble(
            id: BubbleID.focusWarning,
            message: Strings.Bubble.pick(Strings.Bubble.focusWarning, rule),
            actions: [
                BubbleAction(
                    id: BubbleActionID.focusBack,
                    label: Strings.Actions.focusBack,
                    kind: .primary
                ),
                BubbleAction(id: BubbleActionID.focusEnd, label: Strings.Actions.focusEnd)
            ]
        ))
        syncDerivedState()
    }

    /// One timer ends the session; a second refreshes the countdown badge.
    private func startFocusTimers(duration: TimeInterval) {
        stopFocusTimers()

        let end = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            self?.stopFocus(completed: true)
        }
        RunLoop.main.add(end, forMode: .common)
        focusEndTimer = end

        refreshFocusBadge()
        let badge = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshFocusBadge()
        }
        RunLoop.main.add(badge, forMode: .common)
        focusBadgeTimer = badge
    }

    private func stopFocusTimers() {
        focusEndTimer?.invalidate()
        focusEndTimer = nil
        focusBadgeTimer?.invalidate()
        focusBadgeTimer = nil
    }

    /// Updates the badge from the remaining time. Public so tests can drive it
    /// without waiting on the run loop.
    public func refreshFocusBadge() {
        guard stateMachine.focusActive, let focusEndsAt else {
            petWindow.hideFocusBadge()
            return
        }
        let remaining = max(0, focusEndsAt.timeIntervalSince(clock.now))
        petWindow.showFocusBadge(remainingSeconds: Int(remaining.rounded(.up)))
    }

    /// Opens System Settings at Privacy & Security › Accessibility.
    public func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Stats

    /// Ported from `resetTodayStats`.
    public func resetTodayStats() {
        stateMachine.resetMuteForNewDay()
        scheduler.setBreakMuted(false)
        stats = statsStore.resetToday()
    }

    // MARK: - Menu

    public var menuState: MenuState {
        MenuState(petVisible: petVisible, focusActive: focusActive)
    }

    public func handle(_ action: MenuAction) {
        switch action {
        case .togglePet: togglePetVisibility()
        case .hidePet: hidePet()
        case .startFocus: startFocus()
        case .stopFocusCompleted: stopFocus(completed: true)
        case .stopFocusCancelled: stopFocus(completed: false)
        case .openSettings: onOpenSettings?()
        case .quit:
            // Status-item menus run in the tracking run loop; `terminate:` from
            // that turn is ignored. Fire after the menu has dismissed.
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)

        case .demoBreak:
            if stateMachine.triggerBreakReminder(fromDemo: true) {
                presentBreakPrompt()
            } else {
                NSLog("DeskPet: demo break refused (blocking=\(stateMachine.blockingMode?.rawValue ?? "none"))")
            }
        case .demoHydration:
            if stateMachine.triggerHydrationReminder(fromDemo: true) {
                presentHydrationPrompt()
            } else {
                NSLog("DeskPet: demo hydration refused (blocking=\(stateMachine.blockingMode?.rawValue ?? "none"))")
            }
        case .demoFocusWarning: triggerFocusWarning(rule: "Twitter")
        case .demoHappy:
            // Happy feedback refuses any blocking prompt; demos clear it first.
            clearBlockingForDemo()
            happyFeedback(message: Strings.pick(Strings.Bubble.woof))
        case .debugCycleStates:
            clearBlockingForDemo()
            cycleStatesForDebugging()
        }
    }

    /// Demo menu items must work even when a break/water prompt is open.
    private func clearBlockingForDemo() {
        cancelPendingSequences()
        stateCycleTimer?.invalidate()
        stateCycleTimer = nil
        if stateMachine.blockingMode == .breakRun {
            breakRunner.cancel()
        }
        hideBubble()
        if stateMachine.blockingMode != nil {
            stateMachine.resumeLongTermState()
        }
        ensurePetVisible()
        syncDerivedState()
    }

    /// Keeps the published mirrors and the menu labels in step with the machine
    /// and the window.
    private func syncDerivedState() {
        petVisible = petWindow.isVisible
        focusActive = stateMachine.focusActive
        blockingMode = stateMachine.blockingMode
        statusBar?.refresh()
    }

    // MARK: - Debug

    private func cycleStatesForDebugging() {
        // Menu actions run inside the tracking run loop. A timer scheduled there
        // dies with the menu; defer onto the main run loop in `.common` mode.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateCycleTimer?.invalidate()

            var index = 0
            let states = PetState.allCases
            let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                if index >= states.count {
                    timer.invalidate()
                    self.stateCycleTimer = nil
                    self.stateMachine.debugForceState(self.stateMachine.longTermState)
                    return
                }
                NSLog("DeskPet: cycle state \(states[index].rawValue)")
                self.stateMachine.debugForceState(states[index])
                index += 1
            }
            self.stateCycleTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            timer.fire()
        }
    }
}
