import AppKit

/// Every command a menu can issue.
public enum MenuAction: String, CaseIterable, Sendable {
    case togglePet
    case hidePet
    case startFocus
    /// The menu bar's stop counts the session as completed…
    case stopFocusCompleted
    /// …while the pet's context menu counts it as cancelled. The Electron build
    /// wired `stopFocusFromMenu`/`stopFocusFromContext` to `stopFocusMode(true)`
    /// and `stopFocusMode(false)` respectively.
    case stopFocusCancelled
    case openSettings
    case quit

    case demoBreak
    case demoHydration
    case demoFocusWarning
    case demoHappy
    case debugCycleStates
}

/// A menu row, independent of AppKit so menu structure can be asserted in tests.
public enum MenuItemDescriptor: Equatable, Sendable {
    case command(MenuAction, title: String)
    case disabledLabel(String)
    case separator
    case submenu(title: String, items: [MenuItemDescriptor])
}

/// Inputs that change menu labels.
public struct MenuState: Equatable, Sendable {
    public var appName: String
    public var petVisible: Bool
    public var focusActive: Bool
    /// Demo triggers were dev-only in the Electron build (gated on
    /// `!app.isPackaged`); here they appear only in debug builds.
    public var includeDeveloperItems: Bool

    public init(
        appName: String = Constants.appName,
        petVisible: Bool,
        focusActive: Bool,
        includeDeveloperItems: Bool = MenuState.developerItemsDefault
    ) {
        self.appName = appName
        self.petVisible = petVisible
        self.focusActive = focusActive
        self.includeDeveloperItems = includeDeveloperItems
    }

    public static var developerItemsDefault: Bool {
        #if DEBUG
        true
        #else
        // Local `make run` / ad-hoc builds keep demos; installed copies do not.
        !Bundle.main.bundlePath.hasPrefix("/Applications/")
        #endif
    }
}

/// Ported from `src/main/menus.ts`.
public enum MenuBuilder {

    static func developerItems() -> [MenuItemDescriptor] {
        [
            .separator,
            .command(.demoBreak, title: Strings.Menu.demoBreakReminder),
            .command(.demoHydration, title: Strings.Menu.demoHydrationReminder),
            .command(.demoFocusWarning, title: Strings.Menu.demoFocusWarning),
            .command(.demoHappy, title: Strings.Menu.demoHappyReaction),
            .command(.debugCycleStates, title: Strings.Menu.debugCycleStates)
        ]
    }

    /// The shared block: show/hide, focus toggle, developer items, settings.
    static func actionItems(_ state: MenuState) -> [MenuItemDescriptor] {
        var items: [MenuItemDescriptor] = [
            .command(
                .togglePet,
                title: state.petVisible ? Strings.Menu.hidePet : Strings.Menu.showPet
            ),
            .command(
                state.focusActive ? .stopFocusCompleted : .startFocus,
                title: state.focusActive ? Strings.Menu.stopFocusMode : Strings.Menu.startFocusMode
            )
        ]
        if state.includeDeveloperItems {
            items += developerItems()
        }
        items += [
            .separator,
            .command(.openSettings, title: Strings.Menu.settings)
        ]
        return items
    }

    public static func trayMenu(_ state: MenuState) -> [MenuItemDescriptor] {
        [.disabledLabel(state.appName), .separator]
            + actionItems(state)
            + [.separator, .command(.quit, title: Strings.Menu.quit)]
    }

    public static func applicationMenu(_ state: MenuState) -> [MenuItemDescriptor] {
        [
            .submenu(
                title: state.appName,
                items: actionItems(state)
                    + [.separator, .command(.quit, title: Strings.Menu.quit)]
            )
        ]
    }

    public static func petContextMenu(_ state: MenuState) -> [MenuItemDescriptor] {
        var items: [MenuItemDescriptor] = [
            .command(.openSettings, title: Strings.Menu.settings),
            .command(
                state.focusActive ? .stopFocusCancelled : .startFocus,
                title: state.focusActive ? Strings.Menu.stopFocusMode : Strings.Menu.startFocusMode
            )
        ]
        if state.includeDeveloperItems {
            items += developerItems()
        }
        items += [
            .separator,
            .command(.hidePet, title: Strings.Menu.hidePet)
        ]
        return items
    }
}

// MARK: - AppKit construction

/// Target for menu items; retained by the menu's owner.
final class MenuActionTarget: NSObject {
    private let handler: (MenuAction) -> Void

    init(handler: @escaping (MenuAction) -> Void) {
        self.handler = handler
    }

    /// Named distinctly from NSObject's `perform(_:with:)` family so the menu
    /// action selector cannot collide at runtime.
    @objc func handleMenuItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = MenuAction(rawValue: raw) else {
            NSLog("DeskPet: menu item missing action (\(sender.title))")
            return
        }
        NSLog("DeskPet: menu action \(action.rawValue)")
        handler(action)
    }
}

extension MenuBuilder {
    /// Turns descriptors into a live `NSMenu`.
    static func makeMenu(
        from descriptors: [MenuItemDescriptor],
        target: MenuActionTarget
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for descriptor in descriptors {
            menu.addItem(makeItem(descriptor, target: target))
        }
        return menu
    }

    private static func makeItem(
        _ descriptor: MenuItemDescriptor,
        target: MenuActionTarget
    ) -> NSMenuItem {
        switch descriptor {
        case .separator:
            return .separator()

        case .disabledLabel(let title):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item

        case .command(let action, let title):
            let item = NSMenuItem(
                title: title,
                action: #selector(MenuActionTarget.handleMenuItem(_:)),
                keyEquivalent: action == .quit ? "q" : ""
            )
            item.target = target
            item.representedObject = action.rawValue
            item.isEnabled = true
            return item

        case .submenu(let title, let items):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = makeMenu(from: items, target: target)
            return item
        }
    }
}
