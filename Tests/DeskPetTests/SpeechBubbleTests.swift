import AppKit
import Foundation
import Testing
@testable import DeskPetKit

@Suite("Speech bubble layout")
@MainActor
struct SpeechBubbleLayoutTests {

    private func action(_ label: String, _ kind: BubbleActionKind = .secondary) -> BubbleAction {
        BubbleAction(id: "test:\(label)", label: label, kind: kind)
    }

    @Test("a message-only bubble is as tall as its text plus padding")
    func messageOnlyHeight() {
        let bubble = SpeechBubble(id: "b", message: "Short")
        let height = SpeechBubbleView.height(for: bubble)
        // 12pt padding top and bottom around a single 13pt line.
        #expect(height > BubbleStyle.padding * 2)
        #expect(height < 60)
    }

    @Test("a longer message wraps to a taller bubble")
    func longMessageIsTaller() {
        let short = SpeechBubble(id: "b", message: "Hi")
        let long = SpeechBubble(
            id: "b",
            message: "You've been sitting too long, walk for a minute! "
                + "Seriously, get up and stretch those legs right now please."
        )
        #expect(SpeechBubbleView.height(for: long) > SpeechBubbleView.height(for: short))
    }

    @Test("actions add a row plus the top margin")
    func actionsAddHeight() {
        let plain = SpeechBubble(id: "b", message: "Message")
        let withAction = SpeechBubble(id: "b", message: "Message", actions: [action("OK")])

        let delta = SpeechBubbleView.height(for: withAction) - SpeechBubbleView.height(for: plain)
        #expect(delta == BubbleStyle.actionsTopMargin + BubbleStyle.buttonHeight)
    }

    @Test("narrow actions share one row")
    func narrowActionsShareRow() {
        let rows = SpeechBubbleView.buttonRows(for: [action("A"), action("B")])
        #expect(rows.count == 1)
        #expect(rows[0].count == 2)
    }

    @Test("the three break actions wrap onto multiple rows")
    func breakActionsWrap() {
        // "I stood up", "Remind in 10 min", "Leave me today" do not fit on one
        // 186pt content row, matching the renderer's flex-wrap behaviour.
        let rows = SpeechBubbleView.buttonRows(for: [
            action(Strings.Actions.breakDone, .primary),
            action(Strings.Actions.breakSnooze),
            action(Strings.Actions.breakMute, .danger)
        ])
        #expect(rows.count > 1, "expected wrapping, got one row")
        #expect(rows.flatMap { $0 }.count == 3, "no action may be dropped")
    }

    @Test("every row fits inside the bubble's content width")
    func rowsFitContentWidth() {
        let actions = [
            action(Strings.Actions.breakDone, .primary),
            action(Strings.Actions.breakSnooze),
            action(Strings.Actions.breakMute, .danger)
        ]
        let available = BubbleStyle.width - BubbleStyle.padding * 2

        for row in SpeechBubbleView.buttonRows(for: actions) {
            let width = row.reduce(CGFloat(0)) { $0 + SpeechBubbleView.buttonWidth(for: $1) }
                + CGFloat(max(0, row.count - 1)) * BubbleStyle.actionSpacing
            // A single button wider than the row is allowed to overflow; two or
            // more must fit.
            if row.count > 1 {
                #expect(width <= available, "row overflows: \(width) > \(available)")
            }
        }
    }

    @Test("a button is at least as wide as its label plus padding")
    func buttonWidthIncludesPadding() {
        let width = SpeechBubbleView.buttonWidth(for: action("OK"))
        #expect(width > BubbleStyle.buttonHorizontalPadding * 2)
    }

