import Foundation

/// Drives a break run: moves the pet every tick, updates the countdown once a
/// second, and finishes after the configured duration.
///
/// Ported from `startBreakRun` / `movePetForBreakRun` / `finishBreakRun`. The
/// three timers of the original are kept separate for the same reason — the
/// movement cadence (16ms) and the countdown cadence (1s) differ by two orders
/// of magnitude.
public final class BreakRunner {
    /// Reports a new window origin in the global top-left space.
    public var onMove: (CGPoint) -> Void = { _ in }
    public var onFacingChange: (PetFacing) -> Void = { _ in }
    /// Whole seconds remaining, for the countdown bubble.
    public var onCountdown: (Int) -> Void = { _ in }
    public var onFinish: () -> Void = {}

    /// Current window origin, supplied by the caller so the run always starts
    /// from wherever the pet actually is.
    public var currentPosition: () -> CGPoint = { .zero }
    /// Work area of the display the pet is on, resolved per tick so the pet can
    /// bounce around whichever screen it currently occupies.
    public var workArea: (CGPoint) -> GlobalRect = { _ in
        GlobalRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private let clock: DeskPetClock
    private let random: BreakRunPhysics.RandomSource
    private let size: CGSize

    private var state: BreakRunPhysics.State?
    private var endsAt: Date?
    private var movementTimer: Timer?
    private var countdownTimer: Timer?
    private var finishTimer: Timer?
    private var facing: PetFacing = .right

    public init(
        size: CGSize = Constants.petWindowSize,
        clock: DeskPetClock = SystemClock(),
        random: @escaping BreakRunPhysics.RandomSource = BreakRunPhysics.systemRandom
    ) {
        self.size = size
        self.clock = clock
        self.random = random
    }

    deinit {
        cancelTimers()
    }

    public var isRunning: Bool { state != nil }
    public var remainingSeconds: Int? {
        endsAt.map { BreakRunPhysics.remainingSeconds(until: $0, now: clock.now) }
    }

    /// Begins a run of `duration` seconds.
    public func start(duration: TimeInterval) {
        cancelTimers()

        let now = clock.now
        let velocity = BreakRunPhysics.chooseVelocity(random: random)
        state = BreakRunPhysics.State(
            position: currentPosition(),
            velocity: velocity,
            // The original set nextBreakRunTurnAt to now, so the first tick may
            // already turn.
            nextTurnAt: now
        )
        endsAt = now.addingTimeInterval(duration)

        facing = BreakRunPhysics.facing(for: velocity)
        onFacingChange(facing)
        emitCountdown()

        let movement = Timer(timeInterval: Constants.breakRunTick, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(movement, forMode: .common)
        movementTimer = movement

        let countdown = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.emitCountdown()
        }
        RunLoop.main.add(countdown, forMode: .common)
        countdownTimer = countdown

        let finish = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            self?.finish()
        }
        RunLoop.main.add(finish, forMode: .common)
        finishTimer = finish
    }

    /// Ends the run and reports completion once.
    public func finish() {
        guard isRunning else { return }
        cancelTimers()
        state = nil
        endsAt = nil
        onFinish()
    }

    /// Ends the run without reporting completion, for teardown.
    public func cancel() {
        cancelTimers()
        state = nil
        endsAt = nil
    }

    /// One movement step. Public so tests can advance the run deterministically.
    public func tick() {
        guard let current = state else { return }

        let next = BreakRunPhysics.step(
            current,
            workArea: workArea(current.position),
            size: size,
            now: clock.now,
            random: random
        )
        state = next
        onMove(next.position)

        let nextFacing = BreakRunPhysics.facing(for: next.velocity)
        if nextFacing != facing {
            facing = nextFacing
            onFacingChange(nextFacing)
        }
    }

    private func emitCountdown() {
        guard let endsAt else { return }
        onCountdown(BreakRunPhysics.remainingSeconds(until: endsAt, now: clock.now))
    }

    private func cancelTimers() {
        movementTimer?.invalidate()
        countdownTimer?.invalidate()
        finishTimer?.invalidate()
        movementTimer = nil
        countdownTimer = nil
        finishTimer = nil
    }
}
