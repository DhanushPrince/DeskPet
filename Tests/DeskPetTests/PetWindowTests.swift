import AppKit
import Foundation
import Testing
@testable import DeskPetKit

@Suite("Pet animation")
struct PetAnimationTests {

    // MARK: keyTimes

    @Test("keyTimes has one more entry than frames and spans 0...1")
    func keyTimesShape() {
        let times = PetAnimator.keyTimes(durations: [0.1, 0.1, 0.2])
        #expect(times.count == 4)
        #expect(times.first?.doubleValue == 0)
        #expect(times.last?.doubleValue == 1)
    }

    @Test("keyTimes are the cumulative fractions of total duration")
    func keyTimesValues() {
        // Total 0.4 → frame boundaries at 0, 0.25, 0.5, then the closing 1.0.
        let times = PetAnimator.keyTimes(durations: [0.1, 0.1, 0.2]).map(\.doubleValue)
        #expect(times == [0, 0.25, 0.5, 1.0])
    }

    @Test("keyTimes are monotonically non-decreasing")
    func keyTimesMonotonic() {
        let times = PetAnimator.keyTimes(durations: [0.05, 0.3, 0.02, 0.11]).map(\.doubleValue)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(times.count == 5)
    }

    @Test("a single frame still produces a valid 0...1 range")
    func keyTimesSingleFrame() {
        let times = PetAnimator.keyTimes(durations: [0.1]).map(\.doubleValue)
        #expect(times == [0, 1.0])
    }

    @Test("zero total duration degrades to a full-span range")
    func keyTimesZeroDuration() {
        #expect(PetAnimator.keyTimes(durations: []).map(\.doubleValue) == [0, 1])
        #expect(PetAnimator.keyTimes(durations: [0, 0]).map(\.doubleValue) == [0, 1])
    }

    @Test("keyTimes derived from a real bundled GIF are well formed")
    func keyTimesFromRealGIF() throws {
        let definition = PetAppearances.assetDefinition(appearance: .lineDog, state: .idle)
        let url = try #require(PetAssetLoader.url(for: definition, variant: 0))
        let metadata = try GIFDecoder.probe(url: url)

        let times = PetAnimator.keyTimes(durations: metadata.frameDurations)
        #expect(times.count == metadata.frameCount + 1)
        #expect(times.first?.doubleValue == 0)
        #expect(times.last?.doubleValue == 1)
    }

    // MARK: Variant selection

    @Test("a single variant always selects index 0")
    func singleVariant() {
        #expect(PetVariantSelector.variant(count: 1, random: { _ in 0 }) == 0)
        #expect(PetVariantSelector.variant(count: 0, random: { _ in 5 }) == 0)
    }

    @Test("rotation avoids repeating the previous variant")
    func avoidsPreviousVariant() {
        // The generator insists on 2; with previous == 2 the result must move on.
        #expect(PetVariantSelector.variant(count: 4, previous: 2, random: { _ in 2 }) == 3)
        // Wraps around at the end of the range.
        #expect(PetVariantSelector.variant(count: 3, previous: 2, random: { _ in 2 }) == 0)
    }

    @Test("a differing draw is used unchanged")
    func usesDrawWhenDifferent() {
        #expect(PetVariantSelector.variant(count: 4, previous: 0, random: { _ in 3 }) == 3)
    }

    @Test("selection always lands in range", arguments: 1...6)
    func selectionInRange(count: Int) {
        for _ in 0..<200 {
            let value = PetVariantSelector.variant(count: count)
            #expect(value >= 0 && value < count)
        }
    }

    @Test("only idle and focusGuard rotate variants")
    func rotatingStates() {
        #expect(PetVariantSelector.rotates(.idle, variantCount: 4))
        #expect(PetVariantSelector.rotates(.focusGuard, variantCount: 3))
        #expect(!PetVariantSelector.rotates(.happy, variantCount: 3))
        #expect(!PetVariantSelector.rotates(.breakRunning, variantCount: 2))
        // A single-variant state has nothing to rotate to.
        #expect(!PetVariantSelector.rotates(.idle, variantCount: 1))
    }

