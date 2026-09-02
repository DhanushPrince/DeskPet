import AppKit
import ApplicationServices

public enum ActiveWindowError: Error, Equatable {
    /// Accessibility permission has not been granted.
    case permissionDenied
    /// No frontmost application, which happens briefly during app switches.
    case noFrontmostApplication
    case accessibility(code: Int32)
}

/// The result of one read, distinguishing "no title" from "not allowed to read
/// the title".
public struct ActiveWindowReading: Equatable, Sendable {
    public let info: ActiveWindowInfo
    /// True when the window title was withheld for lack of Accessibility
    /// permission, as opposed to the app simply having no titled window.
    public let titlePermissionDenied: Bool

    public init(info: ActiveWindowInfo, titlePermissionDenied: Bool = false) {
        self.info = info
        self.titlePermissionDenied = titlePermissionDenied
    }
}

/// Reads the frontmost application and its focused window title.
///
/// ADR-3: this replaces the Electron build's `osascript` subprocess, which was
/// spawned every three seconds. `NSWorkspace` supplies the app name with no
/// permission at all, and `AXUIElement` supplies the window title under the same
/// Accessibility permission the AppleScript needed — so the permission model is
/// unchanged while the process spawn disappears.
public enum ActiveWindowReader {

    /// Whether Accessibility access has been granted to this binary.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system to prompt for Accessibility access.
    ///
    /// The prompt appears once per binary; macOS ties the grant to the code
    /// signature, so an unsigned or re-signed build has to be re-approved.
    @discardableResult
    public static func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Name of the frontmost application. Needs no special permission.
    public static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// Reads the frontmost app and, if permitted, its window title.
    ///
    /// A missing Accessibility grant is *not* an error here. The app name comes
    /// from `NSWorkspace` and needs no permission, so blocked-app rules keep
    /// working; only title-based keyword matching is lost. The Electron build
    /// could not degrade this way — its single `osascript` call supplied both
    /// values or neither.
    ///
    /// Known browsers additionally expose the active tab URL via Apple Events;
    /// when present, that string replaces the AX title for keyword matching.
    public static func read() throws -> ActiveWindowReading {
        try read(tabReader: BrowserTabReader.readActiveTab)
    }

    static func read(
        tabReader: (String?) -> BrowserTabReader.ActiveTab?
    ) throws -> ActiveWindowReading {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ActiveWindowError.noFrontmostApplication
        }
        let name = app.localizedName ?? ""
        let bundleID = app.bundleIdentifier

        do {
            let axTitle = try focusedWindowTitle(pid: app.processIdentifier)
            let windowTitle = enrichedWindowTitle(
                axTitle: axTitle,
                bundleID: bundleID,
                tabReader: tabReader
            )
            return ActiveWindowReading(
                info: ActiveWindowInfo(appName: name, windowTitle: windowTitle)
            )
        } catch ActiveWindowError.permissionDenied {
            let windowTitle = enrichedWindowTitle(
                axTitle: nil,
                bundleID: bundleID,
                tabReader: tabReader
            )
            return ActiveWindowReading(
                info: ActiveWindowInfo(appName: name, windowTitle: windowTitle),
                titlePermissionDenied: windowTitle.isEmpty
            )
        }
    }

    /// Prefer active-tab title + URL when the browser script returns a URL.
    static func enrichedWindowTitle(
        axTitle: String?,
        bundleID: String?,
        tabReader: (String?) -> BrowserTabReader.ActiveTab?
    ) -> String {
        if let tab = tabReader(bundleID), !tab.url.isEmpty {
            return tab.keywordContext
        }
        return axTitle ?? ""
    }

    /// Focused window title via the accessibility API, or nil when the app
    /// exposes none.
    static func focusedWindowTitle(pid: pid_t) throws -> String? {
        let element = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            element, kAXFocusedWindowAttribute as CFString, &windowRef
        )
        switch windowResult {
        case .success:
            break
        case .apiDisabled, .notImplemented:
            throw ActiveWindowError.permissionDenied
        case .noValue, .attributeUnsupported, .cannotComplete, .invalidUIElement:
            // Menu-bar-only apps and some windowless processes legitimately have
            // no focused window.
            return nil
        default:
            throw ActiveWindowError.accessibility(code: windowResult.rawValue)
        }

        guard let window = windowRef else { return nil }

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef
        )
        switch titleResult {
        case .success:
            return titleRef as? String
        case .apiDisabled, .notImplemented:
            throw ActiveWindowError.permissionDenied
        case .noValue, .attributeUnsupported, .cannotComplete, .invalidUIElement:
            return nil
        default:
            throw ActiveWindowError.accessibility(code: titleResult.rawValue)
        }
    }
}
