import Foundation

/// Active-tab title and URL from AppleScript-capable browsers.
///
/// Chromium window titles often omit the page name; Brave/Chrome expose the
/// selected tab via their scripting dictionary. Only the front window's active
/// tab is queried — background tabs are never scanned.
public enum BrowserTabReader {

    public struct ActiveTab: Equatable, Sendable {
        public let title: String
        public let url: String

        public init(title: String, url: String) {
            self.title = title
            self.url = url
        }

        /// Combined text for keyword matching in `DistractionClassifier`.
        public var keywordContext: String {
            let parts = [title.trimmingCharacters(in: .whitespacesAndNewlines),
                         url.trimmingCharacters(in: .whitespacesAndNewlines)]
                .filter { !$0.isEmpty }
            return parts.joined(separator: " ")
        }
    }

    /// Maps bundle IDs to the name used in `tell application "…"`.
    public static let supportedBundleIDs: [String: String] = [
        "com.brave.Browser": "Brave Browser",
        "com.google.Chrome": "Google Chrome",
        "com.apple.Safari": "Safari"
    ]

    /// AppleScript source for the active tab only, or nil when unsupported.
    public static func script(forBundleID bundleID: String?) -> String? {
        guard let bundleID,
              let appName = supportedBundleIDs[bundleID]
        else { return nil }

        if bundleID == "com.apple.Safari" {
            return """
            tell application "Safari"
                set t to current tab of front window
                return (name of t) & linefeed & (URL of t)
            end tell
            """
        }

        return """
        tell application "\(appName)"
            set t to active tab of front window
            return (title of t) & linefeed & (URL of t)
        end tell
        """
    }

    /// Parses the two-line `title` + newline + `url` script result.
    public static func parseScriptResult(_ raw: String) -> ActiveTab? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lines = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let title = String(lines.first ?? "")
        let url = lines.count > 1 ? String(lines[1]) : ""
        guard !title.isEmpty || !url.isEmpty else { return nil }
        return ActiveTab(title: title, url: url)
    }

    /// Runs AppleScript for the bundle ID. Failures return nil (caller keeps AX title).
    public static func readActiveTab(bundleID: String?) -> ActiveTab? {
        readActiveTab(bundleID: bundleID, runner: NSAppleScriptRunner())
    }

    public static func readActiveTab(
        bundleID: String?,
        runner: AppleScriptRunning
    ) -> ActiveTab? {
        guard let source = script(forBundleID: bundleID) else { return nil }
        guard let raw = runner.run(source: source) else { return nil }
        return parseScriptResult(raw)
    }
}

/// Injectable AppleScript execution for tests.
public protocol AppleScriptRunning: Sendable {
    func run(source: String) -> String?
}

/// Production runner using in-process `NSAppleScript` (no `osascript` subprocess).
public struct NSAppleScriptRunner: AppleScriptRunning {
    public init() {}

    public func run(source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743 = user declined / Automation not granted for this binary.
            let number = error[NSAppleScript.errorNumber] as Any? ?? "?"
            let message = error[NSAppleScript.errorMessage] as Any? ?? error
            NSLog(
                "DeskPet: AppleScript failed (err=\(number) msg=\(message)). "
                    + "Allow DeskPet under System Settings › Privacy & Security › Automation."
            )
            return nil
        }
        return result.stringValue
    }
}