    @Test("the style constants match the ported CSS")
    func styleMatchesSource() {
        #expect(BubbleStyle.width == 210)          // min-width: 210px
        #expect(BubbleStyle.cornerRadius == 16)    // border-radius: 16px
        #expect(BubbleStyle.padding == 12)         // padding: 12px
        #expect(BubbleStyle.bottomInset == 154)    // bottom: 154px
        #expect(BubbleStyle.tailHalfWidth == 9)    // border-left/right: 9px
        #expect(BubbleStyle.tailHeight == 10)      // border-top: 10px
        #expect(BubbleStyle.buttonHeight == 28)    // min-height: 28px
        #expect(BubbleStyle.actionSpacing == 6)    // gap: 6px
        #expect(BubbleStyle.actionsTopMargin == 10)
    }

    @Test("only the primary button inverts its text colour")
    func primaryTextInverts() {
        #expect(BubbleStyle.textColour(for: .primary) == BubbleStyle.primaryText)
        #expect(BubbleStyle.textColour(for: .secondary) == BubbleStyle.messageColour)
        #expect(BubbleStyle.textColour(for: .danger) == BubbleStyle.messageColour)
    }
}

@Suite("Speech bubble presentation", .serialized)
@MainActor
struct SpeechBubblePresentationTests {

    private func makeView() -> PetContentView {
        PetContentView(frame: CGRect(origin: .zero, size: Constants.petWindowSize))
    }

    @Test("a bubble starts hidden")
    func startsHidden() {
        let view = makeView()
        #expect(!view.isBubbleVisible)
        #expect(view.additionalInteractiveRects.isEmpty)
    }

    @Test("a tall break bubble stays above the pet sprite")
    func tallBubbleClearsPetSprite() {
        let view = makeView()
        view.presentBubble(SpeechBubble(
            id: "b",
            message: "I wanna play! Walk for a minute~",
            actions: [
                BubbleAction(id: "1", label: Strings.Actions.breakDone, kind: .primary),
                BubbleAction(id: "2", label: Strings.Actions.breakSnooze),
                BubbleAction(id: "3", label: Strings.Actions.breakMute, kind: .danger)
            ]
        ))
        view.layoutSubtreeIfNeeded()

        let panelBottom = view.bubbleView.frame.minY + BubbleStyle.tailHeight
        // Tail may kiss the head; the panel itself must sit at/above bottomInset
        // and leave the lower sprite band mostly free.
        #expect(panelBottom >= BubbleStyle.bottomInset - 0.5)
        #expect(view.bubbleView.frame.maxY <= view.bounds.height + 0.5)
        #expect(view.petSpriteFrame.maxY <= Constants.petSpriteSize.height + 0.5)
    }

    @Test("presenting shows the bubble at the ported offset")
    func presentPositionsBubble() {
        let view = makeView()
        let bubble = SpeechBubble(id: "b", message: "Hello")
        view.presentBubble(bubble)

        #expect(view.isBubbleVisible)
        let frame = view.bubbleView.frame
        #expect(frame.width == BubbleStyle.width)
        // The panel's bottom edge sits 154pt above the window bottom; the view
        // extends a further 10pt down for the tail.
        #expect(frame.minY == BubbleStyle.bottomInset - BubbleStyle.tailHeight)
        // Horizontally centred in the 220pt window.
        #expect(frame.midX == view.bounds.midX)
    }

    @Test("bubble buttons accept a click while the pet window is not key")
    func bubbleButtonsAcceptFirstMouse() {
        let view = makeView()
        view.presentBubble(SpeechBubble(
            id: "b",
            message: "Drink water",
            actions: [BubbleAction(id: BubbleActionID.hydrationDone, label: "OK")]
        ))
        view.layoutSubtreeIfNeeded()

        #expect(view.bubbleView.acceptsFirstMouse(for: nil))
        let button = view.bubbleView.subviews.compactMap { $0 as? NSButton }.first
        #expect(button != nil)
        #expect(button?.acceptsFirstMouse(for: nil) == true)
    }

