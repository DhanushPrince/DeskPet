import Foundation

public enum UpdateCheckStatus: String, Equatable, Sendable {
    case idle
    case checking
    case available
    case upToDate = "up-to-date"
    case error
}

public struct UpdateCheckResult: Equatable, Sendable {
    public var status: UpdateCheckStatus
    public var currentVersion: String
    public var latestVersion: String?
    public var releaseURL: URL
    public var error: String?

    public init(
        status: UpdateCheckStatus,
        currentVersion: String,
        latestVersion: String? = nil,
        releaseURL: URL = Constants.releasesURL,
        error: String? = nil
    ) {
        self.status = status
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseURL = releaseURL
        self.error = error
    }

    func failed(_ message: String) -> UpdateCheckResult {
        var next = self
        next.status = .error
        next.error = message
        return next
    }
}

public protocol UpdateChecking: AnyObject {
    func check(current: UpdateCheckResult) async -> UpdateCheckResult
}

/// Fetches `releases/latest` from GitHub. Ported from `src/main/updates.ts`.
public final class GitHubUpdateChecker: UpdateChecking {
    private let session: URLSession
    private let endpoint: URL

    public init(session: URLSession = .shared, endpoint: URL = Constants.releasesAPIURL) {
        self.session = session
        self.endpoint = endpoint
    }

    public func check(current: UpdateCheckResult) async -> UpdateCheckResult {
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(
            "\(Constants.appName)/\(current.currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                return current.failed("GitHub returned \(statusCode)")
            }
            return Self.parse(data, currentVersion: current.currentVersion)
        } catch {
            return current.failed(error.localizedDescription)
        }
    }

    /// Interprets a GitHub Releases JSON payload. Exposed so tests need no network.
    public static func parse(_ data: Data, currentVersion: String) -> UpdateCheckResult {
        struct Payload: Decodable {
            var tag_name: String?
            var html_url: String?
            var name: String?
        }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let latestVersion = payload.tag_name ?? payload.name ?? ""
            guard !latestVersion.isEmpty else {
                return UpdateCheckResult(
                    status: .error,
                    currentVersion: currentVersion,
                    error: "Latest release has no version tag"
                )
            }
            let releaseURL = payload.html_url.flatMap(URL.init(string:)) ?? Constants.releasesURL
            let available = Versions.compare(latestVersion, currentVersion) > 0
            return UpdateCheckResult(
                status: available ? .available : .upToDate,
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                releaseURL: releaseURL
            )
        } catch {
            return UpdateCheckResult(
                status: .error,
                currentVersion: currentVersion,
                error: "Unexpected release response"
            )
        }
    }
}
