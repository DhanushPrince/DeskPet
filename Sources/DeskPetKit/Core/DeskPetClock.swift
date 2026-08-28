import Foundation

/// Time source, injected so every duration-dependent rule is testable without
/// waiting. The reminder scheduler in Task 11 uses the same abstraction to
/// compare against wall-clock time rather than accumulating interval drift.
public protocol DeskPetClock: AnyObject {
    var now: Date { get }
}

public final class SystemClock: DeskPetClock {
    public init() {}
    public var now: Date { Date() }
}

/// Manually advanced clock for tests.
public final class TestClock: DeskPetClock {
    public var now: Date

    public init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = now
    }

    public func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
