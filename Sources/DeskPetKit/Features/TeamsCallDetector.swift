import Foundation
import IOKit.pwr_mgt

/// Detects an active Microsoft Teams call via the system power assertion
/// Teams creates: `NoDisplaySleepAssertion` named
/// `"Microsoft Teams Call in progress"`.
///
/// Window titles are unreliable on New Teams (WebView); this matches what
/// production macOS scripts use (TeamsStatusMacOS, pmset-based detectors).
public enum TeamsCallDetector {
    public static let assertionNameNeedle = "Microsoft Teams Call in progress"

    /// True when any process holds a matching power assertion.
    public static func isInCall() -> Bool {
        isInCall(assertionNames: activeAssertionNames())
    }

    /// Pure classifier for tests.
    public static func isInCall(assertionNames: [String]) -> Bool {
        assertionNames.contains {
            $0.localizedCaseInsensitiveContains(assertionNameNeedle)
        }
    }

    /// Names of every active IOPM assertion on the system.
    public static func activeAssertionNames() -> [String] {
        var assertionsRef: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&assertionsRef)
        guard status == kIOReturnSuccess,
              let root = assertionsRef?.takeRetainedValue() as? [AnyHashable: Any]
        else {
            return []
        }

        let nameKey = kIOPMAssertionNameKey as String
        var names: [String] = []
        for (_, value) in root {
            guard let list = value as? [[String: Any]] else { continue }
            for assertion in list {
                if let name = assertion[nameKey] as? String, !name.isEmpty {
                    names.append(name)
                }
            }
        }
        return names
    }
}
