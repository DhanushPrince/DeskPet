import AppKit

/// The menu bar presence. Replaces Electron's `Tray`.
///
/// `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: the menu's labels change
/// with pet visibility and focus state, and it must be rebuilt on demand, which
/// `MenuBarExtra` does not express cleanly.
public final class StatusBarController {
    private let statusItem: NSStatusItem
    private let target: MenuActionTarget
    /// Supplies the current labels each time a menu is built.
    private let stateProvider: () -> MenuState

    public init(
        stateProvider: @escaping () -> MenuState,
        onAction: @escaping (MenuAction) -> Void
    ) {
        self.stateProvider = stateProvider
        self.target = MenuActionTarget(handler: onAction)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        statusItem.button?.image = TrayIcon.make()
        statusItem.button?.toolTip = Constants.appName
        refresh()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// Rebuilds the tray and application menus from the current state.
    public func refresh() {
        let state = stateProvider()
        statusItem.menu = MenuBuilder.makeMenu(
            from: MenuBuilder.trayMenu(state),
            target: target
        )
        NSApp.mainMenu = MenuBuilder.makeMenu(
            from: MenuBuilder.applicationMenu(state),
            target: target
        )
    }

    /// Shows the pet's context menu at the event location.
    public func showPetContextMenu(for event: NSEvent, in view: NSView) {
        let menu = MenuBuilder.makeMenu(
            from: MenuBuilder.petContextMenu(stateProvider()),
            target: target
        )
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// Exposed for tests: the live tray menu.
    public var currentMenu: NSMenu? { statusItem.menu }
    public var hasIcon: Bool { statusItem.button?.image != nil }
}
