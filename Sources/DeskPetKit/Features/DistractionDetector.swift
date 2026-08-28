import AppKit
import Foundation

/// Polls the frontmost window and raises focus warnings for blocked apps or
/// keywords.
///
/// Ported from `checkDistractionNow` and `scheduleDistractionDetection`.
public final class DistractionDetector {
    /// Raised with the display form of the matched rule.
    public var onWarning: (String) -> Void = { _ in }
    public var onStatusChange: (DistractionStatus) -> Void = { _ in }

    /// Supplied by AppState, since the guards depend on live focus state.
    public var isFocusActive: () -> Bool = { false }
    public var blockingMode: () -> BlockingMode? = { nil }

    public private(set) var status = DistractionStatus()

    private let clock: DeskPetClock
    /// Injected so tests can drive detection without a real frontmost app.
    private let reader: () throws -> ActiveWindowReading
    private var settings: Settings
    private var startupTimer: Timer?
    private var pollTimer: Timer?

    public init(
        settings: Settings,
        clock: DeskPetClock = SystemClock(),
        reader: @escaping () throws -> ActiveWindowReading = ActiveWindowReader.read
    ) {
        self.settings = settings
        self.clock = clock
        self.reader = reader
    }

    deinit {
        cancelTimers()
    }

    // MARK: Lifecycle

    /// Ported from `scheduleDistractionDetection`.
    ///
    /// When focus is already running the first check waits out the grace period,
    /// so starting a session on a blocked app does not fire instantly.
    public func update(settings newSettings: Settings) {
        settings = newSettings
        cancelTimers()

        guard settings.distractionDetectionEnabled else {
            var next = status
            next.state = .idle
            next.matchedRule = nil
            next.error = nil
            apply(next)
            return
        }

        var next = status
        next.state = .watching
        next.error = nil
        apply(next)

        let graceDelay = isFocusActive()
            ? max(0, TimeInterval(settings.distractionGraceSeconds))
            : 0

        let startup = Timer(timeInterval: graceDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.checkNow()
            self.startPolling()
        }
        RunLoop.main.add(startup, forMode: .common)
        startupTimer = startup
    }

    public func stop() {
        cancelTimers()
        var next = status
        next.state = .idle
        next.matchedRule = nil
        apply(next)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(
            timeInterval: Constants.distractionCheckInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkNowInBackground()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func cancelTimers() {
        startupTimer?.invalidate()
        startupTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// True while the poll timer is running, for tests.
    public var isPolling: Bool { pollTimer != nil }

    // MARK: Checking

    /// Timer path: Accessibility reads can hitch the main thread, so run them
    /// off-main and hop back to apply status / warnings.
    private func checkNowInBackground() {
        guard settings.distractionDetectionEnabled else { return }
        let reader = self.reader
        let settings = self.settings
        let focusActive = isFocusActive()
        let blocking = blockingMode()
        let lastWarning = status.lastWarningAt
        let now = clock.now

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let outcome: Result<ActiveWindowReading, Error> = Result { try reader() }
            DispatchQueue.main.async {
                self?.applyCheck(
                    outcome,
                    settings: settings,
                    focusActive: focusActive,
                    blockingMode: blocking,
                    lastWarningAt: lastWarning,
                    now: now
                )
            }
        }
    }

    /// One detection pass. Public so tests can drive it directly (synchronous).
    public func checkNow() {
        guard settings.distractionDetectionEnabled else { return }
        let outcome: Result<ActiveWindowReading, Error> = Result { try reader() }
        applyCheck(
            outcome,
            settings: settings,
            focusActive: isFocusActive(),
            blockingMode: blockingMode(),
            lastWarningAt: status.lastWarningAt,
            now: clock.now
        )
    }

    private func applyCheck(
        _ outcome: Result<ActiveWindowReading, Error>,
        settings: Settings,
        focusActive: Bool,
        blockingMode: BlockingMode?,
        lastWarningAt: Date?,
        now: Date
    ) {
        switch outcome {
        case .success(let reading):
            let active = reading.info
            let match = DistractionClassifier.classify(active, settings: settings)

            var next = status
            // Without the title, app rules still match but keyword rules can only
            // see the app name, so the status stays honest about the gap.
            next.state = reading.titlePermissionDenied ? .permissionNeeded : .watching
            next.activeApp = active.appName
            next.activeWindowTitle = active.windowTitle
            next.matchedRule = match.map(DistractionClassifier.displayRule)
            next.lastCheckedAt = now
            next.error = reading.titlePermissionDenied
                ? "DeskPet needs Accessibility permission to read window titles. "
                    + "Blocked apps are still detected."
                : nil

            guard DistractionClassifier.shouldWarn(
                matchedRule: match,
                focusActive: focusActive,
                blockingMode: blockingMode,
                lastWarningAt: lastWarningAt,
                now: now
            ) else {
                apply(next)
                return
            }

            next.lastWarningAt = now
            apply(next)
            onWarning(DistractionClassifier.displayRule(match!))

        case .failure(let error):
            var next = status
            next.state = (error as? ActiveWindowError) == .permissionDenied
                ? .permissionNeeded
                : .error
            next.error = describe(error)
            next.lastCheckedAt = now
            apply(next)
        }
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case ActiveWindowError.permissionDenied:
            return "DeskPet needs Accessibility permission to see the active window."
        case ActiveWindowError.noFrontmostApplication:
            return "No frontmost application."
        case ActiveWindowError.accessibility(let code):
            return "Accessibility error \(code)."
        default:
            return String(describing: error)
        }
    }

    private func apply(_ next: DistractionStatus) {
        guard next != status else { return }
        status = next
        onStatusChange(next)
    }

    /// Clears the cooldown, used when a focus session ends.
    public func resetCooldown() {
        var next = status
        next.lastWarningAt = nil
        apply(next)
    }
}
