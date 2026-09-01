import CoreGraphics
import Foundation

/// Values ported from `src/main/config.ts` and from literals embedded in
/// `src/main/main.ts`. Kept in one place so parity with the Electron build is
/// auditable.
public enum Constants {
    // MARK: Identity

    public static let appName = "DeskPet"
    /// electron-store file name; the migration reader looks for `<this>.json`.
    public static let legacyStoreName = "deskpet"
    public static let releasesAPIURL = URL(
        string: "https://api.github.com/repos/DhanushPrince/DeskPet/releases/latest"
    )!
    public static let releasesURL = URL(
        string: "https://github.com/DhanushPrince/DeskPet/releases"
    )!
    /// Stable asset URL; the same file the README download link serves.
    public static let dmgDownloadURL = URL(
        string: "https://github.com/DhanushPrince/DeskPet/releases/latest/download/DeskPet.dmg"
    )!

    // MARK: Window geometry

    public static let petWindowSize = CGSize(width: 220, height: 340)
    /// Drawn size of the pet GIF inside the window. Matches `.pet-button` /
    /// `img` in the Electron CSS (184×184, bottom-centred). Leaving the upper
    /// band empty is what keeps speech bubbles from covering the pet.
    public static let petSpriteSize = CGSize(width: 184, height: 184)
    public static let settingsWindowSize = CGSize(width: 760, height: 680)
    public static let settingsWindowMinHeight: CGFloat = 400

    /// Cocoa (bottom-left) frame for the pet sprite inside a pet window.
    public static func petSpriteFrame(inWindowSize size: CGSize = petWindowSize) -> CGRect {
        CGRect(
            x: ((size.width - petSpriteSize.width) / 2).rounded(),
            y: 0,
            width: petSpriteSize.width,
            height: petSpriteSize.height
        )
    }

    /// Same sprite frame in DeskPet top-left window coordinates.
    public static func petSpriteFrameTopLeft(inWindowSize size: CGSize = petWindowSize) -> CGRect {
        let cocoa = petSpriteFrame(inWindowSize: size)
        return CGRect(
            x: cocoa.minX,
            y: size.height - cocoa.maxY,
            width: cocoa.width,
            height: cocoa.height
        )
    }

    // MARK: Timing

    /// Break-run physics tick, matching `BREAK_RUN_TICK_MS`.
    public static let breakRunTick: TimeInterval = 0.016
    public static let distractionCheckInterval: TimeInterval = 3
    public static let distractionWarningCooldown: TimeInterval = 60

    public static let breakSnooze: TimeInterval = 10 * 60
    public static let hydrationSnooze: TimeInterval = 15 * 60

    /// Safety net that ends a drag if the mouse-up event is never seen.
    public static let dragSafetyTimeout: TimeInterval = 15
    /// Coalesces bursts of display-change notifications.
    public static let displayChangeDebounce: TimeInterval = 0.25
    /// Delay before the launch-time update check.
    public static let launchUpdateCheckDelay: TimeInterval = 1.5

    // MARK: Bubble and sequence durations

    public static let happyBubbleDuration: TimeInterval = 1.8
    public static let happyReturnDelay: TimeInterval = 1.9
    public static let breakRunCompleteBubbleDuration: TimeInterval = 2.2
    public static let breakDoneReturnDelay: TimeInterval = 2.3
    public static let breakMutedBubbleDuration: TimeInterval = 2.6
    public static let drinkingDuration: TimeInterval = 2.4
    public static let hydrationDoneBubbleDuration: TimeInterval = 1.8
    public static let hydrationDoneReturnDelay: TimeInterval = 1.9
    public static let focusStartBubbleDuration: TimeInterval = 4.5
    public static let focusCompleteBubbleDuration: TimeInterval = 2.8
    public static let focusCompleteReturnDelay: TimeInterval = 2.9
    public static let focusBackBubbleDuration: TimeInterval = 1.8
    public static let focusBackReturnDelay: TimeInterval = 1.9
    public static let updateAvailableBubbleDuration: TimeInterval = 12

    // MARK: Break-run physics

    public enum BreakRun {
        /// Speed is `base + random * range` pixels per tick.
        public static let speedBase: Double = 3.5
        public static let speedRange: Double = 2.9
        /// Keeps the pet this far inside the work area.
        public static let edgeInset: Double = 8
        /// Probability of picking a new heading once the turn interval elapses.
        public static let turnChance: Double = 0.45
        /// Next turn is allowed after `turnIntervalBase + random * turnIntervalRange`.
        public static let turnIntervalBase: TimeInterval = 0.350
        public static let turnIntervalRange: TimeInterval = 0.850
    }

    // MARK: Interaction

    /// Fraction of the pet window treated as the pet's body for hit testing.
    /// `PET_HITBOX_SCALE` in `petHitbox.ts`.
    public static let hitboxScale: Double = 0.8
    /// Pointer travel beyond this during a press counts as a drag, not a click.
    /// `DRAG_START_DISTANCE_PX` in `PetView.tsx`.
    public static let dragThreshold: Double = 10

    // MARK: Animation variants

    /// States that persist long enough to warrant rotating between variants.
    /// `CONTINUOUS_ASSET_STATES` in `PetView.tsx`.
    public static let continuousAssetStates: Set<PetState> = [.idle, .focusGuard]
    /// `CONTINUOUS_ASSET_ROTATION_MS` in `PetView.tsx`.
    public static let continuousAssetRotation: TimeInterval = 15 * 60
}
