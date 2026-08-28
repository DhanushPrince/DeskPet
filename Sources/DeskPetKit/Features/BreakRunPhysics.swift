import CoreGraphics
import Foundation

/// Physics for the break run, where the pet skitters around the screen to make
/// the user get up.
///
/// Ported from `chooseBreakRunVelocity` and `movePetForBreakRun` in `main.ts`.
/// Pure so the bouncing, the turn cadence, and the velocity bounds can be
/// asserted without a window or a run loop.
public enum BreakRunPhysics {

    /// Position, heading, and when the pet may next change direction.
    public struct State: Equatable, Sendable {
        /// Window origin in the global top-left space.
        public var position: CGPoint
        /// Pixels per tick.
        public var velocity: CGPoint
        public var nextTurnAt: Date

        public init(position: CGPoint, velocity: CGPoint, nextTurnAt: Date) {
            self.position = position
            self.velocity = velocity
            self.nextTurnAt = nextTurnAt
        }
    }

    /// Source of randomness, returning values in `0..<1`. Injected so tests can
    /// supply a fixed sequence. Deliberately non-cryptographic.
    public typealias RandomSource = () -> Double

    public static func systemRandom() -> Double {
        Double.random(in: 0..<1)
    }

    /// A new heading at a random angle and speed.
    ///
    /// Draws speed first and then angle, matching the original call order so a
    /// scripted random sequence lines up.
    public static func chooseVelocity(random: RandomSource) -> CGPoint {
        let speed = Constants.BreakRun.speedBase + random() * Constants.BreakRun.speedRange
        let angle = random() * 2 * .pi
        return CGPoint(x: cos(angle) * speed, y: sin(angle) * speed)
    }

    /// Travel limits for the window origin, inset from the work area.
    public static func limits(
        workArea: GlobalRect,
        size: CGSize
    ) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let inset = Constants.BreakRun.edgeInset
        return (
            minX: workArea.x + inset,
            maxX: workArea.x + workArea.width - size.width - inset,
            minY: workArea.y + inset,
            maxY: workArea.y + workArea.height - size.height - inset
        )
    }

    /// Advances one 16ms tick.
    ///
    /// Order is significant and matches the original: the turn roll happens
    /// before the move, edges are clamped with `<=` / `>=` so touching a
    /// boundary flips the axis, and the next turn deadline is refreshed whenever
    /// the current one has elapsed — whether or not the 45% roll succeeded.
    public static func step(
        _ state: State,
        workArea: GlobalRect,
        size: CGSize,
        now: Date,
        random: RandomSource
    ) -> State {
        var next = state
        let mayTurn = now >= state.nextTurnAt

        if mayTurn, random() < Constants.BreakRun.turnChance {
            next.velocity = chooseVelocity(random: random)
        }

        let bounds = limits(workArea: workArea, size: size)
        var x = next.position.x + next.velocity.x
        var y = next.position.y + next.velocity.y

        // Each edge pins the position and forces the velocity's sign outward,
        // rather than simply negating it, so a pet already pressed against an
        // edge cannot get stuck vibrating.
        if x <= bounds.minX {
            x = bounds.minX
            next.velocity.x = abs(next.velocity.x)
        }
        if x >= bounds.maxX {
            x = bounds.maxX
            next.velocity.x = -abs(next.velocity.x)
        }
        if y <= bounds.minY {
            y = bounds.minY
            next.velocity.y = abs(next.velocity.y)
        }
        if y >= bounds.maxY {
            y = bounds.maxY
            next.velocity.y = -abs(next.velocity.y)
        }

        if mayTurn {
            next.nextTurnAt = now.addingTimeInterval(nextTurnDelay(random: random))
        }

        next.position = CGPoint(x: DisplayGeometry.jsRound(x), y: DisplayGeometry.jsRound(y))
        return next
    }

    /// `350 + Math.round(Math.random() * 850)` milliseconds.
    public static func nextTurnDelay(random: RandomSource) -> TimeInterval {
        let jitter = DisplayGeometry.jsRound(random() * Constants.BreakRun.turnIntervalRange * 1000)
        return Constants.BreakRun.turnIntervalBase + jitter / 1000
    }

    /// Facing implied by the heading. Zero counts as rightward, matching
    /// `velocity.x >= 0 ? "right" : "left"`.
    public static func facing(for velocity: CGPoint) -> PetFacing {
        velocity.x >= 0 ? .right : .left
    }

    /// Whole seconds left, as the countdown bubble displays them.
    public static func remainingSeconds(until endsAt: Date, now: Date) -> Int {
        max(0, Int((endsAt.timeIntervalSince(now)).rounded(.up)))
    }
}