    @Test("dismissing hides the bubble and clears its hit area")
    func dismissHidesBubble() {
        let view = makeView()
        view.presentBubble(SpeechBubble(id: "b", message: "Hello"))
        #expect(!view.additionalInteractiveRects.isEmpty)

        view.dismissBubble()
        #expect(!view.isBubbleVisible)
        #expect(view.additionalInteractiveRects.isEmpty)
    }

    @Test("the bubble's hit area is reported in top-left coordinates")
    func hitAreaIsTopLeft() throws {
        let view = makeView()
        view.presentBubble(SpeechBubble(id: "b", message: "Hello"))

        let rect = try #require(view.additionalInteractiveRects.first)
        let cocoaFrame = view.bubbleView.frame
        // Converting back should recover the Cocoa frame.
        #expect(rect.minX == cocoaFrame.minX)
        #expect(view.bounds.height - rect.maxY == cocoaFrame.minY)
        #expect(rect.size == cocoaFrame.size)
    }

    @Test("hit testing accepts the bubble even outside the pet's hitbox")
    func hitTestAcceptsBubble() {
        let view = makeView()
        // A point in the left margin, outside the 80% pet hitbox.
        let marginPoint = CGPoint(x: 8, y: 200)
        #expect(view.hitTest(marginPoint) == nil, "margin is click-through without a bubble")

        view.presentBubble(SpeechBubble(id: "b", message: "A longer message that wraps nicely"))
        let bubbleFrame = view.bubbleView.frame
        let insideBubble = CGPoint(x: bubbleFrame.minX + 3, y: bubbleFrame.midY)
        #expect(view.hitTest(insideBubble) != nil, "the bubble must be clickable")
    }

    @Test("tapping a button reports its action id")
    func buttonReportsAction() {
        let view = makeView()
        var received: [String] = []
        view.bubbleView.onAction = { received.append($0) }

        view.presentBubble(SpeechBubble(
            id: BubbleID.breakPrompt,
            message: "Take a break",
            actions: [
                BubbleAction(id: BubbleActionID.breakDone, label: "I stood up", kind: .primary),
                BubbleAction(id: BubbleActionID.breakSnooze, label: "Later")
            ]
        ))
        view.layoutSubtreeIfNeeded()

        let buttons = view.bubbleView.subviews.compactMap { $0 as? NSButton }
        #expect(buttons.count == 2)
        buttons.first?.performClick(nil)
        #expect(received == [BubbleActionID.breakDone])

        buttons.last?.performClick(nil)
        #expect(received == [BubbleActionID.breakDone, BubbleActionID.breakSnooze])
    }

    @Test("presenting a new bubble replaces the previous one's buttons")
    func replacingBubbleRebuildsButtons() {
        let view = makeView()
        view.presentBubble(SpeechBubble(
            id: "a", message: "One",
            actions: [BubbleAction(id: "a:1", label: "A"), BubbleAction(id: "a:2", label: "B")]
        ))
        #expect(view.bubbleView.subviews.compactMap { $0 as? NSButton }.count == 2)

        view.presentBubble(SpeechBubble(
            id: "b", message: "Two", actions: [BubbleAction(id: "b:1", label: "C")]
        ))
        #expect(view.bubbleView.subviews.compactMap { $0 as? NSButton }.count == 1)
        #expect(view.bubbleView.bubble?.id == "b")
    }

    @Test("buttons stay inside the bubble's bounds")
    func buttonsFitInsideBubble() {
        let view = makeView()
        view.presentBubble(SpeechBubble(
            id: BubbleID.breakPrompt,
            message: Strings.pick(Strings.Bubble.breakReminder),
            actions: [
                BubbleAction(id: "1", label: Strings.Actions.breakDone, kind: .primary),
                BubbleAction(id: "2", label: Strings.Actions.breakSnooze),
                BubbleAction(id: "3", label: Strings.Actions.breakMute, kind: .danger)
            ]
        ))
        view.layoutSubtreeIfNeeded()

        let bounds = view.bubbleView.bounds
        for button in view.bubbleView.subviews.compactMap({ $0 as? NSButton }) {
            #expect(bounds.contains(button.frame), "button escapes the bubble: \(button.frame)")
        }
    }

