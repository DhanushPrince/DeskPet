import Foundation

/// Polls for an active Teams call and reports hide/show to AppState.
///
/// Primary signal: IOPM assertion `"Microsoft Teams Call in progress"`
/// (see `TeamsCallDetector`). No Accessibility permission required.
public final class MeetingHideWatcher {
    public var onMeetingChange: (Bool) -> Void = { _ in }

    public private(set) var inMeeting = false

    private let isInCall: () -> Bool
    private var enabled = false
    private var pollTimer: Timer?

    public init(isInCall: @escaping () -> Bool = TeamsCallDetector.isInCall) {
        self.isInCall = isInCall
    }

    deinit {
        cancelTimer()
    }

    public func update(enabled: Bool) {
        self.enabled = enabled
        cancelTimer()

        guard enabled else {
            apply(inMeeting: false)
            return
        }

        checkNow()
        startPolling()
    }

    public func stop() {
        enabled = false
        cancelTimer()
    }

    /// True while the poll timer is running, for tests.
    public var isPolling: Bool { pollTimer != nil }

    public func checkNow() {
        guard enabled else { return }
        apply(inMeeting: isInCall())
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

    private func cancelTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkNowInBackground() {
        guard enabled else { return }
        let isInCall = self.isInCall
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let active = isInCall()
            DispatchQueue.main.async {
                self?.apply(inMeeting: active)
            }
        }
    }

    private func apply(inMeeting: Bool) {
        guard self.inMeeting != inMeeting else { return }
        self.inMeeting = inMeeting
        onMeetingChange(inMeeting)
    }
}