    // MARK: Replay interval

    @Test("only Golden Puppy's breakRunning schedules a replay")
    func replayIntervalStates() {
        for appearance in BuiltInPetAppearanceID.allCases {
            let id = PetAppearanceID(rawValue: appearance.rawValue)!
            for state in PetState.allCases {
                let definition = PetAppearances.assetDefinition(appearance: id, state: state)
                let expected = (appearance == .lovartPuppy && state == .breakRunning) ? 4500 : nil
                #expect(
                    definition.replayIntervalMs == expected,
                    "\(appearance.rawValue)/\(state.rawValue)"
                )
            }
        }
    }
}

@Suite("Pet window", .serialized)
@MainActor
struct PetWindowTests {

    @Test("the window is transparent, borderless, floating and on all Spaces")
    func windowConfiguration() {
        let window = PetWindow(contentRect: CGRect(x: 0, y: 0, width: 220, height: 340))

        #expect(window.styleMask.contains(.borderless))
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
        #expect(!window.hasShadow)
        #expect(window.level == .floating)
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        // The pet must never steal keyboard focus.
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
        // Click-through starts enabled; Task 6 toggles it per cursor position.
        #expect(window.ignoresMouseEvents)
    }

    @Test("performClose hides a borderless pet window so Quit can finish")
    func performCloseHidesWindow() {
        let window = PetWindow(contentRect: CGRect(x: 0, y: 0, width: 220, height: 340))
        window.orderFrontRegardless()
        #expect(window.isVisible)
        window.performClose(nil)
        #expect(!window.isVisible)
    }

    @Test("the window opens at the pet size")
    func windowSize() {
        let controller = PetWindowController()
        #expect(controller.window.frame.width == Constants.petWindowSize.width)
        #expect(controller.window.frame.height == Constants.petWindowSize.height)
    }

    @Test("the window opens inside the primary work area")
    func windowStartsOnScreen() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        let controller = PetWindowController()
        let bounds = controller.globalBounds
        let clamped = DisplayGeometry.visibleBounds(
            displays: ScreenBridge.displays,
            primaryDisplay: ScreenBridge.primaryDisplay,
            bounds: bounds
        )
        #expect(clamped == bounds)
    }

    @Test("global bounds round-trip through the window frame")
    func boundsRoundTrip() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        let controller = PetWindowController()
        let target = GlobalRect(x: 120, y: 240, width: 220, height: 340)
        controller.setGlobalBounds(target)
        #expect(controller.globalBounds == target)
    }

    @Test("facing left mirrors the pet layer")
    func facingTransform() {
        let controller = PetWindowController()

        #expect(controller.facing == .right)
        #expect(CATransform3DIsIdentity(controller.contentView.petLayer.transform))

        controller.facing = .left
        #expect(controller.contentView.petLayer.transform.m11 == -1)

        controller.facing = .right
        #expect(CATransform3DIsIdentity(controller.contentView.petLayer.transform))
    }

    @Test("showing the pet loads a real animation into the layer")
    func rendersAnimation() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        let controller = PetWindowController()
        controller.setState(.idle)

        // `contents` is set synchronously from the decoded first frame.
        #expect(controller.contentView.petLayer.contents != nil)
        let size = try #require(controller.contentView.animator.currentPixelSize)
        #expect(size.width > 0 && size.height > 0)
    }

    @Test("every state renders for every built-in appearance")
    func rendersEveryState() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        let controller = PetWindowController()
        for appearance in BuiltInPetAppearanceID.allCases {
            controller.appearance = PetAppearanceID(rawValue: appearance.rawValue)!
            for state in PetState.allCases {
                controller.setState(state)
                #expect(
                    controller.contentView.petLayer.contents != nil,
                    "no frame rendered for \(appearance.rawValue)/\(state.rawValue)"
                )
            }
        }
    }
}