    @Test("buttons appear in action order, top to bottom")
    func buttonOrderMatchesActions() {
        // Regression: frames were assigned while iterating rows bottom-up while
        // buttons were consumed top-down, which inverted the visible order and
        // gave each button the wrong width.
        let view = makeView()
        view.presentBubble(SpeechBubble(
            id: BubbleID.breakPrompt,
            message: "Take a break",
            actions: [
                BubbleAction(id: "1", label: Strings.Actions.breakDone, kind: .primary),
                BubbleAction(id: "2", label: Strings.Actions.breakSnooze),
                BubbleAction(id: "3", label: Strings.Actions.breakMute, kind: .danger)
            ]
        ))
        view.layoutSubtreeIfNeeded()

        let buttons = view.bubbleView.subviews.compactMap { $0 as? NSButton }
        #expect(buttons.count == 3)
        // Cocoa y grows upward, so the first action must have the highest origin.
        #expect(buttons[0].frame.minY > buttons[1].frame.minY)
        #expect(buttons[1].frame.minY > buttons[2].frame.minY)
    }

    @Test("each button is wide enough for its own label")
    func buttonWidthsMatchLabels() {
        let actions = [
            BubbleAction(id: "1", label: Strings.Actions.breakDone, kind: .primary),
            BubbleAction(id: "2", label: Strings.Actions.breakSnooze),
            BubbleAction(id: "3", label: Strings.Actions.breakMute, kind: .danger)
        ]
        let view = makeView()
        view.presentBubble(SpeechBubble(
            id: BubbleID.breakPrompt, message: "Take a break", actions: actions
        ))
        view.layoutSubtreeIfNeeded()

        let buttons = view.bubbleView.subviews.compactMap { $0 as? NSButton }
        for (index, action) in actions.enumerated() where index < buttons.count {
            let required = SpeechBubbleView.buttonWidth(for: action)
            #expect(
                buttons[index].frame.width >= required,
                "\(action.label) is truncated: \(buttons[index].frame.width) < \(required)"
            )
        }
    }

    @Test("the message sits above the action block")
    func messageAboveActions() {
        let view = makeView()
        view.presentBubble(SpeechBubble(
            id: "b", message: "Take a break",
            actions: [BubbleAction(id: "1", label: "OK", kind: .primary)]
        ))
        view.layoutSubtreeIfNeeded()

        let buttons = view.bubbleView.subviews.compactMap { $0 as? NSButton }
        let label = view.bubbleView.subviews.compactMap { $0 as? NSTextField }.first
        #expect(label != nil)
        if let label, let button = buttons.first {
            #expect(label.frame.minY >= button.frame.maxY, "message must clear the buttons")
        }
    }

    @Test("content clears the tail at the bottom of the view")
    func contentClearsTail() {
        let view = makeView()
        view.presentBubble(SpeechBubble(
            id: "b", message: "Hi", actions: [BubbleAction(id: "1", label: "OK")]
        ))
        view.layoutSubtreeIfNeeded()

        for button in view.bubbleView.subviews.compactMap({ $0 as? NSButton }) {
            #expect(
                button.frame.minY >= BubbleStyle.tailHeight,
                "content must not overlap the tail"
            )
        }
    }
}

@Suite("Bubble lifecycle", .serialized)
@MainActor
struct BubbleLifecycleTests {

