import AppKit
import Foundation

/// Resolves `PetAssetDefinition` paths to on-disk URLs.
///
/// Replaces the Electron build's `pawpal-asset://` custom protocol handler.
/// The two roots it guarded are preserved: bundled assets under the app's
/// resource bundle, and imported assets under Application Support.
public enum PetAssetLoader {
    /// `Resources/PetAssets` inside the DeskPetKit resource bundle.
    public static let bundledRoot: URL? = {
        // `Bundle.module.resourceURL` points at the bundle's Resources dir; the
        // SPM `.copy` rule places PetAssets directly inside it.
        guard let resources = Bundle.module.resourceURL else { return nil }
        let root = resources.appendingPathComponent("PetAssets", isDirectory: true)
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }()

    /// Default `~/Library/Application Support/DeskPet`. Tests and debug launches
    /// point this at a temporary directory via `supportDirectory`.
    public static let defaultApplicationSupportRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(AppInfo.name, isDirectory: true)
    }()

    /// Directory that contains `custom_pet_assets/` and `stats.json`.
    public static var supportDirectory: URL = defaultApplicationSupportRoot

    /// `~/Library/Application Support/DeskPet`, shared with the Electron build
    /// so imported custom assets and the legacy store file are found in place.
    public static var applicationSupportRoot: URL { supportDirectory }

    public static var customAssetRoot: URL {
        supportDirectory.appendingPathComponent("custom_pet_assets", isDirectory: true)
    }

    /// Root directory for a definition's `source`.
    public static func root(for source: PetAssetSource) -> URL? {
        switch source {
        case .bundled: return bundledRoot
        case .custom: return supportDirectory
        }
    }

    /// URL for one variant of a definition. Returns nil when the index is out
    /// of range, the root is unavailable, or the resolved path escapes the root.
    public static func url(for definition: PetAssetDefinition, variant index: Int = 0) -> URL? {
        guard definition.paths.indices.contains(index),
              let root = root(for: definition.source) else { return nil }
        let url = root.appendingPathComponent(definition.paths[index])
        switch definition.source {
        case .bundled:
            guard isContained(url, in: root) else { return nil }
        case .custom:
            guard isInsideCustomRoot(url, supportDirectory: supportDirectory) else { return nil }
        }
        return url
    }

    /// True when `url` resolves inside `root` (the `pawpal-asset` containment check).
    public static func isContained(_ url: URL, in root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if path == rootPath { return true }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(prefix)
    }

    public static func isInsideCustomRoot(_ url: URL, supportDirectory: URL) -> Bool {
        let customRoot = supportDirectory.appendingPathComponent("custom_pet_assets", isDirectory: true)
        return isContained(url, in: customRoot)
    }

    /// Every variant URL for a definition, skipping any that cannot be rooted.
    public static func urls(for definition: PetAssetDefinition) -> [URL] {
        definition.paths.indices.compactMap { url(for: definition, variant: $0) }
    }

    public static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// First frame of an appearance's animation, for the settings preview.
    ///
    /// A still frame rather than a live animation: the picker shows several pets
    /// at once and animating all of them would be wasteful.
    public static func previewImage(
        for appearance: PetAppearanceID,
        custom: CustomPetAppearance? = nil,
        state: PetState = .idle
    ) -> NSImage? {
        let definition = PetAppearances.assetDefinition(
            appearance: appearance,
            state: state,
            custom: custom
        )
        guard let url = url(for: definition, variant: 0),
              let decoded = try? GIFDecoder.decode(url: url),
              let frame = decoded.frames.first
        else {
            return nil
        }
        return NSImage(cgImage: frame, size: decoded.pixelSize)
    }
}
