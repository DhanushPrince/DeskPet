import Foundation

public enum UpdateInstallerError: Error, Equatable {
    case downloadFailed
    case sizeMismatch
    case mountFailed
    case missingApp
    case notNewer
    case installFailed
}

/// Downloads, caches, and applies a GitHub `DeskPet.dmg` without Sparkle.
public protocol UpdateInstalling: AnyObject {
    func cachedDMG(version: String, expectedByteCount: Int?) -> URL?
    func download(from url: URL, version: String, expectedByteCount: Int?) async throws -> URL
    func stageApp(fromDMG dmgURL: URL, currentVersion: String) throws -> URL
    func stageCopiedApp(from sourceApp: URL, currentVersion: String) throws -> URL
    func installAndRelaunch(destination: URL, stagedApp: URL) throws
}

public final class FileUpdateInstaller: UpdateInstalling {
    private let supportDirectory: URL
    private let session: URLSession
    private let fileManager: FileManager

    public init(
        supportDirectory: URL,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.supportDirectory = supportDirectory
        self.session = session
        self.fileManager = fileManager
    }

    public var updatesDirectory: URL {
        supportDirectory.appendingPathComponent("updates", isDirectory: true)
    }

    public func dmgCacheURL(version: String) -> URL {
        updatesDirectory.appendingPathComponent("\(Versions.normalize(version)).dmg")
    }

    public func cachedDMG(version: String, expectedByteCount: Int?) -> URL? {
        let url = dmgCacheURL(version: version)
        guard let size = fileSize(url), size > 0 else { return nil }
        if let expectedByteCount, size != expectedByteCount { return nil }
        return url
    }

    public func download(from url: URL, version: String, expectedByteCount: Int?) async throws -> URL {
        try ensureUpdatesDirectory()
        let destination = dmgCacheURL(version: version)
        if let cached = cachedDMG(version: version, expectedByteCount: expectedByteCount) {
            return cached
        }

        let (temp, response) = try await session.download(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else { throw UpdateInstallerError.downloadFailed }

        let partial = destination.appendingPathExtension("partial")
        try? fileManager.removeItem(at: partial)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temp, to: partial)

        if let expectedByteCount, fileSize(partial) != expectedByteCount {
            try? fileManager.removeItem(at: partial)
            throw UpdateInstallerError.sizeMismatch
        }

        try fileManager.moveItem(at: partial, to: destination)
        return destination
    }

    /// Mounts the DMG, copies `DeskPet.app`, then detaches. Tests use `stageCopiedApp` instead.
    public func stageApp(fromDMG dmgURL: URL, currentVersion: String) throws -> URL {
        try ensureUpdatesDirectory()
        let mount = updatesDirectory.appendingPathComponent("mnt-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: mount) }

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", dmgURL.path, "-nobrowse", "-readonly", "-mountpoint", mount.path]
        attach.standardOutput = FileHandle.nullDevice
        attach.standardError = FileHandle.nullDevice
        try attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else { throw UpdateInstallerError.mountFailed }

        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mount.path, "-quiet"]
            detach.standardOutput = FileHandle.nullDevice
            detach.standardError = FileHandle.nullDevice
            try? detach.run()
            detach.waitUntilExit()
        }

        let bundled = mount.appendingPathComponent("DeskPet.app", isDirectory: true)
        guard fileManager.fileExists(atPath: bundled.path) else { throw UpdateInstallerError.missingApp }
        return try stageCopiedApp(from: bundled, currentVersion: currentVersion)
    }

    /// Copies an already-unpacked `.app` into `updates/stage/`. Used by tests with a folder fixture.
    public func stageCopiedApp(from sourceApp: URL, currentVersion: String) throws -> URL {
        try ensureUpdatesDirectory()
        let stage = updatesDirectory.appendingPathComponent("stage", isDirectory: true)
        let destination = stage.appendingPathComponent("DeskPet.app", isDirectory: true)
        try? fileManager.removeItem(at: stage)
        try fileManager.createDirectory(at: stage, withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceApp, to: destination)

        let version = bundleVersion(at: destination) ?? ""
        guard Versions.compare(version, currentVersion) > 0 else { throw UpdateInstallerError.notNewer }
        return destination
    }

    public func installAndRelaunch(destination: URL, stagedApp: URL) throws {
        try ensureUpdatesDirectory()
        let script = updatesDirectory.appendingPathComponent("install.sh")
        let body = """
        #!/bin/bash
        set -e
        DEST="$1"
        SRC="$2"
        i=0
        while pgrep -qx DeskPet; do
          i=$((i+1))
          [ "$i" -gt 50 ] && break
          sleep 0.2
        done
        rm -rf "$DEST"
        cp -R "$SRC" "$DEST"
        xattr -cr "$DEST" || true
        open "$DEST"
        rm -f "$0"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, destination.path, stagedApp.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateInstallerError.installFailed
        }
    }

    private func ensureUpdatesDirectory() throws {
        try fileManager.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)
    }

    private func fileSize(_ url: URL) -> Int? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    private func bundleVersion(at app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let dict = NSDictionary(contentsOf: plist)
        return dict?["CFBundleShortVersionString"] as? String
    }
}
