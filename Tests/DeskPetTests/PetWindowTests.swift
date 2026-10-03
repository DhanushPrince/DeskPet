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

    @Test("pause drops the looping animation and resume restores it")
    func pauseAndResume() throws {
        let layer = CALayer()
        let animator = PetAnimator(layer: layer)
        let definition = PetAppearances.assetDefinition(appearance: .lineDog, state: .idle)
        #expect(animator.play(definition: definition))
        #expect(animator.isAnimating)
        animator.pause()
        #expect(!animator.isAnimating)
        #expect(layer.contents != nil)
        animator.resume()
        #expect(animator.isAnimating)
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

    @Test("only Snowy's breakRunning schedules a replay")
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

    @Test("notch mode raises the window above the menu bar; disabling it restores floating")
    func notchModeWindowLevel() {
        let window = PetWindow(contentRect: CGRect(x: 0, y: 0, width: 220, height: 340))
        #expect(window.level == .floating)

        window.setNotchModeActive(true)
        #expect(window.level == .statusBar)

        window.setNotchModeActive(false)
        #expect(window.level == .floating)
    }

    @Test("the controller's notchModeEnabled flag drives the window level")
    func controllerNotchModeTogglesLevel() {
        let controller = PetWindowController()
        #expect(controller.window.level == .floating)

        controller.notchModeEnabled = true
        #expect(controller.window.level == .statusBar)

        controller.notchModeEnabled = false
        #expect(controller.window.level == .floating)
    }

    @Test("notch mode without a physical notch leaves free-roaming positioning untouched")
    func notchModeWithoutNotchIsANoOp() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        // No `#require` for the notch check itself: `#require` fails a test on
        // a false condition, it does not skip it, and whether this machine has
        // a notch is a hardware fact, not an error. The notch-present path is
        // covered by the tests below instead.
        guard ScreenBridge.notchHangRect(size: Constants.petWindowSize) == nil else { return }

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        let before = controller.globalBounds
        controller.notchModeEnabled = true
        // No notch to hang from: enabling the setting must not move the pet
        // or otherwise break free-roaming placement.
        #expect(controller.globalBounds == before)
    }

    @Test("notch mode pins the pet under the notch while idle")
    func notchModePinsPetWhileIdle() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        guard let target = ScreenBridge.notchHangRect(size: Constants.petWindowSize) else {
            return // No notch on this machine; nothing to verify here.
        }

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.notchModeEnabled = true
        drainNotchSlide()
        #expect(controller.globalBounds == ScreenBridge.notchRestRect(size: Constants.petWindowSize))
    }

    @Test("turning notch mode off releases the pet from the notch back to free-roam")
    func notchModeOffReleasesPet() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let restRect = ScreenBridge.notchRestRect(size: Constants.petWindowSize)
        guard ScreenBridge.notchHangRect(size: Constants.petWindowSize) != nil else {
            return // No notch on this machine; nothing to verify here.
        }

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.notchModeEnabled = true
        drainNotchSlide()
        #expect(controller.globalBounds == restRect)

        // Turning the mode off must move the pet out of the notch rest rect,
        // not leave it pinned there. It lands on the visible work area.
        controller.notchModeEnabled = false
        drainNotchSlide()
        #expect(controller.globalBounds != restRect)
        let onArea = DisplayGeometry.visibleBounds(
            displays: ScreenBridge.displays,
            primaryDisplay: ScreenBridge.primaryDisplay,
            bounds: controller.globalBounds
        )
        #expect(controller.globalBounds == onArea)
    }


    func notchModeSlidesDownForReminders() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        guard ScreenBridge.notchHangRect(size: Constants.petWindowSize) != nil else {
            return // No notch on this machine; nothing to verify here.
        }

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }
        controller.notchModeEnabled = true
        drainNotchSlide()

        guard let shown = ScreenBridge.notchHangRect(size: Constants.petWindowSize) else { return }
        controller.setState(.breakPrompt)
        drainNotchSlide()
        #expect(controller.globalBounds == shown)

        // Once the slide finishes, a manual move is left alone until the
        // state changes. The break run still owns its own motion.
        controller.setGlobalBounds(GlobalRect(x: 40, y: 40, width: 220, height: 340))
        #expect(controller.globalBounds == GlobalRect(x: 40, y: 40, width: 220, height: 340))

        controller.setState(.idle)
        drainNotchSlide()
        #expect(controller.globalBounds == ScreenBridge.notchRestRect(size: Constants.petWindowSize))
    }

    @Test("celebration states tuck back into the notch")
    func notchModeHidesCelebrationStates() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        guard ScreenBridge.notchHangRect(size: Constants.petWindowSize) != nil else {
            return
        }

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }
        controller.notchModeEnabled = true
        drainNotchSlide()

        guard let shown = ScreenBridge.notchHangRect(size: Constants.petWindowSize) else { return }
        controller.setState(.hydrationPrompt)
        drainNotchSlide()
        #expect(controller.globalBounds == shown)

        let rest = ScreenBridge.notchRestRect(size: Constants.petWindowSize)
        for state in [PetState.happy, .hydrationDone, .breakDone, .sad] {
            controller.setState(state)
            drainNotchSlide()
            #expect(controller.globalBounds == rest)
        }
    }

    @Test("a tall notch bubble keeps the dog's head inside the window")
    func notchBubbleDoesNotClipHead() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        guard ScreenBridge.notchHangRect(size: Constants.petWindowSize) != nil else {
            return
        }

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }
        controller.notchModeEnabled = true
        controller.setState(.breakPrompt)
        drainNotchSlide()

        let beforeTop = controller.globalBounds.y
            + Double(controller.globalBounds.height - controller.contentView.petSpriteFrame.maxY)

        controller.showBubble(SpeechBubble(
            id: "break",
            message: "Sitting for so long... go walk for a minute!",
            actions: [
                BubbleAction(id: "stood", label: "I stood up", kind: .primary),
                BubbleAction(id: "snooze", label: "Remind in 10 min"),
                BubbleAction(id: "mute", label: "Leave me today", kind: .danger)
            ]
        ))
        drainNotchSlide()
        controller.contentView.layoutSubtreeIfNeeded()

        let sprite = controller.contentView.petSpriteFrame
        let afterTop = controller.globalBounds.y
            + Double(controller.globalBounds.height - sprite.maxY)
        #expect(sprite.maxY <= controller.contentView.bounds.height + 0.5)
        #expect(controller.window.frame.height + 0.5 >= sprite.height + controller.contentView.bubbleDrop)
        #expect(abs(afterTop - beforeTop) < 1)
    }

    @Test("clamping into the visible area re-pins to the notch in notch mode")
    func clampIntoVisibleAreaRepinsToNotch() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        guard let target = ScreenBridge.notchHangRect(size: Constants.petWindowSize) else {
            return // No notch on this machine; nothing to verify here.
        }

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }
        controller.notchModeEnabled = true
        drainNotchSlide()
        #expect(controller.globalBounds == ScreenBridge.notchRestRect(size: Constants.petWindowSize))

        // Simulate a display change knocking the pet elsewhere, then recovering.
        controller.setGlobalBounds(GlobalRect(x: 9000, y: 9000, width: 220, height: 340))
        controller.clampIntoVisibleArea()
        #expect(controller.globalBounds == ScreenBridge.notchRestRect(size: Constants.petWindowSize))
    }

    @Test("stopping a drag in notch mode snaps the pet back under the notch")
    func stopDragSnapsBackToNotchWhileIdle() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        guard let target = ScreenBridge.notchHangRect(size: Constants.petWindowSize) else {
            return // No notch on this machine; nothing to verify here.
        }

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }
        controller.notchModeEnabled = true
        drainNotchSlide()
        #expect(controller.globalBounds == ScreenBridge.notchRestRect(size: Constants.petWindowSize))

        // Dragging moves the window freely mid-drag — simulate that by moving
        // the window directly, the way `moveWithCursor` would, then release.
        controller.startDrag(offset: .zero)
        controller.setGlobalBounds(GlobalRect(x: 50, y: 500, width: 220, height: 340))
        #expect(controller.globalBounds != ScreenBridge.notchRestRect(size: Constants.petWindowSize))

        controller.stopDrag()
        #expect(controller.globalBounds == ScreenBridge.notchRestRect(size: Constants.petWindowSize))
    }

    @Test("stopping a drag outside notch mode persists the free position as before")
    func stopDragOutsideNotchModePersistsFreePosition() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }
        // notchModeEnabled defaults to false: regression guard that Task 6's
        // change is additive, not a behaviour change for free-roaming.

        var saved: SavedWindowPosition?
        controller.onPositionChanged = { saved = $0 }

        controller.startDrag(offset: .zero)
        controller.setGlobalBounds(GlobalRect(x: 50, y: 500, width: 220, height: 340))
        controller.stopDrag()

        #expect(controller.globalBounds == GlobalRect(x: 50, y: 500, width: 220, height: 340))
        #expect(saved != nil)
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

    @Test("hiding the pet stops the GIF so it is not composited off-screen")
    func hideStopsAnimation() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")

        let controller = PetWindowController()
        controller.show()
        #expect(controller.contentView.animator.isAnimating)
        #expect(controller.contentView.petLayer.contents != nil)

        controller.hide()
        #expect(!controller.contentView.animator.isAnimating)

        controller.show()
        #expect(controller.contentView.animator.isAnimating)
    }

    @Test("parking in the notch pauses the GIF; a reminder starts it again")
    func notchRestPausesAnimation() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        guard ScreenBridge.notchHangRect(size: Constants.petWindowSize) != nil else {
            return
        }

        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }
        #expect(controller.contentView.animator.isAnimating)

        controller.notchModeEnabled = true
        drainNotchSlide()
        #expect(!controller.contentView.animator.isAnimating)

        controller.setState(.breakPrompt)
        drainNotchSlide()
        #expect(controller.contentView.animator.isAnimating)
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

private func drainNotchSlide() {
    let deadline = Date().addingTimeInterval(Constants.notchSlideDuration + 0.08)
    while Date() < deadline {
        RunLoop.main.run(
            mode: PetWindowController.notchSlideRunLoopMode,
            before: Date().addingTimeInterval(0.02)
        )
    }
}
