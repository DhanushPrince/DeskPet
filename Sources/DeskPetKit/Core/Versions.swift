import Foundation

/// Semver comparison ported from `src/shared/versions.ts`.
public enum Versions {
    public static func normalize(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    /// - Returns: `1` if `left` is greater, `-1` if `right` is greater, `0` if equal.
    public static func compare(_ left: String, _ right: String) -> Int {
        let (leftCore, leftPreRelease) = splitPreRelease(normalize(left))
        let (rightCore, rightPreRelease) = splitPreRelease(normalize(right))
        let leftParts = leftCore.split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = rightCore.split(separator: ".").map { Int($0) ?? 0 }
        let length = max(leftParts.count, rightParts.count)

        for index in 0..<length {
            let leftPart = index < leftParts.count ? leftParts[index] : 0
            let rightPart = index < rightParts.count ? rightParts[index] : 0
            if leftPart > rightPart { return 1 }
            if leftPart < rightPart { return -1 }
        }

        if leftPreRelease.isEmpty && !rightPreRelease.isEmpty { return 1 }
        if !leftPreRelease.isEmpty && rightPreRelease.isEmpty { return -1 }
        return leftPreRelease.compare(rightPreRelease, options: .literal).rawValue
    }

    /// JavaScript `split("-", 2)`: at most one split on the first hyphen.
    private static func splitPreRelease(_ version: String) -> (String, String) {
        guard let hyphen = version.firstIndex(of: "-") else {
            return (version, "")
        }
        return (String(version[..<hyphen]), String(version[version.index(after: hyphen)...]))
    }
}
