import AppKit
import ApplicationServices

/// Titles of every Microsoft Teams window, or a permission gap.
public struct MeetingWindowReading: Equatable, Sendable {
    public let titles: [String]
    /// True when Accessibility is missing, so titles cannot be classified.
    public let permissionDenied: Bool

    public init(titles: [String] = [], permissionDenied: Bool = false) {
        self.titles = titles
        self.permissionDenied = permissionDenied
    }
}

/// Enumerates Teams windows via Accessibility. Frontmost-only is not enough:
/// a call stays up while the user is in another app.
public enum MeetingWindowReader {
    public static func read() throws -> MeetingWindowReading {
        let teams = NSWorkspace.shared.runningApplications.filter {
            MeetingClassifier.isTeamsBundleID($0.bundleIdentifier)
        }
        guard !teams.isEmpty else {
            return MeetingWindowReading()
        }

        var titles: [String] = []
        do {
            for app in teams {
                titles.append(contentsOf: try windowTitles(pid: app.processIdentifier))
            }
            return MeetingWindowReading(titles: titles)
        } catch ActiveWindowError.permissionDenied {
            return MeetingWindowReading(permissionDenied: true)
        }
    }

    static func windowTitles(pid: pid_t) throws -> [String] {
        let element = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element, kAXWindowsAttribute as CFString, &windowsRef
        )
        switch result {
        case .success:
            break
        case .apiDisabled, .notImplemented:
            throw ActiveWindowError.permissionDenied
        case .noValue, .attributeUnsupported, .cannotComplete, .invalidUIElement:
            return []
        default:
            throw ActiveWindowError.accessibility(code: result.rawValue)
        }

        guard let items = windowsRef as? [AnyObject] else { return [] }

        var titles: [String] = []
        for item in items {
            let window = item as! AXUIElement
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(
                window, kAXTitleAttribute as CFString, &titleRef
            )
            switch titleResult {
            case .success:
                if let title = titleRef as? String, !title.isEmpty {
                    titles.append(title)
                }
            case .apiDisabled, .notImplemented:
                throw ActiveWindowError.permissionDenied
            default:
                continue
            }
        }
        return titles
    }
}