    @Test("a bubble with no auto-dismiss stays visible")
    func staysWithoutAutoDismiss() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.showBubble(SpeechBubble(id: "b", message: "Stays"))
        try await Task.sleep(for: .milliseconds(120))
        #expect(controller.isBubbleVisible)
    }

    @Test("a bubble with auto-dismiss disappears on schedule")
    func autoDismisses() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.showBubble(SpeechBubble(
            id: "b", message: "Goes", autoDismissAfter: 0.08
        ))
        #expect(controller.isBubbleVisible)

        try await Task.sleep(for: .milliseconds(250))
        #expect(!controller.isBubbleVisible)
    }

    @Test("a replacement bubble restarts the auto-dismiss timer")
    func replacementRestartsTimer() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.showBubble(SpeechBubble(id: "a", message: "First", autoDismissAfter: 0.1))
        try await Task.sleep(for: .milliseconds(60))
        // Replacing before the first expires must not inherit its deadline.
        controller.showBubble(SpeechBubble(id: "b", message: "Second", autoDismissAfter: 0.4))

        try await Task.sleep(for: .milliseconds(120))
        #expect(controller.isBubbleVisible, "the new bubble's timer should still be running")
        #expect(controller.currentBubble?.id == "b")
    }

    @Test("hiding the pet dismisses its bubble")
    func hidingPetDismissesBubble() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        controller.showBubble(SpeechBubble(id: "b", message: "Bye"))
        #expect(controller.isBubbleVisible)

        controller.hide()
        #expect(!controller.isBubbleVisible)
    }

    @Test("showing a bubble makes its area interactive")
    func bubbleAreaBecomesInteractive() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let controller = PetWindowController()
        controller.show()
        defer { controller.hide() }

        controller.showBubble(SpeechBubble(
            id: "b", message: "Click me", actions: [BubbleAction(id: "x", label: "OK")]
        ))

        // A point in the bubble but outside the pet's hitbox.
        let bounds = controller.globalBounds
        let bubbleFrame = controller.contentView.additionalInteractiveRects[0]
        let cursor = CGPoint(
            x: bounds.x + bubbleFrame.minX + 3,
            y: bounds.y + bubbleFrame.midY
        )
        #expect(controller.mouseTracker.shouldBeInteractive(cursor: cursor))
    }
}

@Suite("Happy feedback", .serialized)
@MainActor
struct HappyFeedbackTests {

    private func makeState() -> (AppState, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let state = AppState(persistence: persistence, clock: TestClock())

        return (state, {
            state.cancelPendingSequences()
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("a message shows a bubble and enters the happy state")
    func happyWithMessage() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.happyFeedback(message: "woof!")
        #expect(state.petState == .happy)
        #expect(state.petWindow.isBubbleVisible)
        #expect(state.petWindow.currentBubble?.message == "woof!")
    }

    @Test("no message means no bubble, but still a happy reaction")
    func happyWithoutMessage() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.happyFeedback(message: nil)
        #expect(state.petState == .happy)
        #expect(!state.petWindow.isBubbleVisible)
    }

    @Test("happy feedback is refused while a prompt is showing")
    func happyRefusedWhileBlocked() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.stateMachine.triggerBreakReminder()
        #expect(state.petState == .breakPrompt)

        state.happyFeedback(message: "woof!")
        #expect(state.petState == .breakPrompt, "a prompt must not be interrupted")
    }

    @Test("demo happy clears a blocking prompt then reacts")
    func demoHappyClearsPrompt() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        #expect(state.petState == .breakPrompt)

        state.handle(.demoHappy)
        #expect(state.petState == .happy)
        #expect(state.blockingMode == nil)
        #expect(state.petWindow.currentBubble?.id == BubbleID.happy)
    }

    @Test("debug cycle advances pet states on the main run loop")
    func debugCycleStatesAdvances() async throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let (state, cleanup) = makeState()
        defer { cleanup() }
        state.start()

        state.handle(.demoBreak)
        state.handle(.debugCycleStates)

        // First state is applied synchronously via timer.fire() on the next turn.
        try await Task.sleep(for: .milliseconds(50))
        #expect(state.petState == PetState.allCases[0])
        #expect(state.blockingMode == nil, "cycle clears the open prompt")
        #expect(!state.petWindow.isBubbleVisible)

        try await Task.sleep(for: .milliseconds(900))
        #expect(state.petState == PetState.allCases[1])
    }
}
