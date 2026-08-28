import AppKit

/// Coalesces display reconfiguration notifications.
///
/// Ported from `schedulePetDisplayRepair`. macOS emits several
/// `didChangeScreenParameters` notifications in quick succession when a display
/// is attached, removed, or resized, and repositioning the pet on each one makes
/// it jump; the Electron build debounced by 250ms for the same reason.
public final class DisplayChangeWatcher {
    /// Invoked once per settled burst of changes.
    public var onChange: () -> Void = {}

    private let debounceInterval: TimeInterval
    private var observer: NSObjectProtocol?
    private var pendingWork: DispatchWorkItem?

    public init(debounceInterval: TimeInterval = Constants.displayChangeDebounce) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stop()
    }

    public func start() {
        stop()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleChange()
        }
    }

    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        pendingWork?.cancel()
        pendingWork = nil
    }

    /// Restarts the debounce window. Exposed so tests can drive it without
    /// posting real notifications.
    public func scheduleChange() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingWork = nil
            self?.onChange()
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    /// True while a change is waiting to be delivered.
    public var hasPendingChange: Bool { pendingWork != nil }
}
